import 'dart:isolate';

import 'package:redpanda_light_client/src/client/isolate_client.dart';
import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:test/test.dart';

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
}
