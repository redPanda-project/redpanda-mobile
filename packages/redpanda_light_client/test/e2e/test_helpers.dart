import 'dart:async';
import 'dart:io';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';

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
///
/// Bounded by [timeout] (default 5 min): a leaked lock — e.g. a crashed
/// suite whose process still holds the port — must fail this suite loudly
/// instead of blocking the whole run until the CI job timeout. With
/// `--concurrency=1` (the CI default for e2e) the lock is essentially
/// uncontended and returns on the first try.
Future<ServerSocket> acquireTopologyLock({
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      return await ServerSocket.bind(InternetAddress.loopbackIPv4, 59557);
    } on SocketException {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'acquireTopologyLock: port 59557 still held after '
          '${timeout.inSeconds}s — a previous topology suite likely leaked '
          'its lock (crashed teardown?).',
        );
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }
}

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
