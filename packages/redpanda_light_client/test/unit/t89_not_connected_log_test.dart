import 'dart:async';
import 'dart:io';

import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:test/test.dart';

/// T89(b): a client that fails to connect used to say nothing at all.
///
/// Everything the connection routine logs about a dial goes through
/// [RpLog.debug], which is suppressed by default and which the isolate worker
/// never forwards to the app — so when the emulator gate died with `client
/// never connected to the node` there was no way to tell "never dialled" from
/// "dialled and got nowhere". The connection check now emits one aggregate,
/// address-free info line while the client is not connected, throttled to 15 s
/// so it cannot flood a long outage (the check itself runs every 3 s).
void main() {
  late List<String> lines;
  late void Function(String, LogLevel) originalSink;

  setUp(() {
    lines = [];
    originalSink = RpLog.sink;
    RpLog.sink = (message, level) {
      if (level == LogLevel.info) lines.add(message);
    };
  });

  tearDown(() => RpLog.sink = originalSink);

  Future<RedPandaLightClient> deadClient() async {
    final keys = await KeyPair.generate();
    return RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: const [],
      // Every dial fails immediately: the client stays disconnected and keeps
      // re-running the check, which is the situation the line exists for.
      socketFactory: (host, port) async =>
          throw const SocketException('refused'),
    );
  }

  test('an unconnected client reports its connectivity state', () async {
    final client = await deadClient();
    addTearDown(client.disconnect);
    await client.addPeer('127.0.0.1:5301');
    await client.connect();
    await Future<void>.delayed(const Duration(seconds: 1));

    final reports = lines.where((l) => l.contains('still ')).toList();
    expect(reports, isNotEmpty, reason: 'expected a connectivity report');
    // Counts only — an address in this line would put it on the wrong side of
    // the info/debug privacy boundary.
    expect(reports.first, matches(RegExp('still (disconnected|connecting)')));
    expect(reports.first, contains('known=1'));
    expect(reports.first, contains('verified=0'));
    expect(reports.first, isNot(contains('127.0.0.1')));
  });

  test(
    'the report is throttled to one line per 15 s',
    () async {
      final client = await deadClient();
      addTearDown(client.disconnect);
      await client.addPeer('127.0.0.1:5302');
      await client.connect();
      // Four connection-check ticks (every 3 s) inside one throttle window.
      await Future<void>.delayed(const Duration(seconds: 13));

      expect(lines.where((l) => l.contains('still ')), hasLength(1));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
