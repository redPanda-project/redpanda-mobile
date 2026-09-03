/// Typed failures for the send/register paths (MS02b).
///
/// The Full Node reports deposit/register problems via proto Status codes
/// (FlaschenpostPutResponse command 158, RegisterOhResponse). These exceptions
/// carry the status **name** as a plain string so they can cross the isolate
/// boundary (only primitives travel through the isolate protocol) and be
/// reconstructed on the main side.
library;

/// Status names a [DepositException] can carry. Mirrors the proto Status
/// enum values the node actually sends for deposits.
abstract final class DepositStatus {
  static const String notFound = 'NOT_FOUND';
  static const String quotaExceeded = 'QUOTA_EXCEEDED';
  static const String badRequest = 'BAD_REQUEST';
}

/// A FlaschenpostPut deposit was rejected by the directly connected node.
///
/// - [DepositStatus.quotaExceeded] — recipient mailbox full (reject-new);
///   retrying later may succeed once the recipient fetched.
/// - [DepositStatus.badRequest] — item exceeds the per-item size limit
///   (64 KiB); retrying the same payload can never succeed.
/// - [DepositStatus.notFound] — oh_id not registered and forwarding not
///   possible (hop limit).
class DepositException implements Exception {
  /// Proto Status name, e.g. 'QUOTA_EXCEEDED'.
  final String statusName;

  DepositException(this.statusName);

  bool get isQuotaExceeded => statusName == DepositStatus.quotaExceeded;
  bool get isBadRequest => statusName == DepositStatus.badRequest;

  @override
  String toString() => 'DepositException($statusName)';
}

/// A RegisterOhRequest was rejected with RATE_LIMIT (max 5/min per
/// connection). Retry after backing off.
class RateLimitException implements Exception {
  @override
  String toString() => 'RateLimitException(RATE_LIMIT)';
}

/// A send could not be handed to the network because the channel's
/// counterpart OH mailbox id is not (yet) known.
///
/// T114: "counterpart" is the human on the other side of the conversation.
/// Everywhere else in this package "peer" means a full node, which is exactly
/// why this exception could not keep its old name (`UnknownPeerException`) —
/// it never had anything to do with node connectivity.
///
/// Without a counterpart OH, a direct-deposit FlaschenpostPut would have to carry an
/// empty oh_id. The node's legacy garlic-parsing fallback then misparses the
/// raw E2E-encrypted payload as a `GMAck` frame (every v4 payload starts with
/// byte 0x04, the ACK type id) and throws, silently dropping the message
/// instead of delivering or rejecting it (REDPANDAJ-2DR). So this exception
/// is thrown instead of ever sending that doomed packet — the message stays
/// (or is put back) in the app's pending/retry queue and is sent for real
/// once the counterpart OH becomes known (e.g. via the partner's next channel
/// activity) or a garlic route becomes available.
class UnknownCounterpartException implements Exception {
  /// The channel whose partner OH mailbox id is not (yet) known.
  final String channelId;

  UnknownCounterpartException(this.channelId);

  @override
  String toString() => 'UnknownCounterpartException($channelId)';
}
