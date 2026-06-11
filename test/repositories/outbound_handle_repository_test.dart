import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

class _RegisteringFakeClient extends FakeRedPandaClient {
  String? endpoint = 'node-1:59558';

  @override
  Future<OHRegistration> registerOutboundHandle({String? channelId}) async {
    return OHRegistration(
      ohId: List.generate(20, (i) => i),
      keypair: OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      channelId: channelId,
      serverEndpoint: endpoint,
    );
  }
}

void main() {
  late AppDatabase db;
  late OutboundHandleRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = OutboundHandleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  OHRegistration registration({String? channelId, int lastCursor = 0}) {
    return OHRegistration(
      ohId: List.generate(20, (i) => 9),
      keypair: OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      channelId: channelId,
      serverEndpoint: 'node-1:59558',
      lastCursor: lastCursor,
    );
  }

  group('persistence round-trip', () {
    test('save and getByChannelId', () async {
      await repo.save(registration(channelId: 'channel-1'));

      final row = await repo.getByChannelId('channel-1');
      expect(row, isNotNull);
      expect(row!.serverEndpoint, equals('node-1:59558'));
      expect(row.lastCursor, equals(0));
    });

    test('updateCursor and updateExpiry persist new values', () async {
      final reg = registration(channelId: 'channel-1');
      await repo.save(reg);
      final ohIdHex = HEX.encode(reg.ohId);
      final newExpiry = DateTime.now().add(const Duration(days: 14));

      await repo.updateCursor(ohIdHex, 55);
      await repo.updateExpiry(ohIdHex, newExpiry);

      final row = await repo.getByChannelId('channel-1');
      expect(row!.lastCursor, equals(55));
      expect(
        row.expiresAt.millisecondsSinceEpoch ~/ 1000,
        equals(newExpiry.millisecondsSinceEpoch ~/ 1000),
      );
    });

    test('toRegistration restores keypair, cursor and channel', () async {
      final reg = registration(channelId: 'channel-1', lastCursor: 0);
      await repo.save(reg);
      await repo.updateCursor(HEX.encode(reg.ohId), 7);

      final row = await repo.getByChannelId('channel-1');
      final restored = repo.toRegistration(row!);

      expect(restored.ohId, equals(reg.ohId));
      expect(
        restored.keypair.publicKeyBytes,
        equals(reg.keypair.publicKeyBytes),
      );
      expect(restored.lastCursor, equals(7));
      expect(restored.channelId, equals('channel-1'));
      expect(restored.serverEndpoint, equals('node-1:59558'));
    });

    test('getAllValid excludes expired handles', () async {
      final expired = registration(channelId: 'old');
      expired.expiresAtMs = DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      await repo.save(expired);
      await repo.save(registration(channelId: 'fresh'));

      final valid = await repo.getAllValid();
      expect(valid, hasLength(1));
      expect(valid.single.channelId, equals('fresh'));
    });
  });

  group('ensureOwnDescriptor', () {
    test('returns persisted descriptor when a valid OH exists', () async {
      final reg = registration(channelId: 'channel-1');
      await repo.save(reg);
      final client = _RegisteringFakeClient();

      final descriptor = await repo.ensureOwnDescriptor(client, 'channel-1');

      expect(descriptor, isNotNull);
      expect(descriptor!.handleId, equals(reg.ohId));
      expect(descriptor.serverEndpoint, equals('node-1:59558'));
    });

    test('registers and persists a new OH when none exists', () async {
      final client = _RegisteringFakeClient();

      final descriptor = await repo.ensureOwnDescriptor(client, 'channel-2');

      expect(descriptor, isNotNull);
      expect(await repo.getByChannelId('channel-2'), isNotNull);
    });

    test('returns null when registration has no server endpoint', () async {
      final client = _RegisteringFakeClient()..endpoint = null;

      final descriptor = await repo.ensureOwnDescriptor(client, 'channel-3');

      expect(descriptor, isNull);
      expect(await repo.getByChannelId('channel-3'), isNull);
    });

    test('returns null when registration throws', () async {
      final client = FakeRedPandaClient(); // registerOutboundHandle throws

      final descriptor = await repo.ensureOwnDescriptor(client, 'channel-4');

      expect(descriptor, isNull);
    });
  });
}
