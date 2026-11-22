/// Which Redpanda network this build belongs to (T180).
///
/// The wire protocol has no network identifier (the handshake only carries
/// the magic and the protocol version), so the build decides. Field
/// diagnostics send full identifiers (mailbox ids, message ids, node ids,
/// addresses) to Sentry; that is acceptable for the testnet only (decision 2
/// of `plans/PLAN-field-diagnostics.md`). Every diagnostics code path checks
/// [RpNetwork.allowsDiagnostics] and stays inert for any other value.
class RpNetwork {
  RpNetwork._();

  /// The test network (today the only network).
  static const String testnet = 'testnet';

  /// The network this build talks to. THE one constant: change it when a
  /// build targets another network, and field diagnostics switch off.
  static const String id = testnet;

  /// Whether field diagnostics may run on [networkId]. Only the testnet.
  static bool allowsDiagnostics(String networkId) => networkId == testnet;
}
