import 'dart:math';

import 'package:hex/hex.dart';

import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

/// Selects relay hops for a Flaschenpost v2 garlic path (Frontend MS04).
///
/// Candidates are known peers with an X25519 encryption public key (learned
/// via the peer exchange, MS04). Constraints (frontend spec):
///
/// - excluded by address: the connected node the packet is submitted
///   through and the destination OH endpoint (anti-correlation),
/// - excluded by KademliaId: the submission node (its address in the peer
///   list may differ from the address we dialed),
/// - diversity: random selection that prefers distinct KademliaId prefixes
///   (first byte) where the candidate set allows it.
///
/// MS06: with a [NodeScorer], reliably delivering nodes are preferred —
/// candidates are ordered by score plus random jitter (scores steer, they
/// never fully determine, so paths stay diverse) and nodes below the avoid
/// threshold are dropped when enough other candidates exist.
class HopSelector {
  final PeerRepository _peerRepository;

  /// Optional R-ACK-based node scoring (MS06); null selects unscored.
  final NodeScorer? nodeScorer;

  /// Jitter added to the score when ordering candidates, so a small score
  /// difference does not deterministically pin the same hops every time.
  static const double scoreJitter = 0.25;

  /// Optional additional candidate predicate. Used by tests to pin the
  /// candidate set (e.g. to local nodes in E2E); null accepts all.
  final bool Function(PeerStats peer)? candidateFilter;

  HopSelector(this._peerRepository, {this.candidateFilter, this.nodeScorer});

  /// Picks up to [count] distinct hops. Returns fewer (possibly zero) hops
  /// when not enough eligible candidates are known — the caller decides how
  /// to degrade (fewer hops with a warning, or the direct MS02b path).
  List<GarlicHop> selectHops({
    int count = 3,
    Set<String> excludeAddresses = const {},
    Set<String> excludeNodeIds = const {},
  }) {
    final seenNodeIds = <String>{};
    final candidates = <PeerStats>[];
    for (final address in _peerRepository.knownAddresses.toList()) {
      final peer = _peerRepository.getPeer(address);
      if (peer == null) continue;
      final nodeId = peer.nodeId;
      final encryptionKey = peer.encryptionPublicKey;
      if (nodeId == null || nodeId.length != GarlicHop.nodeIdLength * 2) {
        continue;
      }
      if (encryptionKey == null || encryptionKey.length != 64) continue;
      if (excludeAddresses.contains(peer.address)) continue;
      if (excludeNodeIds.contains(nodeId)) continue;
      if (candidateFilter != null && !candidateFilter!(peer)) continue;
      // The same node may be known under several addresses — never build a
      // path that visits one relay twice.
      if (!seenNodeIds.add(nodeId)) continue;
      candidates.add(peer);
    }

    candidates.shuffle();

    // MS06: drop unreliable nodes when the candidate set allows it, then
    // order by score plus jitter (highest first) so proven nodes are
    // preferred without pinning the same path every time.
    final scorer = nodeScorer;
    if (scorer != null) {
      final reliable = candidates
          .where((peer) => !scorer.shouldAvoid(peer.nodeId!))
          .toList();
      if (reliable.length >= count) {
        candidates
          ..clear()
          ..addAll(reliable);
      }
      final random = Random();
      final jittered = <String, double>{
        for (final peer in candidates)
          peer.nodeId!:
              scorer.score(peer.nodeId!) + random.nextDouble() * scoreJitter,
      };
      candidates.sort(
        (a, b) => jittered[b.nodeId!]!.compareTo(jittered[a.nodeId!]!),
      );
    }

    // Greedy diversity pass: prefer candidates whose KademliaId first byte
    // differs from already selected hops; top up with the remainder if the
    // candidate set is too uniform.
    final selected = <PeerStats>[];
    final usedPrefixes = <String>{};
    final skipped = <PeerStats>[];
    for (final peer in candidates) {
      if (selected.length == count) break;
      final prefix = peer.nodeId!.substring(0, 2);
      if (usedPrefixes.add(prefix)) {
        selected.add(peer);
      } else {
        skipped.add(peer);
      }
    }
    for (final peer in skipped) {
      if (selected.length == count) break;
      selected.add(peer);
    }

    return selected
        .map(
          (peer) => GarlicHop(
            nodeId: HEX.decode(peer.nodeId!),
            encryptionPublicKey: HEX.decode(peer.encryptionPublicKey!),
          ),
        )
        .toList();
  }
}
