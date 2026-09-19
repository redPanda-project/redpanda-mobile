import 'dart:isolate';

import 'package:redpanda_light_client/src/client/isolate_client.dart';
import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/domain/rendezvous_state_update.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:test/test.dart';

/// A rendezvous merge state as `RendezvousManager.exportMergeState` produces
/// it: one counterpart entry with its `entry_ts` and mailbox list.
const mergeStateJson =
    '[{"pid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":"partner","ts":1700000000000,'
    '"ohs":[{"ep":"node:59558","id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","pk":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}]}]';

/// Fake worker for supervision tests: reports every received command back to
/// the main isolate via [EventLog] and crashes (uncaught error → isolate
/// death) when it receives [CmdDisconnect].
void crashableWorkerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    mainSendPort.send(EventLog('cmd:${message.runtimeType}'));
    if (message is CmdDisconnect) {
      throw StateError('simulated worker crash');
    }
  });
}

/// Fake worker for the TD117 respawn test: publishes a rendezvous merge
/// state (as the real worker does after a resolved DHT record) when it is
/// told to connect, reports every received command — including the payload of
/// a rendezvous restore — and crashes on [CmdDisconnect].
void rendezvousWorkerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    mainSendPort.send(EventLog('cmd:${message.runtimeType}'));
    if (message is CmdRestoreRendezvousState) {
      mainSendPort.send(
        EventLog('rendezvous:${message.channelId}:${message.mergeStateJson}'),
      );
    }
    if (message is CmdConnect) {
      mainSendPort.send(
        EventStateUpdate(
          const RendezvousStateUpdate(
            channelId: 'chan1',
            mergeStateJson: mergeStateJson,
          ),
        ),
      );
    }
    if (message is CmdDisconnect) {
      throw StateError('simulated worker crash');
    }
  });
}

void main() {
  final capturedLogs = <String>[];
  late LogLevel previousLevel;
  late void Function(String, LogLevel) previousSink;

  setUp(() {
    capturedLogs.clear();
    previousLevel = RpLog.minLevel;
    previousSink = RpLog.sink;
    RpLog.minLevel = LogLevel.debug;
    RpLog.sink = (message, level) => capturedLogs.add(message);
  });

  tearDown(() {
    RpLog.minLevel = previousLevel;
    RpLog.sink = previousSink;
  });

  Future<void> waitForLogCount(
    String needle,
    int count, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (capturedLogs.where((l) => l.contains(needle)).length >= count) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('timed out waiting for $count x "$needle"; logs: $capturedLogs');
  }

  test(
    'a crashed worker isolate is respawned and its state replayed',
    () async {
      final client = RedPandaIsolateClient(
        seeds: const [],
        workerEntryPoint: crashableWorkerEntry,
      );
      addTearDown(client.dispose);

      await client.connect();
      await waitForLogCount('cmd:CmdInit', 1);

      client.addChannelKeys(
        'chan1',
        List<int>.filled(32, 7),
        isChannelCreator: true,
      );
      await client.addPeer('10.0.0.1:1234');
      await waitForLogCount('cmd:CmdAddChannelKeys', 1);
      await waitForLogCount('cmd:CmdAddPeer', 1);

      // A send that the fake worker never answers: it must fail fast when the
      // worker dies instead of hanging into its 15s timeout.
      final pendingSend = client.sendMessage('chan1', 'hello');
      final pendingSendFails = expectLater(
        pendingSend,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('worker restarted'),
          ),
        ),
      );
      await waitForLogCount('cmd:CmdSendMessage', 1);

      // Crash the worker (the fake throws on CmdDisconnect; the uncaught
      // error kills its isolate — exactly what an unhandled SocketException
      // did before supervision existed).
      await client.disconnect();

      await pendingSendFails;

      // The supervisor must respawn the worker, re-init it and replay the
      // state-establishing commands.
      await waitForLogCount('cmd:CmdInit', 2);
      await waitForLogCount('cmd:CmdAddChannelKeys', 2);
      await waitForLogCount('cmd:CmdAddPeer', 2);
    },
  );

  test(
    'TD115: a one-off command sent in the respawn gap is delivered, not dropped',
    () async {
      final client = RedPandaIsolateClient(
        seeds: const [],
        workerEntryPoint: crashableWorkerEntry,
      );
      addTearDown(client.dispose);

      await client.connect();
      await waitForLogCount('cmd:CmdInit', 1);

      // Crash the worker and wait until the supervisor has NOTICED — from
      // here until the respawn (500 ms backoff) no worker is attached.
      await client.disconnect();
      await waitForLogCount('worker isolate died', 1);

      // Fire-and-forget, not part of the replay projection: before TD115 this
      // was logged as "Dropping command" and lost, and awaiting
      // `_isolateReady` would not have helped — it completed long ago.
      // ignore: unawaited_futures
      client.ensureOhRedundancy('chan1');
      expect(
        capturedLogs.where((l) => l.contains('cmd:CmdEnsureOhRedundancy')),
        isEmpty,
        reason: 'no worker is attached yet — the command must be buffered',
      );

      await waitForLogCount('cmd:CmdInit', 2);
      await waitForLogCount('cmd:CmdEnsureOhRedundancy', 1);
    },
  );

  test(
    'TD117: rendezvous merge state published by the worker survives a respawn',
    () async {
      final client = RedPandaIsolateClient(
        seeds: const [],
        workerEntryPoint: rendezvousWorkerEntry,
      );
      addTearDown(client.dispose);

      client.addChannelKeys(
        'chan1',
        List<int>.filled(32, 7),
        channelSecret: List<int>.filled(32, 8),
        isChannelCreator: true,
      );
      // The fake worker answers CmdConnect with the merge state a resolved
      // rendezvous record would have produced.
      await client.connect();
      await waitForLogCount('cmd:CmdInit', 1);
      await waitForLogCount('cmd:CmdAddChannelKeys', 1);

      await client.disconnect(); // crashes the worker
      await waitForLogCount('cmd:CmdInit', 2);
      await waitForLogCount('cmd:CmdAddChannelKeys', 2);

      // The merge state is replayed verbatim — before TD117 it lived only
      // inside the dead worker's RendezvousManager.
      await waitForLogCount('rendezvous:chan1:$mergeStateJson', 1);

      // ... and only AFTER the channel registration: the worker registers a
      // channel's rendezvous state in addChannelKeys, so entries restored
      // before that would have nowhere to go.
      final restoreIndex = capturedLogs.indexWhere(
        (l) => l.contains('cmd:CmdRestoreRendezvousState'),
      );
      final secondChannelIndex = capturedLogs.lastIndexWhere(
        (l) => l.contains('cmd:CmdAddChannelKeys'),
      );
      expect(restoreIndex, greaterThan(secondChannelIndex));
    },
  );
}
