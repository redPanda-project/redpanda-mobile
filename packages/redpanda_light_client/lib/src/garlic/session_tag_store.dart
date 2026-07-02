/// In-memory session-tag lookup for reverse-garlic replies (Frontend MS05).
///
/// Maps a 16-byte session tag (lowercase hex) to the channel it belongs to.
/// The issuer (Alice) stores a tag per attached RGB; when a tagged reply is
/// fetched from her OH mailbox, the tag is looked up and **consumed** —
/// single-use is enforced at the endpoint (master spec MS05, Decision 5):
/// replies with an unknown or already consumed tag are discarded.
///
/// The store lives in the network isolate; the app layer persists snapshots
/// (see `GarlicSessionUpdate`) into the Drift `session_tags` table and feeds
/// them back through `addChannelKeys` after a restart.
class SessionTagStore {
  /// Outstanding tags older than this are dropped by [cleanup] — the RGB
  /// they belong to expired long before (24h lifetime + slack).
  static const Duration maxTagAge = Duration(hours: 48);

  final Map<String, _TagEntry> _tags = {};

  /// Registers [tagHex] for [channelId]. [createdAtMs] defaults to now.
  void store(String tagHex, String channelId, {int? createdAtMs}) {
    _tags[tagHex] = _TagEntry(
      channelId,
      createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Returns the channel a tag belongs to without consuming it.
  String? lookup(String tagHex) => _tags[tagHex]?.channelId;

  /// Consumes [tagHex] (single-use): removes it and returns its channel,
  /// or null when the tag is unknown or already consumed.
  String? consume(String tagHex) => _tags.remove(tagHex)?.channelId;

  /// Whether any outstanding tags exist for [channelId].
  bool hasTagsFor(String channelId) =>
      _tags.values.any((entry) => entry.channelId == channelId);

  /// Outstanding tags of [channelId] as tagHex → createdAtMs (for
  /// persistence snapshots).
  Map<String, int> tagsForChannel(String channelId) => {
    for (final entry in _tags.entries)
      if (entry.value.channelId == channelId)
        entry.key: entry.value.createdAtMs,
  };

  /// Drops tags older than [maxTagAge]. Returns the channels that lost tags
  /// so the caller can emit persistence snapshots for them.
  Set<String> cleanup({int? nowMs}) {
    final cutoff =
        (nowMs ?? DateTime.now().millisecondsSinceEpoch) -
        maxTagAge.inMilliseconds;
    final affected = <String>{};
    _tags.removeWhere((_, entry) {
      if (entry.createdAtMs < cutoff) {
        affected.add(entry.channelId);
        return true;
      }
      return false;
    });
    return affected;
  }
}

class _TagEntry {
  final String channelId;
  final int createdAtMs;
  const _TagEntry(this.channelId, this.createdAtMs);
}
