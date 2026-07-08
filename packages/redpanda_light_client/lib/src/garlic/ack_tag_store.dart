/// In-memory lookup of outstanding R-ACK session tags (Frontend MS06).
///
/// Maps a 16-byte ack session tag (lowercase hex) to the message that
/// requested it plus the relay hops involved, so a fetched R-ACK item can be
/// correlated (master spec, Decisions Backend-MS06, Decision 3) and the hops
/// scored. Entries are consumed on the first matching R-ACK (single-use like
/// MS05 reply tags) or reaped by [takeExpired] after the ack timeout.
///
/// Deliberately **not persisted** (Frontend-MS06 decision): R-ACKs normally
/// arrive within one or two polling cycles. After an app restart outstanding
/// entries are lost — those messages simply keep their `sent` status (the
/// pre-MS06 semantics) instead of producing false timeout failures.
class AckTagStore {
  final Map<String, AckTagEntry> _entries = {};

  /// Registers an outstanding ack tag for a sent message. [memberIdHex]
  /// identifies the targeted group member for MS08 fan-outs (null for 1:1);
  /// [isRotation] marks the delivery of a sealed rotation box — its R-ACK
  /// clears the box from the pending store instead of updating a message.
  void store(
    String tagHex, {
    required String channelId,
    required String messageIdHex,
    required List<String> hopNodeIdsHex,
    int? sentAtMs,
    String? memberIdHex,
    bool isRotation = false,
  }) {
    _entries[tagHex] = AckTagEntry(
      channelId: channelId,
      messageIdHex: messageIdHex,
      hopNodeIdsHex: List.unmodifiable(hopNodeIdsHex),
      sentAtMs: sentAtMs ?? DateTime.now().millisecondsSinceEpoch,
      memberIdHex: memberIdHex,
      isRotation: isRotation,
    );
  }

  /// Consumes [tagHex] (single-use): removes and returns its entry, or null
  /// when the tag is unknown or already consumed.
  AckTagEntry? consume(String tagHex) => _entries.remove(tagHex);

  /// Number of outstanding entries (for tests/diagnostics).
  int get outstanding => _entries.length;

  /// Removes and returns all entries older than [timeout] — the messages
  /// whose R-ACK never arrived. The caller scores the hops down and notifies
  /// the app layer.
  List<AckTagEntry> takeExpired(Duration timeout, {int? nowMs}) {
    final cutoff =
        (nowMs ?? DateTime.now().millisecondsSinceEpoch) -
        timeout.inMilliseconds;
    final expired = <AckTagEntry>[];
    _entries.removeWhere((_, entry) {
      if (entry.sentAtMs < cutoff) {
        expired.add(entry);
        return true;
      }
      return false;
    });
    return expired;
  }
}

/// One outstanding R-ACK expectation: which message over which hops.
class AckTagEntry {
  final String channelId;
  final String messageIdHex;

  /// KademliaIds (hex) of every relay involved: the forward hops that carry
  /// the message and the return hops that carry the R-ACK back. An arriving
  /// R-ACK proves the whole loop worked; a timeout blames all of them
  /// (an R-ACK is a hint, not proof — master spec MS06, OQ 5).
  final List<String> hopNodeIdsHex;

  final int sentAtMs;

  /// MS08: the targeted group member (hex member id); null for 1:1 sends.
  final String? memberIdHex;

  /// MS08: true when this entry tracks a sealed rotation box delivery —
  /// the arriving R-ACK removes the box from the group's pending store
  /// (Decision 10: rotations must arrive reliably) and is not forwarded
  /// as a message status update.
  final bool isRotation;

  const AckTagEntry({
    required this.channelId,
    required this.messageIdHex,
    required this.hopNodeIdsHex,
    required this.sentAtMs,
    this.memberIdHex,
    this.isRotation = false,
  });
}
