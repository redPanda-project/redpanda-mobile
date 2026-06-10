import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';

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
