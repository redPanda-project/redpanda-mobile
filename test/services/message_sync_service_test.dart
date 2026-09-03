import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/outbox_service.dart';
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
    final messages = MessageRepository(db);
    final groups = GroupRepository(db);
    service = MessageSyncService(
      client,
      messages,
      ohRepo,
      db,
      groups,
      OutboxService(messages, client, groups),
    );
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

    test('passes persisted session tags and pending RGB (MS05)', () async {
      await insertChannel('channel-1');
      await insertChannel('channel-2');
      await db
          .into(db.sessionTags)
          .insert(
            SessionTagsCompanion.insert(
              tag: 'aa' * 16,
              channelId: 'channel-1',
              createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
            ),
          );
      await (db.update(db.channels)..where((c) => c.uuid.equals('channel-1')))
          .write(ChannelsCompanion(pendingRgb: drift.Value('bb' * 40)));

      await service.restorePersistedState();

      expect(
        client.restoredSessionTags['channel-1'],
        equals({'aa' * 16: 1700000000000}),
      );
      expect(client.restoredPendingRgbs['channel-1'], equals('bb' * 40));
      expect(client.restoredSessionTags, isNot(contains('channel-2')));
      expect(client.restoredPendingRgbs, isNot(contains('channel-2')));
    });

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

  group('T111: registerChannel is the one restore entry point', () {
    Future<void> insertRichChannel(String uuid) async {
      await insertChannel(uuid, ratchetState: '{"v":1}');
      await db
          .into(db.sessionTags)
          .insert(
            SessionTagsCompanion.insert(
              tag: 'aa' * 16,
              channelId: uuid,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
            ),
          );
      await (db.update(db.channels)..where((c) => c.uuid.equals(uuid))).write(
        ChannelsCompanion(
          channelSecret: drift.Value(HEX.encode(List.generate(32, (i) => i))),
          pendingRgb: drift.Value('bb' * 40),
          peerOhId: drift.Value(HEX.encode(List.filled(20, 9))),
          peerOhEndpoint: const drift.Value('peer-host:59558'),
          peerOhSet: drift.Value(
            '[{"ep":"peer-host:59558","id":"${HEX.encode(List.filled(20, 9))}",'
            '"pk":"${HEX.encode(List.filled(32, 8))}"}]',
          ),
        ),
      );
    }

    test('hands over the COMPLETE channel state, not a subset', () async {
      await insertRichChannel('channel-1');

      await service.registerChannel('channel-1');

      final registration = client.channelRegistrations.single;
      expect(registration.channelId, equals('channel-1'));
      // The three fields `chat_screen.build` used to drop.
      expect(registration.sessionTags, equals({'aa' * 16: 1700000000000}));
      expect(registration.pendingRgbHex, equals('bb' * 40));
      expect(registration.ratchetState, equals('{"v":1}'));
      // …and the rest of the row.
      expect(registration.channelSecret, isNotNull);
      expect(registration.peerOhId, equals(List.filled(20, 9)));
      expect(registration.peerOhEndpoint, equals('peer-host:59558'));
      expect(registration.peerOhSet, hasLength(1));
    });

    test('the startup restore hands over exactly the same state', () async {
      await insertRichChannel('channel-1');

      await service.restorePersistedState();
      final viaRestore = client.channelRegistrations.single;
      client.channelRegistrations.clear();
      await service.registerChannel('channel-1');
      final viaRegister = client.channelRegistrations.single;

      expect(viaRegister.sessionTags, equals(viaRestore.sessionTags));
      expect(viaRegister.pendingRgbHex, equals(viaRestore.pendingRgbHex));
      expect(viaRegister.ratchetState, equals(viaRestore.ratchetState));
      expect(viaRegister.peerOhId, equals(viaRestore.peerOhId));
      expect(viaRegister.peerOhEndpoint, equals(viaRestore.peerOhEndpoint));
      expect(viaRegister.channelSecret, equals(viaRestore.channelSecret));
      expect(
        viaRegister.peerOhSet?.length,
        equals(viaRestore.peerOhSet?.length),
      );
    });

    test('an unknown channel id registers nothing', () async {
      await service.registerChannel('never-joined');
      expect(client.channelRegistrations, isEmpty);
    });

    test('a channel row added by ANY path is registered (duo-E2E)', () async {
      // The regression the emulator duo gate caught: the harness joins by
      // calling the channel repository directly, so before the watcher
      // existed only `chat_screen.build` registered Bob's keys and his worker
      // logged `fetchMessages() no encryption key` forever. Registration is a
      // property of the data now, not of which screen ran.
      service.start();

      await insertChannel('joined-outside-the-ui');
      await pumpEventQueue();

      expect(
        client.channelRegistrations.map((r) => r.channelId),
        contains('joined-outside-the-ui'),
      );
    });

    test('a channel is registered once, not on every table write', () async {
      service.start();
      await insertChannel('channel-1');
      await pumpEventQueue();

      // A ratchet advance writes the Channels row on every message.
      await service.handleRatchetStateUpdate(
        const RatchetStateUpdate(channelId: 'channel-1', stateJson: '{"v":2}'),
      );
      await pumpEventQueue();

      expect(
        client.channelRegistrations
            .where((r) => r.channelId == 'channel-1')
            .length,
        equals(1),
      );
    });

    test('the startup restore does not re-register via the watcher', () async {
      await insertChannel('channel-1');
      await service.restorePersistedState();
      service.start();
      await pumpEventQueue();

      expect(client.channelRegistrations, hasLength(1));
    });

    test('a channel without garlic state passes null, not empty', () async {
      await insertChannel('channel-1');

      await service.registerChannel('channel-1');

      final registration = client.channelRegistrations.single;
      expect(registration.sessionTags, isNull);
      expect(registration.pendingRgbHex, isNull);
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
      client.stateController.add(
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

      client.stateController.add(
        const RatchetStateUpdate(
          channelId: 'channel-1',
          stateJson: '{"v":1,"advanced":true}',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final channel = await db.select(db.channels).getSingle();
      expect(channel.ratchetState, equals('{"v":1,"advanced":true}'));
    });

    test('persists garlic session snapshots as replacements (MS05)', () async {
      await insertChannel('channel-1');
      service.start();

      client.stateController.add(
        const GarlicSessionUpdate(
          channelId: 'channel-1',
          sessionTags: {'aa11': 1000, 'bb22': 2000},
          pendingRgbHex: 'cafe',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      var tags = await db.select(db.sessionTags).get();
      expect(tags.map((t) => t.tag).toSet(), equals({'aa11', 'bb22'}));
      var channel = await db.select(db.channels).getSingle();
      expect(channel.pendingRgb, equals('cafe'));

      // A later snapshot REPLACES the channel's state: the consumed tag
      // disappears and the pending RGB is cleared.
      client.stateController.add(
        const GarlicSessionUpdate(
          channelId: 'channel-1',
          sessionTags: {'bb22': 2000},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      tags = await db.select(db.sessionTags).get();
      expect(tags.map((t) => t.tag).toList(), equals(['bb22']));
      channel = await db.select(db.channels).getSingle();
      expect(channel.pendingRgb, isNull);
    });
  });
}
