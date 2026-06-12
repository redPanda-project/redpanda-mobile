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
