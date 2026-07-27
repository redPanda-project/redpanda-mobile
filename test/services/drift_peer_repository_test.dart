import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/services/drift_peer_repository.dart';

import '../helpers/test_database.dart';

/// M6 regression coverage. These tests deliberately exercise the *Drift*
/// implementation: `InMemoryPeerRepository` does the same work synchronously,
/// so a fake can never reproduce the interleaving that loses updates.
void main() {
  late AppDatabase db;
  late DriftPeerRepository repo;

  setUp(() async {
    db = createTestDatabase();
    repo = DriftPeerRepository(db);
    await repo.load();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Peer?> readRow(String address) => (db.select(
    db.peers,
  )..where((t) => t.address.equals(address))).getSingleOrNull();

  test(
    'concurrent updates for the same address keep every increment (M6)',
    () async {
      const address = '10.0.0.1:59558';

      // Exactly the shape of the race: several fire-and-forget callbacks for
      // one freshly connected peer land before the first DB write completes.
      repo.updatePeer(address, isSuccess: true);
      repo.updatePeer(address, isSuccess: true);
      repo.updatePeer(address, isSuccess: true);
      repo.updatePeer(address, isFailure: true);
      repo.updatePeer(address, isFailure: true);

      await repo.save();

      final row = await readRow(address);
      expect(row, isNotNull);
      expect(row!.successCount, 3, reason: 'no success increment may be lost');
      expect(row.failureCount, 2, reason: 'no failure increment may be lost');

      final cached = repo.getPeer(address);
      expect(cached!.successCount, 3);
      expect(cached.failureCount, 2);
    },
  );

  test('concurrent latency samples all fold into the average (M6)', () async {
    const address = '10.0.0.2:59558';

    // First sample seeds the average (9999 sentinel -> 100), the following
    // ones are folded in with the 0.7/0.3 EMA. If the reads raced, later
    // samples would all start from the 9999 sentinel again.
    repo.updatePeer(address, latencyMs: 100);
    repo.updatePeer(address, latencyMs: 200);
    repo.updatePeer(address, latencyMs: 200);

    await repo.save();

    // 100 -> round(100*0.7 + 200*0.3) = 130 -> round(130*0.7 + 200*0.3) = 151
    final row = await readRow(address);
    expect(row!.averageLatencyMs, 151);
  });

  test('an update never clobbers a field another update just set', () async {
    const address = '10.0.0.3:59558';

    repo.updatePeer(address, nodeId: 'node-abc');
    repo.updatePeer(address, encryptionPublicKey: 'aa' * 32);
    repo.updatePeer(address, isSuccess: true, latencyMs: 42);

    await repo.save();

    final row = await readRow(address);
    expect(row!.nodeId, 'node-abc');
    expect(row.encryptionPublicKey, 'aa' * 32);
    expect(row.successCount, 1);
    expect(row.averageLatencyMs, 42);
  });

  test('updates for different addresses stay independent', () async {
    repo.updatePeer('10.0.0.4:59558', isSuccess: true);
    repo.updatePeer('10.0.0.5:59558', isSuccess: true);
    repo.updatePeer('10.0.0.4:59558', isSuccess: true);

    await repo.save();

    expect((await readRow('10.0.0.4:59558'))!.successCount, 2);
    expect((await readRow('10.0.0.5:59558'))!.successCount, 1);
  });

  test('save() drains the queue and leaves no pending work behind', () async {
    repo.addAll(['10.0.0.6:59558', '10.0.0.7:59558']);
    repo.updatePeer('10.0.0.6:59558', isSuccess: true);

    await repo.save();

    expect((await db.select(db.peers).get()).length, 2);
    // A second drain must be a no-op rather than hanging on a stale entry.
    await repo.save();
    expect((await readRow('10.0.0.6:59558'))!.successCount, 1);
  });
}
