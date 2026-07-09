/// A message that has been fetched from an OH mailbox and decrypted.
class DecryptedMessage {
  /// Sender-chosen message id (hex of the 16-byte ChannelMessage.message_id).
  /// Stable across the sender's retries, so it is the deduplication key.
  final String id;

  final String content;

  /// When the Full Node received this item (server clock), in ms since epoch.
  final int receivedAtMs;

  /// Sender-chosen send time (from the decrypted ChannelMessage), in ms since
  /// epoch. 0 if the sender did not set one.
  final int senderTimestampMs;

  /// The channel this message belongs to (derived from the OH the message
  /// was fetched from). Null if the OH has no channel association.
  final String? channelId;

  /// MS05: true when this message arrived as a reverse-garlic reply and was
  /// correlated (and consumed) via its session tag.
  final bool viaSessionTag;

  /// MS08: the authenticated sender member id (hex) for group messages
  /// (the group id is in [channelId]); null for 1:1 messages.
  final String? senderMemberIdHex;

  const DecryptedMessage({
    required this.id,
    required this.content,
    required this.receivedAtMs,
    this.senderTimestampMs = 0,
    this.channelId,
    this.viaSessionTag = false,
    this.senderMemberIdHex,
  });
}
