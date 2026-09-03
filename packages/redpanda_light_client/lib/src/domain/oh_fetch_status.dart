import 'package:redpanda_light_client/src/domain/state_update.dart';

/// Outcome of a single mailbox fetch attempt for one Outbound Handle.
///
/// Unlike [OhMailboxUpdate] (which only fires when the mailbox state
/// changed), this is emitted for EVERY fetch attempt — including empty
/// successful polls and failures. The app layer uses it to show per-channel
/// health ("last successful mailbox check") without any persistence: after
/// a restart the next poll (≤30 s) repopulates the state.
class OhFetchStatus extends StateUpdate {
  final List<int> ohId;
  final String? channelId;

  /// True when the node answered the fetch with status OK (the mailbox was
  /// checked — even if it contained no items).
  final bool success;

  /// When the attempt finished (client clock, ms since epoch).
  final int atMs;

  /// Short failure reason for diagnostics (e.g. "no active peer",
  /// "timeout"); null on success.
  final String? detail;

  const OhFetchStatus({
    required this.ohId,
    required this.success,
    required this.atMs,
    this.channelId,
    this.detail,
  });
}
