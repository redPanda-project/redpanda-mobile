import 'package:redpanda_light_client/src/domain/state_update.dart';

/// Snapshot of a channel's T44 rendezvous merge state — the newest-known
/// entry per participant — emitted whenever the network layer learns
/// something new from a resolved DHT record (TD117).
///
/// Why it has to leave the worker: the merge state is the only place the
/// counterpart's `entry_ts` lives. A respawned worker without it (a) drops
/// the counterpart out of the record it republishes, so the newest surviving
/// KadContent no longer carries everyone, and (b) loses the newest-wins
/// guard in `applyResolvedRecord`, so an older-but-still-valid record can
/// roll the counterpart's mailbox set backwards. Same pattern as the ratchet
/// and garlic session state: the worker publishes, the main isolate keeps the
/// projection and replays the newest version after a respawn.
class RendezvousStateUpdate extends StateUpdate {
  final String channelId;

  /// `RendezvousManager.exportMergeState` output (JSON list of entries).
  final String mergeStateJson;

  const RendezvousStateUpdate({
    required this.channelId,
    required this.mergeStateJson,
  });
}
