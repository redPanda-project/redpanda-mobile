import 'package:redpanda_light_client/src/models/peer_stats.dart';

/// Abstract interface for peer persistence.
abstract class PeerRepository {
  /// Loads or initializes the repository.
  Future<void> load();

  /// Saves the repository state (if needed).
  Future<void> save();

  /// Updates or adds a peer stat.
  void updatePeer(
    String address, {
    String? nodeId,
    int? latencyMs,
    bool? isSuccess,
    bool? isFailure,
  });

  /// Returns the top N peers sorted by score.
  List<PeerStats> getBestPeers(int count);

  /// Returns all known peer addresses.
  Iterable<String> get knownAddresses;

  /// Adds a list of known addresses (seeds or discovered).
  void addAll(Iterable<String> addresses);

  /// Helper to get stats for a specific peer
  PeerStats? getPeer(String address);
}

/// Fallback in-memory implementation for testing or simple usage
class InMemoryPeerRepository implements PeerRepository {
  final Map<String, PeerStats> _peers = {};

  @override
  Future<void> load() async {}

  @override
  Future<void> save() async {}

  @override
  void updatePeer(
    String address, {
    String? nodeId,
    int? latencyMs,
    bool? isSuccess,
    bool? isFailure,
  }) {
    final stats = _peers.putIfAbsent(
      address,
      () => PeerStats(address: address, lastSeen: DateTime.now()),
    );

    if (nodeId != null) {
      stats.nodeId = nodeId;
    }

    if (latencyMs != null) {
      if (stats.averageLatencyMs == 9999) {
        stats.averageLatencyMs = latencyMs;
      } else {
        stats.averageLatencyMs =
            (stats.averageLatencyMs * 0.7 + latencyMs * 0.3).round();
      }
    }

    if (isSuccess == true) {
      stats.successCount++;
      stats.lastSeen = DateTime.now();
    }

    if (isFailure == true) {
      stats.failureCount++;
    }
  }

  @override
  List<PeerStats> getBestPeers(int count) {
    final sorted = _peers.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return sorted.take(count).toList();
  }

  @override
  Iterable<String> get knownAddresses => _peers.keys;

  @override
  void addAll(Iterable<String> addresses) {
    for (final addr in addresses) {
      if (!_peers.containsKey(addr)) {
        updatePeer(addr);
      }
    }
  }

  @override
  PeerStats? getPeer(String address) => _peers[address];
}
