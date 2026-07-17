/// Outcome of a loopback self-test (T20): a test message deposited into the
/// OWN mailbox and received back through the regular fetch pipeline. Carries
/// only isolate-sendable primitives.
class LoopbackResult {
  /// True when the test message came back within the timeout.
  final bool success;

  /// Full round-trip duration (deposit handed to the network until the
  /// fetch pipeline decrypted the message). Null on failure.
  final int? roundtripMs;

  /// Garlic relay hops the deposit travelled over (0 = direct deposit).
  /// Null when the test failed before the deposit went out.
  final int? hopCount;

  /// Human-readable failure detail; null on success.
  final String? error;

  const LoopbackResult.ok({
    required int this.roundtripMs,
    required this.hopCount,
  }) : success = true,
       error = null;

  const LoopbackResult.failed(String this.error, {this.hopCount})
    : success = false,
      roundtripMs = null;
}
