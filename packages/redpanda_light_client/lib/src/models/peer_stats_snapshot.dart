import 'package:redpanda_light_client/src/models/peer_stats.dart';

/// A snapshot of all known peers and their connection states.
/// Sent periodically from the background isolate to the main thread.
class PeerStatsSnapshot {
  final List<PeerStats> allPeers;
  final Set<String> activePeerAddresses;
  final Set<String> connectingPeerAddresses;

  PeerStatsSnapshot({
    required this.allPeers,
    required this.activePeerAddresses,
    required this.connectingPeerAddresses,
  });
}
