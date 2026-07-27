import 'package:drift/drift.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

class DriftPeerRepository implements PeerRepository {
  final AppDatabase db;

  DriftPeerRepository(this.db);

  /// Tail of the in-flight update chain per address (M6).
  ///
  /// [updatePeer] is `void` on the interface, so every caller in
  /// `RedPandaLightClient` fires it and forgets it — `onHandshakeComplete`,
  /// `onLatencyUpdate`, `onDisconnect` and the `onPeersReceived` loop can all
  /// land for the same address within the same event loop turn. The Drift
  /// implementation has to read-modify-write across two awaits, so without
  /// serialization both callbacks read the same snapshot, derive their counters
  /// from it and the later write silently drops the earlier increment / latency
  /// sample — degrading exactly the bookkeeping that feeds [getBestPeers] and
  /// garlic hop selection.
  ///
  /// Updates for the same address are therefore chained; different addresses
  /// still run concurrently. Entries are dropped once the chain drains, so the
  /// map stays bounded by the number of peers being updated right now.
  final Map<String, Future<void>> _pending = {};

  @override
  Future<void> save() async {
    // The DB writes themselves are immediate; "saving" means letting the queued
    // per-address updates drain, which also gives tests a way to await them.
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.values.toList());
    }
  }

  @override
  void updatePeer(
    String address, {
    String? nodeId,
    String? encryptionPublicKey,
    int? latencyMs,
    bool? isSuccess,
    bool? isFailure,
  }) {
    final previous = _pending[address];
    // `_applyUpdate` never completes with an error (it swallows failures
    // internally), so the chain cannot get stuck on a broken link.
    final next = previous == null
        ? _applyUpdate(
            address,
            nodeId: nodeId,
            encryptionPublicKey: encryptionPublicKey,
            latencyMs: latencyMs,
            isSuccess: isSuccess,
            isFailure: isFailure,
          )
        : previous.then(
            (_) => _applyUpdate(
              address,
              nodeId: nodeId,
              encryptionPublicKey: encryptionPublicKey,
              latencyMs: latencyMs,
              isSuccess: isSuccess,
              isFailure: isFailure,
            ),
          );
    _pending[address] = next;
    next.whenComplete(() {
      // Only the last link clears the slot — an update queued in the meantime
      // has already replaced it and must stay reachable.
      if (identical(_pending[address], next)) {
        _pending.remove(address);
      }
    });
  }

  Future<void> _applyUpdate(
    String address, {
    String? nodeId,
    String? encryptionPublicKey,
    int? latencyMs,
    bool? isSuccess,
    bool? isFailure,
  }) async {
    // Read, modify, write — serialized per address by [updatePeer].
    try {
      final existing = await (db.select(
        db.peers,
      )..where((t) => t.address.equals(address))).getSingleOrNull();

      var newAverage = existing?.averageLatencyMs ?? 9999;
      var newSuccess = existing?.successCount ?? 0;
      var newFailure = existing?.failureCount ?? 0;
      var newNodeId =
          nodeId ?? existing?.nodeId; // Keep existing if not provided
      // Keep existing key if not provided (MS04).
      var newEncryptionKey =
          encryptionPublicKey ?? existing?.encryptionPublicKey;
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
        encryptionPublicKey: newEncryptionKey,
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
              encryptionPublicKey: Value(newEncryptionKey),
              averageLatencyMs: Value(newAverage),
              successCount: Value(newSuccess),
              failureCount: Value(newFailure),
              lastSeen: Value(now),
            ),
          );
    } catch (_) {
      // Silently ignore update failures to avoid crashing peer tracking
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
        // Optimistically add to cache first — `updatePeer` only reaches the
        // cache once its queued DB read completes.
        _cache[addr] = PeerStats(address: addr);
        updatePeer(addr);
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
        encryptionPublicKey: row.encryptionPublicKey,
        averageLatencyMs: row.averageLatencyMs,
        successCount: row.successCount,
        failureCount: row.failureCount,
        lastSeen: row.lastSeen,
      );
    }
  }
}
