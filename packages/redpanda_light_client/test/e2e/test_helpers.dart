import 'dart:io';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';

/// Serializes the multi-node topology suites (MS04, MS05): both launch
/// their entry node on 59558, the JAR's built-in local seed port — relays
/// only ever find an entry there — so only one topology may be up at a
/// time. The mutex is a bound loopback port: it works across the test
/// isolates `flutter test` runs concurrently (unlike fcntl file locks,
/// which don't exclude within one process) and releases itself if a suite
/// crashes.
///
/// Acquire before launching nodes, release via [ServerSocket.close] after
/// stopping them. Waiting counts against the suite's `e2e` tag timeout.
Future<ServerSocket> acquireTopologyLock() async {
  while (true) {
    try {
      return await ServerSocket.bind(InternetAddress.loopbackIPv4, 59557);
    } on SocketException {
      await Future.delayed(const Duration(seconds: 2));
    }
  }
}

/// Polls until [client.isEncryptionActive] is true or timeout (20s).
/// Returns true if encryption became active, false on timeout.
Future<bool> waitForEncryption(
  RedPandaLightClient client, {
  int maxWaitMs = 20000,
  int intervalMs = 500,
}) async {
  final iterations = maxWaitMs ~/ intervalMs;
  for (int i = 0; i < iterations; i++) {
    await Future.delayed(Duration(milliseconds: intervalMs));
    if (client.isEncryptionActive) return true;
  }
  return false;
}
