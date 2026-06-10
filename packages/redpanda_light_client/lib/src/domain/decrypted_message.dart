/// A message that has been fetched from an OH mailbox and decrypted.
class DecryptedMessage {
  final String id;
  final String content;
  final int receivedAtMs;

  const DecryptedMessage({
    required this.id,
    required this.content,
    required this.receivedAtMs,
  });
}
