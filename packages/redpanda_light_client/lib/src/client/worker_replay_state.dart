import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';

/// The state a respawned network worker has to be re-initialized with:
/// known peers, channel keys (with the LATEST ratchet/garlic/peer-OH state),
/// own OH registrations, groups and node scores.
///
/// This is a **projection of the state channel**, not a second source of
/// truth: [apply] folds every [StateUpdate] that changes worker-restorable
/// state into the cached commands, so a respawn never replays stale crypto
/// state (which would break the ratchet chain or resurrect a dead mailbox).
/// Extracted from `RedPandaIsolateClient` so it is unit-testable without an
/// isolate — and so the isolate client itself holds no per-event logic.
///
/// A new [StateUpdate] type only needs a branch here when it changes what a
/// restarted worker must be told; everything else flows through untouched.
class WorkerReplayState {
  final Set<String> _peers = {};
  final Map<String, CmdAddChannelKeys> _channels = {};
  final Map<String, CmdRestoreOutboundHandle> _handles = {};
  final Map<String, CmdRegisterGroup> _groups = {};
  List<NodeScore>? _nodeScores;

  void recordPeer(String address) => _peers.add(address);

  /// Records the channel registration a respawned worker has to replay.
  ///
  /// T111: a re-registration may carry only a SUBSET of a channel's state
  /// (a caller that holds the channel row but not the live garlic session).
  /// Recording it as a wholesale replace dropped the session tags, the
  /// pending RGB and the display name from the projection, so the respawned
  /// worker came back with crypto state OLDER than the app had already
  /// persisted — the H8 bug class, one level up.
  ///
  /// The projection therefore applies the same precedence the worker itself
  /// applies (`RedPandaLightClient.addChannelKeys`): what is already known
  /// wins, and a re-registration may only fill gaps.
  void recordChannelKeys(CmdAddChannelKeys cmd) {
    final old = _channels[cmd.channelId];
    if (old == null) {
      _channels[cmd.channelId] = cmd;
      return;
    }
    // The peer mailbox and the garlic session are patched from live state
    // (`PeerOhUpdate` / `GarlicSessionUpdate`), so once either is known at
    // all it must survive a partial re-register untouched — including a
    // pending RGB that a live update legitimately set back to null.
    final knowsPeerOh = old.peerOhSet != null || old.peerOhId != null;
    final knowsGarlic = old.sessionTags != null || old.pendingRgbHex != null;
    _channels[cmd.channelId] = CmdAddChannelKeys(
      old.channelId,
      old.encryptionKey,
      channelSecret: old.channelSecret ?? cmd.channelSecret,
      ownDisplayName: old.ownDisplayName ?? cmd.ownDisplayName,
      peerOhId: knowsPeerOh ? old.peerOhId : cmd.peerOhId,
      peerOhEndpoint: knowsPeerOh ? old.peerOhEndpoint : cmd.peerOhEndpoint,
      peerOhSet: knowsPeerOh ? old.peerOhSet : cmd.peerOhSet,
      isChannelCreator: old.isChannelCreator,
      ratchetState: old.ratchetState ?? cmd.ratchetState,
      sessionTags: knowsGarlic ? old.sessionTags : cmd.sessionTags,
      pendingRgbHex: knowsGarlic ? old.pendingRgbHex : cmd.pendingRgbHex,
    );
  }

  void recordOutboundHandle(CmdRestoreOutboundHandle cmd) =>
      _handles[HEX.encode(cmd.ohId)] = cmd;

  void recordGroup(CmdRegisterGroup cmd) =>
      _groups[cmd.registration.groupId] = cmd;

  void recordNodeScores(List<NodeScore> scores) => _nodeScores = scores;

  /// Folds one state update into the cached restore commands.
  void apply(StateUpdate update) {
    switch (update) {
      case RatchetStateUpdate(:final channelId, :final stateJson):
        _patchChannel(channelId, ratchetState: stateJson);
      case GarlicSessionUpdate(
        :final channelId,
        :final sessionTags,
        :final pendingRgbHex,
      ):
        // A garlic update is an authoritative snapshot: pendingRgbHex may
        // legitimately become null (block consumed).
        _patchChannel(
          channelId,
          sessionTags: sessionTags,
          pendingRgbHex: pendingRgbHex,
          patchGarlic: true,
        );
      case PeerOhUpdate(:final channelId, :final descriptors):
        // T42: the partner announced a new mailbox set — keep the cached
        // primary in sync so a respawned worker sends to the current mailbox.
        if (descriptors.isEmpty) return;
        final primary = descriptors.first;
        _patchChannel(
          channelId,
          peerOhId: primary.handleId,
          peerOhEndpoint: primary.serverEndpoint,
          peerOhSet: [
            for (final d in descriptors)
              OhDescriptorData(
                endpoint: d.serverEndpoint,
                ohId: d.handleId,
                authPublicKey: d.authPublicKey,
              ),
          ],
          patchPeerOh: true,
        );
      case OhMailboxUpdate(:final ohId, :final lastCursor, :final expiresAtMs):
        final key = HEX.encode(ohId);
        final old = _handles[key];
        if (old == null) return;
        _handles[key] = CmdRestoreOutboundHandle(
          ohId: old.ohId,
          privateKeyBytes: old.privateKeyBytes,
          expiresAtMs: expiresAtMs,
          channelId: old.channelId,
          serverEndpoint: old.serverEndpoint,
          lastCursor: lastCursor,
        );
      case OwnOhSetUpdate(:final channelId, :final handles):
        // T21 failover / T42 multi-OH: the worker changed a channel's own-OH
        // SET. Rebuild this channel's entries from exactly that set — a
        // respawned worker must restore the current handles, not dead ones.
        // An empty set therefore CLEARS the channel's entries: the cache
        // mirrors the worker's live set, it is not a "last known good" store.
        // (No producer emits an empty set today — `_emitOwnOhSet` only fires
        // after a successful registration — but the mirror rule is what makes
        // the cache safe.)
        if (channelId != null) {
          _handles.removeWhere((_, cmd) => cmd.channelId == channelId);
        }
        for (final h in handles) {
          _handles[HEX.encode(h.ohId)] = CmdRestoreOutboundHandle(
            ohId: h.ohId,
            privateKeyBytes: h.keypair.privateKeyBytes.toList(),
            expiresAtMs: h.expiresAtMs,
            channelId: channelId,
            serverEndpoint: h.serverEndpoint,
            lastCursor: h.lastCursor,
          );
        }
      case NodeScoreUpdate(:final scores):
        _nodeScores = scores;
      default:
        // Purely informational updates (fetch status, ACKs, group state,
        // handshakes) do not change what a restarted worker needs.
        break;
    }
  }

  /// The commands that re-establish the worker state, in the order they must
  /// be sent (peers → channels → handles → groups → node scores).
  List<IsolateCommand> replayCommands() {
    final scores = _nodeScores;
    return [
      for (final address in _peers) CmdAddPeer(address),
      ..._channels.values,
      ..._handles.values,
      ..._groups.values,
      if (scores != null && scores.isNotEmpty) CmdRestoreNodeScores(scores),
    ];
  }

  /// Updates the cached [CmdAddChannelKeys] for [channelId] with newer
  /// ratchet, garlic or peer-OH state. A channel that was never registered is
  /// not resurrected here — the state belongs to a channel the worker only
  /// learned about from live traffic.
  void _patchChannel(
    String channelId, {
    String? ratchetState,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
    bool patchGarlic = false,
    List<int>? peerOhId,
    String? peerOhEndpoint,
    List<OhDescriptorData>? peerOhSet,
    bool patchPeerOh = false,
  }) {
    final old = _channels[channelId];
    if (old == null) return;
    _channels[channelId] = CmdAddChannelKeys(
      old.channelId,
      old.encryptionKey,
      channelSecret: old.channelSecret,
      ownDisplayName: old.ownDisplayName,
      peerOhId: patchPeerOh ? peerOhId : old.peerOhId,
      peerOhEndpoint: patchPeerOh ? peerOhEndpoint : old.peerOhEndpoint,
      peerOhSet: patchPeerOh ? peerOhSet : old.peerOhSet,
      isChannelCreator: old.isChannelCreator,
      ratchetState: ratchetState ?? old.ratchetState,
      sessionTags: patchGarlic ? sessionTags : old.sessionTags,
      pendingRgbHex: patchGarlic ? pendingRgbHex : old.pendingRgbHex,
    );
  }
}
