import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:redpanda_light_client/src/client/isolate_client.dart';
import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/diagnostics/diag_catalogue.dart';
import 'package:redpanda_light_client/src/diagnostics/rp_diag.dart';
import 'package:redpanda_light_client/src/diagnostics/rp_network.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';
import 'package:test/test.dart';

import '../helpers/wait_for.dart';

/// Fake worker for the T180 forwarding tests: uses the real worker-side
/// diagnostics wiring ([installWorkerDiagnostics] /
/// [handleWorkerDiagnosticsCommand]), reports lifecycle steps via [EventLog],
/// emits one `test.ping` per [CmdAddPeer] (attribute `n` = the address) and
/// crashes on [CmdDisconnect].
void diagWorkerEntry(SendPort mainSendPort) {
  installWorkerDiagnostics(mainSendPort);
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (handleWorkerDiagnosticsCommand(message)) {
      mainSendPort.send(EventLog('diag:${RpDiag.enabled}'));
      return;
    }
    if (message is CmdInit) mainSendPort.send(EventLog('init'));
    if (message is CmdAddPeer) {
      RpDiag.emit('test.ping', {'n': message.address});
    }
    if (message is CmdDisconnect) throw StateError('simulated worker crash');
  });
}

/// The same fake worker, but the build inside it belongs to another network.
void foreignNetworkWorkerEntry(SendPort mainSendPort) {
  RpDiag.networkId = 'mainnet';
  diagWorkerEntry(mainSendPort);
}

void main() {
  final events = <DiagEvent>[];

  setUp(() {
    RpDiag.resetForTesting();
    events.clear();
    RpDiag.sink = events.add;
  });

  tearDown(RpDiag.resetForTesting);

  group('network gate', () {
    test('this build is a testnet build and diagnostics are available', () {
      expect(RpNetwork.id, RpNetwork.testnet);
      expect(RpDiag.available, isTrue);
    });

    for (final foreign in ['mainnet', 'devnet', '', 'Testnet']) {
      test('network id "$foreign": switching on is refused, nothing is '
          'emitted, nobody is told', () {
        RpDiag.networkId = foreign;
        final told = <bool>[];
        RpDiag.addListener(told.add);

        RpDiag.setEnabled(true);
        RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: '1.2.3.4:5'});
        RpDiag.deliver(const DiagEvent('conn.up', 1, {}));

        expect(RpDiag.available, isFalse);
        expect(RpDiag.enabled, isFalse);
        expect(events, isEmpty);
        expect(told, isEmpty);
      });
    }
  });

  group('RpDiag channel', () {
    test('off by default: emit is a no-op', () {
      RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
      expect(RpDiag.enabled, isFalse);
      expect(events, isEmpty);
    });

    test('on: events carry the device time and cleaned attributes', () {
      RpDiag.setEnabled(true);
      final before = DateTime.now().millisecondsSinceEpoch;
      RpDiag.emit(DiagEvt.sendAttempt, {
        DiagKey.msg: 'ab',
        DiagKey.route: 0,
        DiagKey.selfHop: false,
        DiagKey.hops: ['n1', 'n2'],
        DiagKey.ackTag: null,
      });
      final after = DateTime.now().millisecondsSinceEpoch;

      final event = events.single;
      expect(event.name, DiagEvt.sendAttempt);
      expect(event.tMs, inInclusiveRange(before, after));
      expect(event.attrs, {
        DiagKey.msg: 'ab',
        DiagKey.route: 0,
        DiagKey.selfHop: false,
        DiagKey.hops: 'n1,n2',
      });
    });

    test('switching off stops emission; listeners see every change', () {
      final told = <bool>[];
      RpDiag.addListener(told.add);
      RpDiag.setEnabled(true);
      RpDiag.setEnabled(true); // no change, no call
      RpDiag.setEnabled(false);
      RpDiag.emit(DiagEvt.connUp);
      expect(told, [true, false]);
      expect(events, isEmpty);
    });

    test('a throwing sink never reaches the caller', () {
      RpDiag.setEnabled(true);
      RpDiag.sink = (_) => throw StateError('sink broken');
      expect(() => RpDiag.emit(DiagEvt.connUp), returnsNormally);
      expect(RpDiag.sinkErrors, 1);
    });

    test('the rate limit bounds a burst and counts the drops', () {
      RpDiag.setEnabled(true);
      for (var i = 0; i < RpDiag.maxEventsPerWindow + 25; i++) {
        RpDiag.emit(DiagEvt.fetchItem, {DiagKey.items: i});
      }
      expect(events, hasLength(RpDiag.maxEventsPerWindow));
      expect(RpDiag.takeDropped(), 25);
      expect(RpDiag.dropped, 0);
    });

    test('hash16 is the first 16 hex chars of SHA-256', () {
      // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223…
      expect(RpDiag.hash16('abc'.codeUnits), 'ba7816bf8f01cfea');
    });
  });

  group('catalogue', () {
    test('event names are unique, keys are unique per event and never an '
        'envelope key', () {
      for (final entry in DiagCatalogue.events.entries) {
        expect(
          entry.value.toSet(),
          hasLength(entry.value.length),
          reason: '${entry.key} lists a key twice',
        );
        for (final key in entry.value) {
          expect(DiagKey.envelope, isNot(contains(key)), reason: entry.key);
          expect(key, isNot(startsWith(DiagKey.prefix)));
        }
      }
    });
  });

  group('isolate forwarding', () {
    final logs = <String>[];
    late void Function(String, LogLevel) previousSink;

    setUp(() {
      logs.clear();
      previousSink = RpLog.sink;
      RpLog.sink = (message, level) => logs.add(message);
    });
    tearDown(() => RpLog.sink = previousSink);

    Future<void> waitForLog(String needle, {int count = 1}) => waitFor(
      () => logs.where((l) => l.contains(needle)).length >= count,
      timeout: const Duration(seconds: 20),
      message: () => 'no $count x "$needle" in $logs',
    );

    Iterable<String> pings() => events
        .where((e) => e.name == 'test.ping')
        .map((e) => e.attrs['n']! as String);

    test('runtime toggle reaches the worker, events cross to the main '
        'isolate, and the switch survives a worker respawn', () async {
      final client = RedPandaIsolateClient(workerEntryPoint: diagWorkerEntry);
      addTearDown(client.dispose);
      await waitForLog('[worker] init');

      // Off: the worker emits nothing (nothing is even sent over the port).
      await client.addPeer('off-1');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(pings(), isEmpty);

      RpDiag.setEnabled(true);
      await waitForLog('diag:true');
      await client.addPeer('on-1');
      await waitFor(() => pings().contains('on-1'));
      final ping = events.firstWhere((e) => e.attrs['n'] == 'on-1');
      expect(
        ping.tMs,
        closeTo(DateTime.now().millisecondsSinceEpoch, 20000),
        reason: 'the worker stamps its own device time',
      );

      // Respawn: the new worker is switched on BEFORE its CmdInit.
      unawaited(client.disconnect());
      await waitForLog('[worker] init', count: 2);
      final secondInit = logs.lastIndexOf('[worker] init');
      final secondDiag = logs.lastIndexOf('[worker] diag:true');
      expect(secondDiag, lessThan(secondInit));
      await client.addPeer('after-respawn');
      await waitFor(() => pings().contains('after-respawn'));

      // Off again: the worker stops, and the main side drops stragglers.
      RpDiag.setEnabled(false);
      await waitForLog('diag:false');
      final count = events.length;
      await client.addPeer('off-2');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events, hasLength(count));
    });

    test('a worker built for another network refuses to switch on', () async {
      final client = RedPandaIsolateClient(
        workerEntryPoint: foreignNetworkWorkerEntry,
      );
      addTearDown(client.dispose);
      await waitForLog('[worker] init');
      RpDiag.setEnabled(true); // main isolate is a testnet build in tests
      await waitForLog('diag:false');
      await client.addPeer('x');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(pings(), isEmpty);
    });
  });

  group('connection events from the real client', () {
    Future<RedPandaLightClient> failingClient() async {
      final keys = await KeyPair.generate();
      final client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: const ['192.0.2.1:59558'],
        peerRepository: InMemoryPeerRepository(),
        socketFactory: (h, p) async =>
            throw const SocketException('test: unreachable'),
      );
      return client;
    }

    test('a failed dial produces conn.down and conn.backoff', () async {
      RpDiag.setEnabled(true);
      final client = await failingClient();
      addTearDown(client.disconnect);
      await client.connect();
      await waitFor(
        () => events.any((e) => e.name == DiagEvt.connBackoff),
        description: 'conn.backoff',
      );
      final down = events.firstWhere((e) => e.name == DiagEvt.connDown);
      expect(down.attrs[DiagKey.addr], '192.0.2.1:59558');
      expect(down.attrs[DiagKey.reason], startsWith('dial_failed'));
      expect(down.attrs[DiagKey.wasUp], isFalse);
      expect(down.attrs[DiagKey.intentional], isFalse);
      final backoff = events.firstWhere((e) => e.name == DiagEvt.connBackoff);
      expect(backoff.attrs, {
        DiagKey.addr: '192.0.2.1:59558',
        DiagKey.retry: 1,
        DiagKey.waitMs: 2000,
      });
      for (final e in events) {
        expect(
          DiagCatalogue.events[e.name],
          containsAll(e.attrs.keys),
          reason: '${e.name} carries a key outside the catalogue',
        );
      }
    });

    test('diagnostics off: the same failure produces nothing', () async {
      final client = await failingClient();
      addTearDown(client.disconnect);
      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events, isEmpty);
    });
  });

  group('idle and offline volume', () {
    const seedA = '192.0.2.1:59558';
    const seedB = '192.0.2.2:59558';

    test('a one-hour outage reports each address once and keeps the start '
        'of the outage', () async {
      RpDiag.setEnabled(true);
      var now = DateTime.utc(2026, 11, 22, 15, 55);
      var dials = 0;
      final keys = await KeyPair.generate();
      final client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: const [seedA, seedB],
        peerRepository: InMemoryPeerRepository(),
        now: () => now,
        socketFactory: (h, p) async {
          dials++;
          throw const SocketException(
            'Connection failed (OS Error: Network is unreachable, errno = 101)',
          );
        },
      );
      addTearDown(client.disconnect);
      await client.connect();
      await waitFor(() => dials >= 2, description: 'first dials');

      // One hour in 31 s steps: every step expires both backoffs.
      for (var i = 0; i < 120; i++) {
        now = now.add(const Duration(seconds: 31));
        final before = dials;
        await client.addPeer(seedA);
        await waitFor(() => dials >= before + 2, description: 'redial $i');
      }

      final connEvents = events
          .where(
            (e) => e.name == DiagEvt.connDown || e.name == DiagEvt.connBackoff,
          )
          .toList();
      expect(dials, greaterThan(240));
      expect(
        connEvents.length,
        lessThanOrEqualTo(4),
        reason: 'one conn.down + conn.backoff per address, not one per dial',
      );
      expect(connEvents.first.name, DiagEvt.connDown);
      expect(connEvents.first.attrs[DiagKey.reason], startsWith('dial_failed'));
      expect(
        client.diagSuppressedDialsForTesting,
        dials - connEvents.where((e) => e.name == DiagEvt.connDown).length,
      );

      // The suppressed count reaches the summary (window > heartbeat).
      client.diagFlushFetchSummaryForTesting();
      now = now.add(const Duration(minutes: 1));
      client.diagFlushFetchSummaryForTesting();
      final summary = events.lastWhere((e) => e.name == DiagEvt.fetchSummary);
      expect(summary.attrs[DiagKey.dialFail], greaterThan(200));
      expect(client.diagSuppressedDialsForTesting, 0);
    });

    test('fetch.summary: silent while idle, a heartbeat every 15 min, at '
        'once after a failure', () async {
      RpDiag.setEnabled(true);
      var now = DateTime.utc(2026, 11, 22, 12);
      final keys = await KeyPair.generate();
      final client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: const [],
        peerRepository: InMemoryPeerRepository(),
        now: () => now,
        socketFactory: (h, p) async =>
            throw const SocketException('test: unreachable'),
      );
      addTearDown(client.disconnect);
      List<DiagEvent> summaries() =>
          events.where((e) => e.name == DiagEvt.fetchSummary).toList();

      client.diagFlushFetchSummaryForTesting(); // opens the window
      for (var minute = 1; minute < 15; minute++) {
        now = now.add(const Duration(minutes: 1));
        client.diagFlushFetchSummaryForTesting();
      }
      expect(summaries(), isEmpty, reason: 'nothing happened for 14 min');

      now = now.add(const Duration(minutes: 1, seconds: 1));
      client.diagFlushFetchSummaryForTesting();
      expect(summaries(), hasLength(1), reason: 'the 15-min heartbeat');

      // A failing fetch makes the next minute interesting.
      final oh = OHRegistration(
        ohId: List.generate(20, (i) => i),
        keypair: await OHKeypair.generate(),
        expiresAtMs: DateTime.now()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch,
        channelId: 'chan',
        serverEndpoint: 'dead:1',
      );
      await client.fetchMessages(oh);
      now = now.add(const Duration(seconds: 30));
      client.diagFlushFetchSummaryForTesting();
      expect(summaries(), hasLength(1), reason: 'less than a minute');
      now = now.add(const Duration(seconds: 31));
      client.diagFlushFetchSummaryForTesting();
      expect(summaries(), hasLength(2));
      expect(summaries().last.attrs[DiagKey.fetchFail], 1);

      now = now.add(const Duration(minutes: 2));
      client.diagFlushFetchSummaryForTesting();
      expect(summaries(), hasLength(2), reason: 'idle again');
    });
  });
}
