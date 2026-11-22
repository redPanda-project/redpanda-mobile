@Tags(['lab'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
/// - `connect` / `hopCandidates`: per client, from `connect()` until the
///   first encrypted connection and until [RedPandaLightClient.defaultHopCount]
///   garlic hop candidates are known.
/// - `pairing`: from the moment Bob "scans the QR" until his first message
///   reaches Alice. A send that fails with `UnknownCounterpartException` is
///   repeated on the app outbox's backoff ([outboxBackoff]). Once Bob has
///   learned Alice's mailbox the lab sends at once, like the app's outbox,
///   which flushes a channel's pending messages on `CounterpartOhUpdate`.
///   The lab does that once, for the first mailbox Bob learns; the app does
///   it on every change of the set. A retry in the app that no such event
///   triggers waits for the outbox's 10 s check interval, which the lab does
///   not model.
///   [pairingBudget] is the limit for `firstDeliveryMs`.
///   `aliceLearnedBobMailboxMs` is read at the end of the pairing step, so it
///   is null for a creator who learns the joiner's mailbox after that;
///   `aliceLearnedBobMailboxAfterHelloMs` is filled in at the end of the
///   run: negative when she knew it before the hello, null when she never
///   learned it or the hello never arrived.
/// - `rounds`: [messagesPerRound] alternating messages, each sent the moment
///   the previous one arrived, started by the side that received last. One
///   round right after pairing, further warm rounds, and one after [idleGap]
///   of silence. Each round must finish within [conversationBudget].
/// - the `burst` round: each side sends two messages back to back. The second
///   one has no reply block to ride on, so the sender must know the
///   counterpart's mailbox, and it reaches the receiver while the poll cycle
///   that fetched the first one may still be running. Same budget.
///
/// Known limits of the instrument — read the numbers with them in mind:
///
/// - Both clients share one isolate, so their pure-Dart crypto competes for
///   one core, and with `RP_LAB_CLIENT_LOG` set both also write a debug log
///   (`clientDebugLog` in the report). Real devices do not share a CPU: this
///   makes the lab slower than reality.
/// - Pairing starts only after both clients know their hop candidates, and
///   the nodes are on loopback (or, for the testnet, wherever the lab runs —
///   next to the nodes that is ~0 ms). Both make the lab faster than reality.
/// - `hops` / `viaReplyBlock` are read from client-wide fields that the
///   client's own background sends (channel ACK, `oh_update`) also write, so
///   they are best effort.
///
/// Opt-in: set `RP_LAB=1`. `RP_LAB_NET=testnet` runs the same script against
/// the public testnet (the client's default seeds) instead of local nodes;
/// `RP_LAB_NODES` sets the local node count (default 5, at least 3);
/// `RP_LAB_WARM_ROUNDS` the number of warm rounds (default 2);
/// `RP_LAB_REPORT` is a file the JSON report is written to (it is always
/// printed as well); `RP_LAB_CLIENT_LOG` is a file that receives both
/// clients' debug log, stamped with the lab clock.
const Duration conversationBudget = Duration(seconds: 10);
const Duration pairingBudget = Duration(seconds: 30);
const int messagesPerRound = 5;

/// A message that has not arrived after this long counts as lost. (The app
/// re-queues a sent message when its routing ACK comes back negative or
/// times out after the client's 90 s `ackTimeout`; either way the user has
/// waited far longer than any budget here.)
const Duration lostAfter = Duration(seconds: 30);

/// The human gap between "Alice shows the QR" and "Bob has scanned it".
const Duration qrScanGap = Duration(seconds: 5);

/// Silence before the after-idle round — longer than the client's
/// `pollActivityWindow` (60 s), so the poll is meant to be back on its idle
/// cadence. Not verified: a late ACK or a redundancy sweep inside the gap
/// extends the window.
const Duration idleGap = Duration(seconds: 75);

/// The waits between the app outbox's attempts for a message that keeps
/// failing. `OutboxService._attempt` calls `markRetryAttempt`, which bumps
/// `retryCount` BEFORE `backoffFor(retryCount)` is evaluated, so the wait
/// after the first failure is `backoffFor(1)` = 30 s, not 10 s.
const List<Duration> outboxBackoff = [
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 4),
];

/// Pairing is abandoned (and the run fails) after this long.
const Duration pairingCutoff = Duration(minutes: 5);

/// No further round is started after this much lab time, so that the report
/// is written well before the test timeout.
const Duration labDeadline = Duration(minutes: 22);

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

  /// Polls [condition] every 50 ms; whether it held within [timeout].
  static Future<bool> waitUntil(
    bool Function() condition,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    while (!condition()) {
      if (watch.elapsed > timeout) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
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

/// Sends [content] once and records the outcome in [entry]; whether the
/// send was accepted by the client.
Future<bool> _sendOnce(
  _Party sender,
  String channelId,
  String content,
  Map<String, Object?> entry,
  Stopwatch clock,
) async {
  final sentMs = clock.elapsedMilliseconds;
  entry['sentAtMs'] = sentMs;
  try {
    await sender.client.sendMessage(channelId, content);
  } catch (e) {
    entry['sendError'] = e.toString();
    return false;
  }
  entry['sendReturnedMs'] = clock.elapsedMilliseconds - sentMs;
  entry['hops'] = sender.client.lastSendHopCount;
  entry['viaReplyBlock'] = sender.client.lastSendViaRgb;
  return true;
}

/// A round's report entry plus the side that received its last message
/// ([lastReceiver], null when nothing arrived) — that side opens the next
/// round.
typedef _RoundOutcome = ({Map<String, Object?> report, _Party? lastReceiver});

_RoundOutcome _roundOutcome(
  String label,
  List<Map<String, Object?>> messages,
  bool complete,
  int startMs,
  int? endMs,
  _Party? lastReceiver,
) {
  final totalMs = complete && endMs != null ? endMs - startMs : null;
  return (
    report: {
      'label': label,
      'complete': complete,
      'totalMs': totalMs,
      'withinBudget':
          totalMs != null && totalMs <= conversationBudget.inMilliseconds,
      'messages': messages,
    },
    lastReceiver: lastReceiver,
  );
}

/// Waits for [content] at [receiver] until [lostAfter] after it was SENT
/// ([sentMs] on the lab clock) and records the outcome in [entry]. An
/// arrival after that deadline counts as lost, also when it is already known
/// by the time this is called. The arrival time on the lab clock, or null.
Future<int?> _awaitArrival(
  _Party receiver,
  String content,
  Map<String, Object?> entry,
  int sentMs,
  Stopwatch clock,
) async {
  final deadlineMs = sentMs + lostAfter.inMilliseconds;
  final remainingMs = math.max(0, deadlineMs - clock.elapsedMilliseconds);
  final arrivedMs = await receiver.arrivalOf(
    content,
    Duration(milliseconds: remainingMs),
  );
  if (arrivedMs == null || arrivedMs > deadlineMs) {
    entry['lost'] = true;
    return null;
  }
  entry['latencyMs'] = arrivedMs - sentMs;
  return arrivedMs;
}

/// One conversation round: [messagesPerRound] alternating messages, each sent
/// once, the next one the moment the previous arrived. [first] sends #1.
Future<_RoundOutcome> _runRound(
  String label,
  String channelId,
  _Party first,
  _Party second,
  Stopwatch clock,
) async {
  final messages = <Map<String, Object?>>[];
  final startMs = clock.elapsedMilliseconds;
  int? endMs;
  _Party? lastReceiver;
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

    if (!await _sendOnce(sender, channelId, content, entry, clock)) {
      complete = false;
      break;
    }
    final arrivedMs = await _awaitArrival(
      receiver,
      content,
      entry,
      entry['sentAtMs']! as int,
      clock,
    );
    if (arrivedMs == null) {
      complete = false;
      break;
    }
    endMs = arrivedMs;
    lastReceiver = receiver;
  }
  return _roundOutcome(label, messages, complete, startMs, endMs, lastReceiver);
}

/// The burst round: [first] sends two messages back to back, then [second]
/// does. Every message is still sent once; all four must arrive.
Future<_RoundOutcome> _runBurst(
  String label,
  String channelId,
  _Party first,
  _Party second,
  Stopwatch clock,
) async {
  final messages = <Map<String, Object?>>[];
  final startMs = clock.elapsedMilliseconds;
  int? endMs;
  _Party? lastReceiver;
  var complete = true;
  var n = 0;

  for (final (sender, receiver) in [(first, second), (second, first)]) {
    final pending = <(String, Map<String, Object?>)>[];
    for (var k = 0; k < 2; k++) {
      n++;
      final content = 'lab $label #$n ${sender.name}->${receiver.name}';
      final entry = <String, Object?>{
        'n': n,
        'direction': '${sender.name}->${receiver.name}',
      };
      messages.add(entry);
      if (await _sendOnce(sender, channelId, content, entry, clock)) {
        pending.add((content, entry));
      } else {
        complete = false;
      }
    }
    for (final (content, entry) in pending) {
      final arrivedMs = await _awaitArrival(
        receiver,
        content,
        entry,
        entry['sentAtMs']! as int,
        clock,
      );
      if (arrivedMs == null) {
        complete = false;
        continue;
      }
      endMs = math.max(endMs ?? 0, arrivedMs);
      lastReceiver = receiver;
    }
    if (!complete) break;
  }
  return _roundOutcome(label, messages, complete, startMs, endMs, lastReceiver);
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
      : (!useTestnet && nodeCount < RedPandaLightClient.defaultHopCount)
      ? 'RP_LAB_NODES must be at least '
            '${RedPandaLightClient.defaultHopCount} (garlic needs relays)'
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
          // One side failing to close must not leave the other one running.
          try {
            await party.close();
          } catch (e) {
            print('lab: closing ${party.name} failed: $e');
          }
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
      final clientLogPath = Platform.environment['RP_LAB_CLIENT_LOG'];
      final logClients = clientLogPath != null && clientLogPath.isNotEmpty;
      final report = <String, Object?>{
        'net': useTestnet ? 'testnet' : 'local',
        'nodes': useTestnet ? null : nodeCount,
        'singleIsolate': true,
        'clientDebugLog': logClients,
        'budgets': {
          'conversationMs': conversationBudget.inMilliseconds,
          'pairingMs': pairingBudget.inMilliseconds,
          'messagesPerRound': messagesPerRound,
        },
      };
      final violations = <String>[];

      IOSink? clientLog;
      final previousSink = RpLog.sink;
      final previousLevel = RpLog.minLevel;
      if (logClients) {
        final sink = (File(
          clientLogPath,
        )..createSync(recursive: true)).openWrite();
        clientLog = sink;
        RpLog.minLevel = LogLevel.debug;
        RpLog.sink = (message, level) =>
            sink.writeln('[${clock.elapsedMilliseconds}] $message');
      }

      // Set once pairing has started; the tear-down completes the entry
      // with what the creator learned after the hello had arrived.
      Map<String, Object?>? pairingReport;
      _Party? creator;
      int? helloArrivedAtMs;

      // In a tear-down, not a `finally`: a test that runs into its timeout
      // is abandoned without unwinding, and that is exactly the run whose
      // report matters most.
      addTearDown(() async {
        final pairingEntry = pairingReport;
        if (pairingEntry != null) {
          // Always written once pairing has started, so a reader can tell
          // "never happened" (null) from a report cut off earlier.
          final helloAt = helloArrivedAtMs;
          final learnedMs = creator?.counterpartOhLearnedMs;
          pairingEntry['aliceLearnedBobMailboxAfterHelloMs'] =
              helloAt == null || learnedMs == null ? null : learnedMs - helloAt;
        }
        report['violations'] = violations;
        report['elapsedMs'] = clock.elapsedMilliseconds;
        RpLog.sink = previousSink;
        RpLog.minLevel = previousLevel;
        try {
          await clientLog?.flush();
          await clientLog?.close();
        } catch (e) {
          print('lab: closing the client log failed: $e');
        }
        try {
          _emitReport(report);
        } catch (e) {
          print('lab: writing the report failed: $e');
        }
      });

      // ── Network ──────────────────────────────────────────────────────
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

      // ── Cold start ───────────────────────────────────────────────────
      final connect = <String, Object?>{};
      final hopCandidates = <String, Object?>{};
      report['connect'] = connect;
      report['hopCandidates'] = hopCandidates;
      await Future.wait([
        for (final party in parties)
          () async {
            final startMs = clock.elapsedMilliseconds;
            await party.client.connect();
            final encrypted = await _Party.waitUntil(
              () => party.client.isEncryptionActive,
              const Duration(seconds: 60),
            );
            connect['${party.name}Ms'] = encrypted
                ? clock.elapsedMilliseconds - startMs
                : null;
            final enoughHops = await _Party.waitUntil(
              () =>
                  party.hopCandidates() >= RedPandaLightClient.defaultHopCount,
              const Duration(seconds: 120),
            );
            hopCandidates['${party.name}Ms'] = enoughHops
                ? clock.elapsedMilliseconds - startMs
                : null;
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

      // ── Pairing ──────────────────────────────────────────────────────
      final pairing = <String, Object?>{};
      report['pairing'] = pairing;
      pairingReport = pairing;
      creator = alice;

      // Registers [party]'s own mailbox in the background, like the app's
      // create/join screens do; the error text, or null when it worked.
      Future<String?> registerMailbox(_Party party, String channelId) async {
        final startMs = clock.elapsedMilliseconds;
        try {
          final oh = await party.client.registerOutboundHandle(
            channelId: channelId,
          );
          pairing['${party.name}RegisterMs'] =
              clock.elapsedMilliseconds - startMs;
          pairing['${party.name}MailboxOn'] = oh.serverEndpoint;
          return null;
        } catch (e) {
          return e.toString();
        }
      }

      // Alice creates the channel; the QR is on screen at once while her
      // mailbox registers in the background.
      final channel = await Channel.generate('Conversation lab');
      alice.client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        channelSecret: channel.channelSecret,
        isChannelCreator: true,
      );
      final aliceRegistration = registerMailbox(alice, channel.id);

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
      // The app registers Bob's mailbox in the background as well. Typing a
      // first message takes a human longer than the registration does, so
      // the lab waits for it before sending.
      final registrationErrors = await Future.wait([
        aliceRegistration,
        registerMailbox(bob, joined.id),
      ]);
      for (final error in registrationErrors) {
        if (error != null) fail('mailbox registration failed: $error');
      }

      // Bob says hello. A send that fails because Alice's mailbox is still
      // unknown kicks off the rendezvous lookup and is repeated on the app
      // outbox's backoff; once the mailbox is known the lab sends at once.
      const hello = 'lab pairing hello bob->alice';
      final attempts = <Map<String, Object?>>[];
      pairing['attempts'] = attempts;
      String? helloId;

      Future<bool> sendHello(String trigger) async {
        final atMs = clock.elapsedMilliseconds;
        final entry = <String, Object?>{
          'atMs': atMs - scanMs,
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
      for (var retry = 0; !sent; retry++) {
        final remainingMs = cutoffMs - clock.elapsedMilliseconds;
        if (remainingMs <= 0) break;
        final backoff =
            outboxBackoff[math.min(retry, outboxBackoff.length - 1)];
        // Never wait past the cutoff: a pairing that does not work must end
        // as a failed run with a report, not as a test timeout.
        final cutShort = backoff.inMilliseconds > remainingMs;
        final wait = cutShort ? Duration(milliseconds: remainingMs) : backoff;
        if (!sentOnLearning && await bob.learnsCounterpartOh(wait)) {
          sentOnLearning = true;
          sent = await sendHello('mailbox learned');
        } else {
          if (sentOnLearning) await Future<void>.delayed(wait);
          if (cutShort) break;
          sent = await sendHello('outbox backoff ${backoff.inSeconds} s');
        }
      }

      // A hello that was sent but did not arrive is a lost message: re-send
      // it (same id) so the rounds can still run, and report every attempt.
      // Every send, including the last re-send, gets its full wait.
      int? helloArrivedMs;
      for (var resend = 0; sent; resend++) {
        helloArrivedMs = await alice.arrivalOf(hello, lostAfter);
        if (helloArrivedMs != null || resend == 3) break;
        violations.add(
          'pairing hello was sent but did not arrive within '
          '${lostAfter.inSeconds} s',
        );
        sent = await sendHello('re-send after loss');
      }

      int? sinceScan(int? ms) => ms == null ? null : ms - scanMs;
      final firstDeliveryMs = sinceScan(helloArrivedMs);
      pairing['firstDeliveryMs'] = firstDeliveryMs;
      pairing['bobLearnedAliceMailboxMs'] = sinceScan(
        bob.counterpartOhLearnedMs,
      );
      pairing['aliceLearnedBobMailboxMs'] = sinceScan(
        alice.counterpartOhLearnedMs,
      );
      helloArrivedAtMs = helloArrivedMs;
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

      // ── Conversation rounds ──────────────────────────────────────────
      final rounds = <Map<String, Object?>>[];
      report['rounds'] = rounds;

      // Bob's hello arrived last, so Alice opens; after that the opener is
      // the side that received the last message that actually ARRIVED in
      // the previous round — also when that round stopped early. A round in
      // which nothing arrived leaves the opener as it was.
      var opener = alice;
      var other = bob;

      Future<void> round(String label, {bool burst = false}) async {
        if (clock.elapsed > labDeadline) {
          violations.add(
            'round "$label" skipped: the lab ran past '
            '${labDeadline.inMinutes} min',
          );
          return;
        }
        final outcome = burst
            ? await _runBurst(label, channel.id, opener, other, clock)
            : await _runRound(label, channel.id, opener, other, clock);
        final result = outcome.report;
        rounds.add(result);
        if (outcome.lastReceiver == other) {
          (opener, other) = (other, opener);
        }
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
      await round('burst', burst: true);
      await Future<void>.delayed(idleGap);
      await round('afterIdle');

      expect(violations, isEmpty, reason: violations.join('\n'));
    }, skip: skip);
  });
}
