import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;
  late MessageSyncService service;
  late OutboundHandleRepository ohRepo;

  const ohIdHex = '0101010101010101010101010101010101010101';

  setUp(() {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    ohRepo = OutboundHandleRepository(db);
    service = MessageSyncService(client, MessageRepository(db), ohRepo, db);
  });

  tearDown(() async {
    await service.dispose();
    await client.disconnect();
    await db.close();
  });

  Future<void> insertHandle({String? channelId}) async {
    await db
        .into(db.outboundHandles)
        .insert(
          OutboundHandlesCompanion.insert(
            ohId: ohIdHex,
            keypairBytes: (await OHKeypair.generate()).privateKeyBytes,
            serverEndpoint: 'localhost:59558',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
            channelId: drift.Value(channelId),
          ),
        );
  }

  Future<void> insertChannel(
    String uuid, {
    String? authPrivateKey,
    String? ratchetState,
  }) async {
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            uuid: uuid,
            label: 'Test',
            encryptionKey: HEX.encode(List.generate(32, (i) => i)),
            authPrivateKey: drift.Value(authPrivateKey),
            authPublicKey: HEX.encode(List.generate(32, (i) => i + 1)),
            ratchetState: drift.Value(ratchetState),
          ),
        );
  }

  group('handleIncomingMessage', () {
    test('persists a fetched message into its channel', () async {
      await insertChannel('channel-1');

      await service.handleIncomingMessage(
        const DecryptedMessage(
          id: 'msg-1',
          content: 'Hello',
          receivedAtMs: 1700000000000,
          channelId: 'channel-1',
        ),
      );

      final all = await db.select(db.messages).get();
      expect(all, hasLength(1));
      expect(all.single.conversationId, equals('channel-1'));
      expect(all.single.messageId, equals('msg-1'));
      expect(all.single.status, equals(MessageStatus.received));
    });

    test('deduplicates re-delivered messages (failed AckFetch case)', () async {
      await insertChannel('channel-1');
      const msg = DecryptedMessage(
        id: 'msg-1',
        content: 'Hello',
        receivedAtMs: 1700000000000,
        channelId: 'channel-1',
      );

      await service.handleIncomingMessage(msg);
      await service.handleIncomingMessage(msg);

      expect(await db.select(db.messages).get(), hasLength(1));
    });

    test('drops messages without channel association', () async {
      await service.handleIncomingMessage(
        const DecryptedMessage(
          id: 'msg-1',
          content: 'Hello',
          receivedAtMs: 1700000000000,
        ),
      );

      expect(await db.select(db.messages).get(), isEmpty);
    });
  });

  group('handleMailboxUpdate', () {
    test('persists cursor and expiry for the OH', () async {
      await insertHandle();
      final newExpiry = DateTime.now().add(const Duration(days: 14));

      await service.handleMailboxUpdate(
        OhMailboxUpdate(
          ohId: HEX.decode(ohIdHex),
          lastCursor: 42,
          expiresAtMs: newExpiry.millisecondsSinceEpoch,
        ),
      );

      final row = await db.select(db.outboundHandles).getSingle();
      expect(row.lastCursor, equals(42));
      // Drift persists DateTime with second precision.
      expect(
        row.expiresAt.millisecondsSinceEpoch ~/ 1000,
        equals(newExpiry.millisecondsSinceEpoch ~/ 1000),
      );
    });

    test('forwards overflow warnings to the UI stream', () async {
      await insertHandle();
      final overflowEvents = <OhMailboxUpdate>[];
      final sub = service.overflowEvents.listen(overflowEvents.add);

      await service.handleMailboxUpdate(
        OhMailboxUpdate(
          ohId: HEX.decode(ohIdHex),
          lastCursor: 1,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch,
          mailboxOverflow: true,
        ),
      );
      await service.handleMailboxUpdate(
        OhMailboxUpdate(
          ohId: HEX.decode(ohIdHex),
          lastCursor: 2,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(overflowEvents, hasLength(1));
      expect(overflowEvents.single.mailboxOverflow, isTrue);
      await sub.cancel();
    });
  });

  group('restorePersistedState', () {
    test('registers channel keys and restores valid OHs with cursor', () async {
      await insertChannel('channel-1');
      await insertHandle(channelId: 'channel-1');
      await ohRepo.updateCursor(ohIdHex, 23);

      await service.restorePersistedState();

      expect(client.channelKeys, contains('channel-1'));
      expect(client.restoredHandles, hasLength(1));
      expect(client.restoredHandles.single.lastCursor, equals(23));
      expect(client.restoredHandles.single.channelId, equals('channel-1'));
      expect(HEX.encode(client.restoredHandles.single.ohId), equals(ohIdHex));
    });

    test(
      'passes the creator role and persisted ratchet state (MS03b)',
      () async {
        await insertChannel(
          'created-here',
          authPrivateKey: HEX.encode(List.generate(32, (i) => i + 2)),
          ratchetState: '{"v":1,"fake":"state"}',
        );
        await insertChannel('joined-via-qr');

        await service.restorePersistedState();

        expect(client.channelCreatorRoles['created-here'], isTrue);
        expect(client.channelCreatorRoles['joined-via-qr'], isFalse);
        expect(
          client.restoredRatchetStates['created-here'],
          equals('{"v":1,"fake":"state"}'),
        );
        expect(client.restoredRatchetStates, isNot(contains('joined-via-qr')));
      },
    );

    test('skips expired OHs', () async {
      await db
          .into(db.outboundHandles)
          .insert(
            OutboundHandlesCompanion.insert(
              ohId: ohIdHex,
              keypairBytes: (await OHKeypair.generate()).privateKeyBytes,
              serverEndpoint: 'localhost:59558',
              expiresAt: DateTime.now().subtract(const Duration(days: 1)),
            ),
          );

      await service.restorePersistedState();

      expect(client.restoredHandles, isEmpty);
    });
  });

  group('live stream wiring', () {
    test('start() subscribes to incoming messages and updates', () async {
      await insertChannel('channel-1');
      await insertHandle();
      service.start();

      client.incomingController.add(
        const DecryptedMessage(
          id: 'live-1',
          content: 'streamed',
          receivedAtMs: 1700000000000,
          channelId: 'channel-1',
        ),
      );
      client.updateController.add(
        OhMailboxUpdate(
          ohId: HEX.decode(ohIdHex),
          lastCursor: 7,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await db.select(db.messages).get(), hasLength(1));
      final handle = await db.select(db.outboundHandles).getSingle();
      expect(handle.lastCursor, equals(7));
    });

    test('persists advanced ratchet state per channel (MS03b)', () async {
      await insertChannel('channel-1');
      service.start();

      client.ratchetStateController.add(
        const RatchetStateUpdate(
          channelId: 'channel-1',
          stateJson: '{"v":1,"advanced":true}',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final channel = await db.select(db.channels).getSingle();
      expect(channel.ratchetState, equals('{"v":1,"advanced":true}'));
    });
  });
}
