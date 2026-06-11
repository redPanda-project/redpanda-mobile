/// A message that has been fetched from an OH mailbox and decrypted.
class DecryptedMessage {
  final String id;
  final String content;
  final int receivedAtMs;

  /// The channel this message belongs to (derived from the OH the message
  /// was fetched from). Null if the OH has no channel association.
  final String? channelId;

  const DecryptedMessage({
    required this.id,
    required this.content,
    required this.receivedAtMs,
    this.channelId,
  });
}
