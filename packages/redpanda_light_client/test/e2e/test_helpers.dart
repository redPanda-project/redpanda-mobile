import 'dart:async';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';

// The topology lock (bound loopback port 59557) is gone (T30): every
// multi-node suite now uses suite-private ports and seeds its relays
// explicitly, so no two suites contend for a port anymore. Serialization
// against RESOURCE pressure (4 JVM nodes per suite) still comes from
// `--concurrency=1`, the CI default for the e2e tag.

/// Polls until [client.isEncryptionActive] is true or timeout (40s).
/// Returns true if encryption became active, false on timeout.
///
/// The poll returns as soon as encryption is up, so a generous timeout only
/// costs wall time on a genuine failure — it buys headroom for a slow
/// handshake when the CI runner is warm from the heavy garlic suites
/// (the 20s default occasionally expired mid-handshake under that load).
Future<bool> waitForEncryption(
  RedPandaLightClient client, {
  int maxWaitMs = 40000,
  int intervalMs = 500,
}) async {
  final iterations = maxWaitMs ~/ intervalMs;
  for (int i = 0; i < iterations; i++) {
    await Future.delayed(Duration(milliseconds: intervalMs));
    if (client.isEncryptionActive) return true;
  }
  return false;
}

/// Accumulates messages delivered to [client] via its production delivery
/// path — the mailbox poll loop, which decrypts fetched items and publishes
/// them on [RedPandaClient.incomingMessages].
///
/// Connection-Notify (T38) makes the background poll drain the mailbox in
/// real time (the node signals new mail, the client fetches and ACKs at
/// once), so a manual `fetchMessages()` can no longer be relied on to be the
/// first — and only — consumer of a deposit. E2E tests therefore observe
/// delivery here instead of racing the poll with an explicit fetch.
///
/// Construct the collector BEFORE the message is sent: the stream is a
/// broadcast with no replay, so an item delivered before the collector
/// subscribes (in its constructor) is missed.
class DeliveryCollector {
  DeliveryCollector(RedPandaLightClient client) {
    _sub = client.incomingMessages.listen((m) {
      messages.add(m);
      for (final w in _waiters) {
        if (!w.completer.isCompleted && w.predicate(messages)) {
          w.completer.complete();
        }
      }
    });
  }

  late final StreamSubscription<DecryptedMessage> _sub;
  final List<DecryptedMessage> messages = [];
  final List<
    ({
      Completer<void> completer,
      bool Function(List<DecryptedMessage>) predicate,
    })
  >
  _waiters = [];

  /// Waits until [predicate] holds over the accumulated messages, or until
  /// [timeout]. Returns the accumulated list either way (callers assert on it).
  Future<List<DecryptedMessage>> waitUntil(
    bool Function(List<DecryptedMessage>) predicate, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (predicate(messages)) return messages;
    final completer = Completer<void>();
    final waiter = (completer: completer, predicate: predicate);
    _waiters.add(waiter);
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      // Fall through: the caller asserts on whatever arrived.
    } finally {
      // Keep the list bounded and stop a timed-out waiter from completing
      // later against a stale message.
      _waiters.remove(waiter);
    }
    return messages;
  }

  /// Convenience: wait for at least [count] messages.
  Future<List<DecryptedMessage>> waitForCount(
    int count, {
    Duration timeout = const Duration(seconds: 20),
  }) => waitUntil((m) => m.length >= count, timeout: timeout);

  Future<void> cancel() => _sub.cancel();
}
