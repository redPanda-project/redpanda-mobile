import 'package:redpanda_light_client/src/domain/state_update.dart';

/// Snapshot of a channel's reverse-garlic session state (Frontend MS05),
/// emitted by the network layer whenever it changes so the app layer can
/// persist it on-device and feed it back via `addChannelKeys` after a
/// restart (same pattern as the MS03b ratchet state).
class GarlicSessionUpdate extends StateUpdate {
  final String channelId;

  /// Outstanding session tags issued for this channel: tag (lowercase hex)
  /// → creation time in ms since epoch. Consumed tags are absent — losing
  /// one would silently discard the matching reply (single-use rule).
  final Map<String, int> sessionTags;

  /// The latest unused ReverseGarlicBlock received from the channel partner
  /// (serialized, lowercase hex), or null when none is pending.
  final String? pendingRgbHex;

  const GarlicSessionUpdate({
    required this.channelId,
    required this.sessionTags,
    this.pendingRgbHex,
  });
}
