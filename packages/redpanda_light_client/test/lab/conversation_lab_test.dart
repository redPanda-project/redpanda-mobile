@Tags(['lab'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/counterpart_oh_update.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

import '../e2e/redpanda_node_launcher.dart';

/// Conversation lab: can two light clients hold a short back-and-forth
/// conversation over a multi-node network within a wall-clock budget?
///
/// This is the product gate that precedes any field test on real phones: as
/// long as five alternating messages do not complete within
/// [conversationBudget] here, on loopback, with nothing else going on, there
/// is no point in testing on devices or looking for users.
///
/// Unlike the functional e2e suites, nothing here is retried and nothing is
/// pinned: every message is sent exactly ONCE, the clients pick their own
/// connections and garlic hops, and the two sides pair the way the app does
/// (`addChannelKeys` with the channel secret, then `registerOutboundHandle` —
/// see `create_channel_screen.dart` / `join_channel_screen.dart`). A message
/// that needs a second attempt is a finding, not a pass.
///
/// This is deliberately NOT what the emulator duo gate measures: that gate
/// runs against a single node and hands the two apps each other's mailbox
/// over its coord server, so it exercises neither the rendezvous lookup nor
/// multi-hop routes between nodes. Both are in play here.
///
/// What is measured (all in the JSON report, see [_emitReport]):
///
/// - `connect` / `hopCandidates`: cold start of each client.
/// - `pairing`: from the moment Bob "scans the QR" until his first message
///   reaches Alice. A send that fails with `UnknownCounterpartException` is
///   repeated on the app outbox's backoff (10 s, 30 s, 1 min, …), because
///   those failing sends are what triggers the rendezvous lookup. The lab
///   does not sit out the backoff once Bob has learned Alice's mailbox — it
///   sends at once, so `firstDeliveryMs` is the best the protocol can do and
///   `appNextAttemptMs` is when the app's outbox would have tried again.
///   [pairingBudget] is the limit for `firstDeliveryMs`.
/// - `rounds`: [messagesPerRound] alternating messages, each sent the moment
///   the previous one arrived. One round right after pairing, further warm
///   rounds, and one after [idleGap] of silence (the mailbox poll has fallen
///   back to its idle cadence by then). Each round must finish within
///   [conversationBudget].
///
/// Opt-in: set `RP_LAB=1`. `RP_LAB_NET=testnet` runs the same script against
/// the public testnet (the client's default seeds) instead of local nodes;
/// `RP_LAB_NODES` sets the local node count (default 5); `RP_LAB_REPORT` is a
/// file the JSON report is written to (it is always printed as well);
/// `RP_LAB_CLIENT_LOG` is a file that receives both clients' debug log,
/// stamped with the lab clock.
const Duration conversationBudget = Duration(seconds: 10);
const Duration pairingBudget = Duration(seconds: 30);
const int messagesPerRound = 5;

/// A message that has not arrived after this long counts as lost (the app
/// would only re-send it after the outbox's 3-minute stale-sent threshold).
const Duration lostAfter = Duration(seconds: 60);

/// The human gap between "Alice shows the QR" and "Bob has scanned it".
const Duration qrScanGap = Duration(seconds: 5);

/// Silence before the after-idle round — longer than the client's
/// `pollActivityWindow` (60 s), so the poll is back on its idle cadence.
const Duration idleGap = Duration(seconds: 75);

/// The app outbox's retry schedule for a message whose counterpart mailbox
/// is still unknown (`OutboxService.backoffFor`).
const List<Duration> outboxBackoff = [
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 4),
  Duration(minutes: 8),
];

/// Pairing is abandoned (and the run fails) after this long.
const Duration pairingCutoff = Duration(minutes: 10);

bool _envFlag(String name) {
  final value = Platform.environment[name]?.trim().toLowerCase();
  return value == 'true' || value == '1';
}

/// One side of the conversation: a client plus timestamped observations.
class _Party {
  _Party(this.name, this.client, this._clock) {
    _messageSub = client.incomingMessages.listen((m) {
      arrivals.putIfAbsent(m.content, () => _clock.elapsedMilliseconds);
      _waiters.remove(m.content)?.complete();
    });
    _ohSub = client.stateUpdates.of<CounterpartOhUpdate>().listen((_) {
      counterpartOhLearnedMs ??= _clock.elapsedMilliseconds;
      if (!_ohLearned.isCompleted) _ohLearned.complete();
    });
  }

  final String name;
  final RedPandaLightClient client;
  final Stopwatch _clock;

  /// Message content → lab clock (ms) of its FIRST arrival.
  final Map<String, int> arrivals = {};
  final Map<String, Completer<void>> _waiters = {};

  /// Lab clock (ms) at which this side first learned a counterpart mailbox.
  int? counterpartOhLearnedMs;
  final Completer<void> _ohLearned = Completer<void>();

  /// Whether this side has learned a counterpart mailbox within [timeout].
  Future<bool> learnsCounterpartOh(Duration timeout) async {
    try {
      await _ohLearned.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  late final StreamSubscription<Object?> _messageSub;
  late final StreamSubscription<Object?> _ohSub;

  /// The lab clock (ms) at which [content] arrived, or null after [timeout].
  Future<int?> arrivalOf(String content, Duration timeout) async {
    final known = arrivals[content];
    if (known != null) return known;
    final waiter = _waiters.putIfAbsent(content, Completer<void>.new);
    try {
      await waiter.future.timeout(timeout);
    } on TimeoutException {
      _waiters.remove(content);
      return null;
    }
    return arrivals[content];
  }

  int hopCandidates() => client
      .getDebugPeerStats()
      .where((p) => p.encryptionPublicKey != null && p.nodeId != null)
      .length;

  Future<void> close() async {
    await _messageSub.cancel();
    await _ohSub.cancel();
    await client.disconnect();
  }
}

Future<_Party> _newParty(
  String name,
  Stopwatch clock,
  List<String>? seeds,
) async {
  final keys = await KeyPair.generate();
  final client = seeds == null
      ? RedPandaLightClient(
          selfNodeId: NodeId.fromPublicKey(keys),
          selfKeys: keys,
        )
      : RedPandaLightClient(
          selfNodeId: NodeId.fromPublicKey(keys),
          selfKeys: keys,
          seeds: seeds,
        );
  return _Party(name, client, clock);
}

/// Polls [condition] every 50 ms; the elapsed ms when it held, or null after
/// [timeout].
Future<int?> _timeUntil(bool Function() condition, Duration timeout) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) return null;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return watch.elapsedMilliseconds;
}

/// One conversation round: [messagesPerRound] alternating messages, each sent
/// once, the next one the moment the previous arrived.
Future<Map<String, Object?>> _runRound(
  String label,
  String channelId,
  _Party first,
  _Party second,
  Stopwatch clock,
) async {
  final messages = <Map<String, Object?>>[];
  final startMs = clock.elapsedMilliseconds;
  int? endMs;
  var complete = true;

  for (var i = 1; i <= messagesPerRound; i++) {
    final sender = i.isOdd ? first : second;
    final receiver = i.isOdd ? second : first;
    final content = 'lab $label #$i ${sender.name}->${receiver.name}';
    final entry = <String, Object?>{
      'n': i,
      'direction': '${sender.name}->${receiver.name}',
    };
    messages.add(entry);

    final sentMs = clock.elapsedMilliseconds;
    try {
      await sender.client.sendMessage(channelId, content);
    } catch (e) {
      entry['sendError'] = e.toString();
      complete = false;
      break;
    }
    entry['sendReturnedMs'] = clock.elapsedMilliseconds - sentMs;
    entry['hops'] = sender.client.lastSendHopCount;
    entry['viaReplyBlock'] = sender.client.lastSendViaRgb;

    final arrivedMs = await receiver.arrivalOf(content, lostAfter);
    if (arrivedMs == null) {
      entry['lost'] = true;
      complete = false;
      break;
    }
    entry['latencyMs'] = arrivedMs - sentMs;
    endMs = arrivedMs;
  }

  final totalMs = complete && endMs != null ? endMs - startMs : null;
  return {
    'label': label,
    'complete': complete,
    'totalMs': totalMs,
    'withinBudget':
        totalMs != null && totalMs <= conversationBudget.inMilliseconds,
    'messages': messages,
  };
}

void _emitReport(Map<String, Object?> report) {
  final json = const JsonEncoder.withIndent('  ').convert(report);
  // Markers so the report can be cut out of the (very chatty) node output.
  print('=== LAB REPORT BEGIN ===\n$json\n=== LAB REPORT END ===');
  final path = Platform.environment['RP_LAB_REPORT'];
  if (path != null && path.isNotEmpty) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');
  }
}

void main() {
  final enabled = _envFlag('RP_LAB');
  final useTestnet = Platform.environment['RP_LAB_NET'] == 'testnet';
  final nodeCount =
      int.tryParse(Platform.environment['RP_LAB_NODES'] ?? '') ?? 5;
  final warmRounds =
      int.tryParse(Platform.environment['RP_LAB_WARM_ROUNDS'] ?? '') ?? 2;

  // The JAR guard throws in CI when the JAR is missing — only ask when the
  // lab actually runs against local nodes.
  final String? skip = !enabled
      ? 'conversation lab is opt-in: set RP_LAB=1'
      : (!useTestnet && !e2eJarAvailable())
      ? 'RedPanda JAR not found'
      : null;

  const basePort = 50700;
  final nodeAddresses = [
    for (var i = 0; i < nodeCount; i++) '127.0.0.1:${basePort + i}',
  ];

  group('Conversation lab', () {
    final launchers = <RedPandaNodeLauncher>[];
    final parties = <_Party>[];

    tearDown(() async {
      try {
        for (final party in parties) {
          await party.close();
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      } finally {
        for (final launcher in launchers) {
          await launcher.stop();
        }
        launchers.clear();
        parties.clear();
      }
    });

    test('$messagesPerRound alternating messages complete within '
        '${conversationBudget.inSeconds} s', () async {
      final clock = Stopwatch()..start();
      final report = <String, Object?>{
        'net': useTestnet ? 'testnet' : 'local',
        'nodes': useTestnet ? null : nodeCount,
        'budgets': {
          'conversationMs': conversationBudget.inMilliseconds,
          'pairingMs': pairingBudget.inMilliseconds,
          'messagesPerRound': messagesPerRound,
        },
      };
      final violations = <String>[];

      IOSink? clientLog;
      final clientLogPath = Platform.environment['RP_LAB_CLIENT_LOG'];
      final previousSink = RpLog.sink;
      final previousLevel = RpLog.minLevel;
      if (clientLogPath != null && clientLogPath.isNotEmpty) {
        final sink = (File(
          clientLogPath,
        )..createSync(recursive: true)).openWrite();
        clientLog = sink;
        RpLog.minLevel = LogLevel.debug;
        RpLog.sink = (message, level) =>
            sink.writeln('[${clock.elapsedMilliseconds}] $message');
      }

      try {
        // ── Network ────────────────────────────────────────────────────
        if (!useTestnet) {
          for (var i = 0; i < nodeCount; i++) {
            launchers.add(
              RedPandaNodeLauncher(
                port: basePort + i,
                seeds: [
                  for (final address in nodeAddresses)
                    if (address != nodeAddresses[i]) address,
                ],
              ),
            );
          }
          await Future.wait(launchers.map((l) => l.start()));
          report['networkUpMs'] = clock.elapsedMilliseconds;
        }

        // Like the app: every client starts from the same two seeds and
        // discovers the rest of the network on its own.
        final seeds = useTestnet ? null : nodeAddresses.take(2).toList();
        final alice = await _newParty('alice', clock, seeds);
        final bob = await _newParty('bob', clock, seeds);
        parties.addAll([alice, bob]);

        // ── Cold start ─────────────────────────────────────────────────
        final connect = <String, Object?>{};
        final hopCandidates = <String, Object?>{};
        report['connect'] = connect;
        report['hopCandidates'] = hopCandidates;
        await Future.wait([
          for (final party in parties)
            () async {
              await party.client.connect();
              connect['${party.name}Ms'] = await _timeUntil(
                () => party.client.isEncryptionActive,
                const Duration(seconds: 60),
              );
              hopCandidates['${party.name}Ms'] = await _timeUntil(
                () =>
                    party.hopCandidates() >=
                    RedPandaLightClient.defaultHopCount,
                const Duration(seconds: 120),
              );
              hopCandidates['${party.name}Known'] = party.hopCandidates();
            }(),
        ]);
        for (final party in parties) {
          if (connect['${party.name}Ms'] == null) {
            fail('${party.name} never got an encrypted connection');
          }
          if (hopCandidates['${party.name}Ms'] == null) {
            violations.add(
              '${party.name} knew only '
              '${hopCandidates['${party.name}Known']} garlic hop '
              'candidates after 120 s',
            );
          }
        }

        // ── Pairing ────────────────────────────────────────────────────
        final pairing = <String, Object?>{};
        report['pairing'] = pairing;

        // Alice creates the channel and shows the QR.
        final channel = await Channel.generate('Conversation lab');
        final createMs = clock.elapsedMilliseconds;
        alice.client.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          channelSecret: channel.channelSecret,
          isChannelCreator: true,
        );
        final aliceOh = await alice.client.registerOutboundHandle(
          channelId: channel.id,
        );
        pairing['aliceRegisterMs'] = clock.elapsedMilliseconds - createMs;
        pairing['aliceMailboxOn'] = aliceOh.serverEndpoint;

        await Future<void>.delayed(qrScanGap);

        // Bob scans it: all he gets is the channel secret.
        final joined = await Channel.fromJson(channel.toJson());
        final scanMs = clock.elapsedMilliseconds;
        bob.client.addChannelKeys(
          joined.id,
          joined.encryptionKey,
          channelSecret: joined.channelSecret,
          isChannelCreator: false,
        );
        final bobOh = await bob.client.registerOutboundHandle(
          channelId: joined.id,
        );
        pairing['bobRegisterMs'] = clock.elapsedMilliseconds - scanMs;
        pairing['bobMailboxOn'] = bobOh.serverEndpoint;

        // Bob says hello. A send that fails because Alice's mailbox is still
        // unknown kicks off the rendezvous lookup and is repeated on the app
        // outbox's backoff; once the mailbox is known the lab sends at once.
        const hello = 'lab pairing hello bob->alice';
        final attempts = <Map<String, Object?>>[];
        pairing['attempts'] = attempts;
        String? helloId;

        Future<bool> sendHello(String trigger) async {
          final entry = <String, Object?>{
            'atMs': clock.elapsedMilliseconds - scanMs,
            'trigger': trigger,
          };
          attempts.add(entry);
          try {
            helloId = await bob.client.sendMessage(
              joined.id,
              hello,
              messageId: helloId,
            );
            entry['result'] = 'sent';
            entry['hops'] = bob.client.lastSendHopCount;
            return true;
          } catch (e) {
            entry['result'] = e.toString();
            return false;
          }
        }

        final cutoffMs = scanMs + pairingCutoff.inMilliseconds;
        var sent = await sendHello('first');
        var sentOnLearning = false;
        for (
          var retry = 0;
          !sent && clock.elapsedMilliseconds < cutoffMs;
          retry++
        ) {
          final backoff =
              outboxBackoff[retry < outboxBackoff.length
                  ? retry
                  : outboxBackoff.length - 1];
          final nextAttemptMs =
              clock.elapsedMilliseconds + backoff.inMilliseconds;
          if (!sentOnLearning && await bob.learnsCounterpartOh(backoff)) {
            sentOnLearning = true;
            pairing['appNextAttemptMs'] = nextAttemptMs - scanMs;
            sent = await sendHello('lab: mailbox learned');
          } else {
            if (sentOnLearning) await Future<void>.delayed(backoff);
            sent = await sendHello('outbox backoff ${backoff.inSeconds} s');
          }
        }

        // A hello that was sent but did not arrive is a lost message: re-send
        // it (same id) so the rounds can still run, and report every attempt.
        int? helloArrivedMs;
        for (var resend = 0; sent && resend < 3; resend++) {
          helloArrivedMs = await alice.arrivalOf(hello, lostAfter);
          if (helloArrivedMs != null) break;
          violations.add(
            'pairing hello was sent but did not arrive within '
            '${lostAfter.inSeconds} s',
          );
          sent = await sendHello('re-send after loss');
        }
        int? sinceScan(int? ms) => ms == null ? null : ms - scanMs;
        pairing['firstDeliveryMs'] = sinceScan(helloArrivedMs);
        pairing['bobLearnedAliceMailboxMs'] = sinceScan(
          bob.counterpartOhLearnedMs,
        );
        pairing['aliceLearnedBobMailboxMs'] = sinceScan(
          alice.counterpartOhLearnedMs,
        );
        final firstDeliveryMs = sinceScan(helloArrivedMs);
        pairing['withinBudget'] =
            firstDeliveryMs != null &&
            firstDeliveryMs <= pairingBudget.inMilliseconds;
        if (firstDeliveryMs == null) {
          fail(
            'pairing never completed: Bob\'s first message did not reach '
            'Alice (${attempts.length} attempts)',
          );
        }
        if (firstDeliveryMs > pairingBudget.inMilliseconds) {
          violations.add(
            'pairing took ${firstDeliveryMs / 1000} s '
            '(budget ${pairingBudget.inSeconds} s, '
            '${attempts.length} attempts)',
          );
        }

        // ── Conversation rounds ────────────────────────────────────────
        final rounds = <Map<String, Object?>>[];
        report['rounds'] = rounds;

        Future<void> round(String label) async {
          final result = await _runRound(label, channel.id, alice, bob, clock);
          rounds.add(result);
          if (result['withinBudget'] != true) {
            violations.add(
              result['complete'] == true
                  ? 'round "$label" took '
                        '${(result['totalMs']! as int) / 1000} s '
                        '(budget ${conversationBudget.inSeconds} s)'
                  : 'round "$label" lost a message or failed to send',
            );
          }
        }

        await round('fresh');
        for (var i = 1; i <= warmRounds; i++) {
          await round('warm$i');
        }
        await Future<void>.delayed(idleGap);
        await round('afterIdle');
      } finally {
        report['violations'] = violations;
        report['elapsedMs'] = clock.elapsedMilliseconds;
        _emitReport(report);
        RpLog.sink = previousSink;
        RpLog.minLevel = previousLevel;
        await clientLog?.flush();
        await clientLog?.close();
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    }, skip: skip);
  });
}
