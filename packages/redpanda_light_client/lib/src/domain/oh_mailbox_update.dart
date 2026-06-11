/// State change of a registered Outbound Handle, emitted after a fetch or
/// renewal so the app layer can persist cursor/expiry and warn on overflow.
class OhMailboxUpdate {
  final List<int> ohId;
  final String? channelId;

  /// Highest acknowledged mailbox sequence id (fetch cursor).
  final int lastCursor;

  /// Current expiry of the OH registration (may change after renewal).
  final int expiresAtMs;

  /// True if the Full Node evicted mail items since the last fetch —
  /// older messages may have been lost.
  final bool mailboxOverflow;

  const OhMailboxUpdate({
    required this.ohId,
    required this.lastCursor,
    required this.expiresAtMs,
    this.channelId,
    this.mailboxOverflow = false,
  });
}
