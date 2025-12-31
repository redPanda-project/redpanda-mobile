import 'package:drift/drift.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

class DriftPeerRepository implements PeerRepository {
  final AppDatabase db;

  DriftPeerRepository(this.db);

  @override
  Future<void> save() async {
    // DB is auto-save
  }

  @override
  void updatePeer(
    String address, {
    String? nodeId,
    int? latencyMs,
    bool? isSuccess,
    bool? isFailure,
  }) async {
    // Fetch existing or Create
    // In Drift we can use insertOnConflictUpdate

    // We need to read current first to update averages properly or use SQL
    // Simple approach: Read, Modify, Write
    try {
      final existing = await (db.select(
        db.peers,
      )..where((t) => t.address.equals(address))).getSingleOrNull();

      var newAverage = existing?.averageLatencyMs ?? 9999;
      var newSuccess = existing?.successCount ?? 0;
      var newFailure = existing?.failureCount ?? 0;
      var newNodeId =
          nodeId ?? existing?.nodeId; // Keep existing if not provided
      final now = DateTime.now();

      if (latencyMs != null) {
        if (newAverage == 9999) {
          newAverage = latencyMs;
        } else {
          newAverage = (newAverage * 0.7 + latencyMs * 0.3).round();
        }
      }

      if (isSuccess == true) {
        newSuccess++;
      }

      if (isFailure == true) {
        newFailure++;
      }

      final updatedStats = PeerStats(
        address: address,
        nodeId: newNodeId,
        averageLatencyMs: newAverage,
        successCount: newSuccess,
        failureCount: newFailure,
        lastSeen: now,
      );
      // Update Cache
      _cache[address] = updatedStats;

      await db
          .into(db.peers)
          .insertOnConflictUpdate(
            PeersCompanion(
              address: Value(address),
              nodeId: Value(newNodeId), // Insert or Update NodeId
              averageLatencyMs: Value(newAverage),
              successCount: Value(newSuccess),
              failureCount: Value(newFailure),
              lastSeen: Value(now),
            ),
          );
    } catch (e) {
// print removed
    }
  }

  @override
  List<PeerStats> getBestPeers(int count) {
    // Return sorted list limited by count
    final sorted = _cache.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return sorted.take(count).toList();
  }

  final Map<String, PeerStats> _cache = {};

  @override
  Iterable<String> get knownAddresses => _cache.keys;

  @override
  void addAll(Iterable<String> addresses) {
    for (final addr in addresses) {
      if (!_cache.containsKey(addr)) {
        updatePeer(addr);
        // Optimistically add to cache
        _cache[addr] = PeerStats(address: addr);
      }
    }
  }

  @override
  PeerStats? getPeer(String address) => _cache[address];

  // Custom load to fill cache
  @override
  Future<void> load() async {
    final rows = await db.select(db.peers).get();
    _cache.clear();
    for (final row in rows) {
      _cache[row.address] = PeerStats(
        address: row.address,
        nodeId: row.nodeId,
        averageLatencyMs: row.averageLatencyMs,
        successCount: row.successCount,
        failureCount: row.failureCount,
        lastSeen: row.lastSeen,
      );
    }
// print removed
  }
}
