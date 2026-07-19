import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';

import '../helpers/test_database.dart';

void main() {
  group('AppDatabase schema v9 (MS03)', () {
    late AppDatabase db;

    setUp(() {
      db = createTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('schema version is 15', () {
      expect(db.schemaVersion, equals(15));
    });

    test('dedup is scoped per conversation: same id in two channels', () async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: 'c1',
              senderId: 'c1',
              content: 'in c1',
              timestamp: DateTime.now(),
              status: 0,
              type: 0,
              messageId: const drift.Value('shared'),
            ),
          );
      // Same message id, different conversation: must be allowed by the
      // composite unique index (conversation_id, message_id).
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: 'c2',
              senderId: 'c2',
              content: 'in c2',
              timestamp: DateTime.now(),
              status: 0,
              type: 0,
              messageId: const drift.Value('shared'),
            ),
          );

      final rows = await db.select(db.messages).get();
      expect(rows, hasLength(2));
    });

    test('messages table has messageId, retryCount and lastRetryAt', () async {
      final id = await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: 'c1',
              senderId: 'me',
              content: 'x',
              timestamp: DateTime.now(),
              status: 0,
              type: 0,
              messageId: const drift.Value('net-id'),
              retryCount: const drift.Value(3),
              lastRetryAt: drift.Value(DateTime(2026, 6, 11)),
            ),
          );

      final row = await (db.select(
        db.messages,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.messageId, equals('net-id'));
      expect(row.retryCount, equals(3));
      expect(row.lastRetryAt, equals(DateTime(2026, 6, 11)));
    });

    test('retryCount defaults to 0 and messageId is nullable', () async {
      final id = await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: 'c1',
              senderId: 'me',
              content: 'x',
              timestamp: DateTime.now(),
              status: 0,
              type: 0,
            ),
          );

      final row = await (db.select(
        db.messages,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.retryCount, equals(0));
      expect(row.messageId, isNull);
      expect(row.lastRetryAt, isNull);
    });

    test('outboundHandles has lastCursor with default 0', () async {
      await db
          .into(db.outboundHandles)
          .insert(
            OutboundHandlesCompanion.insert(
              ohId: 'aa' * 20,
              keypairBytes: Uint8List.fromList(List.filled(32, 1)),
              serverEndpoint: 'localhost:1',
              expiresAt: DateTime.now(),
            ),
          );

      final row = await db.select(db.outboundHandles).getSingle();
      expect(row.lastCursor, equals(0));
    });

    test('v6 → v7 migration adds the new columns to existing data', () async {
      // Reshape a fresh database into the v6 layout (drop the MS02 columns),
      // then run the real onUpgrade closure for from=6 → to=7.
      final legacy = createTestDatabase();

      await legacy.customStatement(
        'DROP INDEX IF EXISTS idx_messages_message_id;',
      );
      // The current schema (v8) ships a composite index on message_id; drop it
      // too before removing the column to reshape into the v6 layout.
      await legacy.customStatement(
        'DROP INDEX IF EXISTS idx_messages_conv_message_id;',
      );
      await legacy.customStatement(
        'ALTER TABLE messages DROP COLUMN message_id;',
      );
      await legacy.customStatement(
        'ALTER TABLE messages DROP COLUMN retry_count;',
      );
      await legacy.customStatement(
        'ALTER TABLE messages DROP COLUMN last_retry_at;',
      );
      await legacy.customStatement(
        'ALTER TABLE outbound_handles DROP COLUMN last_cursor;',
      );
      await legacy.customStatement(
        "INSERT INTO messages (conversation_id, sender_id, content, timestamp, status, type) "
        "VALUES ('c1', 'me', 'old row', 0, 0, 0);",
      );

      await legacy.migration.onUpgrade(legacy.createMigrator(), 6, 7);

      final row = await legacy.select(legacy.messages).getSingle();
      expect(row.content, equals('old row'));
      expect(row.retryCount, equals(0));
      expect(row.messageId, isNull);
      expect(row.lastRetryAt, isNull);

      await legacy
          .into(legacy.outboundHandles)
          .insert(
            OutboundHandlesCompanion.insert(
              ohId: 'bb' * 20,
              keypairBytes: Uint8List.fromList(List.filled(32, 2)),
              serverEndpoint: 'localhost:2',
              expiresAt: DateTime.now(),
            ),
          );
      final handle = await legacy.select(legacy.outboundHandles).getSingle();
      expect(handle.lastCursor, equals(0));

      await legacy.close();
    });

    test('v7 → v8 swaps global index for per-conversation unique index', () async {
      // Reshape into the v7 layout: drop the composite index and create the
      // old global-unique message-id index, then run onUpgrade(7 → 8).
      final legacy = createTestDatabase();
      await legacy.customStatement(
        'DROP INDEX IF EXISTS idx_messages_conv_message_id;',
      );
      await legacy.customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_message_id '
        'ON messages (message_id);',
      );

      await legacy.migration.onUpgrade(legacy.createMigrator(), 7, 8);

      // The old global index is gone; same id in two channels is now allowed.
      await legacy.customStatement(
        "INSERT INTO messages (conversation_id, sender_id, content, timestamp, status, type, message_id) "
        "VALUES ('c1', 'c1', 'a', 0, 0, 0, 'shared');",
      );
      await legacy.customStatement(
        "INSERT INTO messages (conversation_id, sender_id, content, timestamp, status, type, message_id) "
        "VALUES ('c2', 'c2', 'b', 0, 0, 0, 'shared');",
      );

      final rows = await legacy.select(legacy.messages).get();
      expect(rows, hasLength(2));

      await legacy.close();
    });

    test('v8 → v9 migration recreates channel/message/OH tables (MS03)', () async {
      // Reshape a fresh database into the v8 layout: shared-secret K_auth
      // column instead of the Ed25519 keypair columns.
      final legacy = createTestDatabase();
      await legacy.customStatement(
        'ALTER TABLE channels DROP COLUMN auth_private_key;',
      );
      await legacy.customStatement(
        'ALTER TABLE channels DROP COLUMN auth_public_key;',
      );
      await legacy.customStatement(
        "ALTER TABLE channels ADD COLUMN authentication_key TEXT NOT NULL "
        "DEFAULT '';",
      );
      await legacy.customStatement(
        "INSERT INTO channels (uuid, label, encryption_key, authentication_key) "
        "VALUES ('old-id', 'Old Channel', '00', 'ff');",
      );
      await legacy.customStatement(
        "INSERT INTO messages (conversation_id, sender_id, content, timestamp, status, type) "
        "VALUES ('old-id', 'me', 'old msg', 0, 0, 0);",
      );

      await legacy.migration.onUpgrade(legacy.createMigrator(), 8, 9);

      // Old incompatible data is gone (destructive recreation, spec §7) ...
      expect(await legacy.select(legacy.channels).get(), isEmpty);
      expect(await legacy.select(legacy.messages).get(), isEmpty);
      expect(await legacy.select(legacy.outboundHandles).get(), isEmpty);

      // ... and the new v3 key model columns are in place.
      await legacy
          .into(legacy.channels)
          .insert(
            ChannelsCompanion.insert(
              uuid: 'new-id',
              label: 'New Channel',
              encryptionKey: 'aa' * 32,
              authPublicKey: 'bb' * 32,
            ),
          );
      final channel = await legacy.select(legacy.channels).getSingle();
      expect(channel.authPublicKey, equals('bb' * 32));
      expect(channel.authPrivateKey, isNull);

      await legacy.close();
    });

    test('v9 → v10 migration adds ratchetState without losing data', () async {
      // Reshape a fresh database into the v9 layout (no ratchet_state).
      final legacy = createTestDatabase();
      await legacy.customStatement(
        'ALTER TABLE channels DROP COLUMN ratchet_state;',
      );
      await legacy.customStatement(
        "INSERT INTO channels (uuid, label, encryption_key, auth_public_key) "
        "VALUES ('kept-id', 'Kept Channel', '${'aa' * 32}', '${'bb' * 32}');",
      );
      await legacy.customStatement(
        "INSERT INTO messages (conversation_id, sender_id, content, timestamp, status, type) "
        "VALUES ('kept-id', 'me', 'kept msg', 0, 0, 0);",
      );

      await legacy.migration.onUpgrade(legacy.createMigrator(), 9, 10);

      // MS03b is non-destructive: existing channels and messages survive.
      final channel = await legacy.select(legacy.channels).getSingle();
      expect(channel.uuid, equals('kept-id'));
      expect(channel.ratchetState, isNull);
      final message = await legacy.select(legacy.messages).getSingle();
      expect(message.content, equals('kept msg'));

      // The new column is writable.
      await (legacy.update(legacy.channels)
            ..where((c) => c.uuid.equals('kept-id')))
          .write(const ChannelsCompanion(ratchetState: drift.Value('{"v":1}')));
      final updated = await legacy.select(legacy.channels).getSingle();
      expect(updated.ratchetState, equals('{"v":1}'));

      await legacy.close();
    });

    test(
      'v10 → v11 migration adds peer encryption key without losing data',
      () async {
        // Reshape a fresh database into the v10 layout (no encryption key).
        final legacy = createTestDatabase();
        await legacy.customStatement(
          'ALTER TABLE peers DROP COLUMN encryption_public_key;',
        );
        await legacy.customStatement(
          "INSERT INTO peers (address, node_id, average_latency_ms, "
          "success_count, failure_count) "
          "VALUES ('1.2.3.4:5', '${'ab' * 20}', 42, 7, 1);",
        );

        await legacy.migration.onUpgrade(legacy.createMigrator(), 10, 11);

        // MS04 is non-destructive: existing peer stats survive.
        final peer = await legacy.select(legacy.peers).getSingle();
        expect(peer.address, equals('1.2.3.4:5'));
        expect(peer.nodeId, equals('ab' * 20));
        expect(peer.encryptionPublicKey, isNull);

        // The new column is writable.
        await (legacy.update(legacy.peers)
              ..where((p) => p.address.equals('1.2.3.4:5')))
            .write(PeersCompanion(encryptionPublicKey: drift.Value('cd' * 32)));
        final updated = await legacy.select(legacy.peers).getSingle();
        expect(updated.encryptionPublicKey, equals('cd' * 32));

        await legacy.close();
      },
    );

    test('v11 → v12 migration adds session_tags and pendingRgb without losing '
        'data (MS05)', () async {
      // Reshape a fresh database into the v11 layout.
      final legacy = createTestDatabase();
      await legacy.customStatement('DROP TABLE session_tags;');
      await legacy.customStatement(
        'ALTER TABLE channels DROP COLUMN pending_rgb;',
      );
      await legacy.customStatement(
        "INSERT INTO channels (uuid, label, encryption_key, auth_public_key) "
        "VALUES ('kept-id', 'Kept Channel', '${'aa' * 32}', '${'bb' * 32}');",
      );

      await legacy.migration.onUpgrade(legacy.createMigrator(), 11, 12);

      // MS05 is non-destructive: existing channels survive.
      final channel = await legacy.select(legacy.channels).getSingle();
      expect(channel.uuid, equals('kept-id'));
      expect(channel.pendingRgb, isNull);

      // The new column and table are writable.
      await (legacy.update(legacy.channels)
            ..where((c) => c.uuid.equals('kept-id')))
          .write(ChannelsCompanion(pendingRgb: drift.Value('cd' * 40)));
      expect(
        (await legacy.select(legacy.channels).getSingle()).pendingRgb,
        equals('cd' * 40),
      );

      await legacy
          .into(legacy.sessionTags)
          .insert(
            SessionTagsCompanion.insert(
              tag: 'ef' * 16,
              channelId: 'kept-id',
              createdAt: DateTime(2026, 6, 13),
            ),
          );
      final tag = await legacy.select(legacy.sessionTags).getSingle();
      expect(tag.tag, equals('ef' * 16));
      expect(tag.channelId, equals('kept-id'));

      await legacy.close();
    });

    test('v13 → v14 migration adds the group tables and senderMemberId '
        'without losing data (MS08)', () async {
      // Reshape a fresh database into the v13 layout.
      final legacy = createTestDatabase();
      for (final table in [
        'group_channels',
        'group_members',
        'group_pending_items',
        'group_invites',
        'message_receipts',
      ]) {
        await legacy.customStatement('DROP TABLE $table;');
      }
      await legacy.customStatement(
        'ALTER TABLE messages DROP COLUMN sender_member_id;',
      );
      await legacy.customStatement(
        "INSERT INTO channels (uuid, label, encryption_key, auth_public_key) "
        "VALUES ('kept-id', 'Kept Channel', '${'aa' * 32}', '${'bb' * 32}');",
      );
      await legacy.customStatement(
        "INSERT INTO messages (conversation_id, sender_id, content, "
        "timestamp, status, type) VALUES ('kept-id', 'kept-id', 'hi', 0, 4, "
        "0);",
      );

      await legacy.migration.onUpgrade(legacy.createMigrator(), 13, 14);

      // MS08 is non-destructive: existing rows survive.
      final message = await legacy.select(legacy.messages).getSingle();
      expect(message.content, equals('hi'));
      expect(message.senderMemberId, isNull);

      // The new tables are writable.
      await legacy
          .into(legacy.groupChannels)
          .insert(
            GroupChannelsCompanion.insert(
              groupId: 'cd' * 32,
              label: 'Gruppe',
              myMemberId: 'ee' * 32,
              mySignSeed: 'ff' * 32,
              myX25519Priv: '11' * 32,
            ),
          );
      await legacy
          .into(legacy.groupMembers)
          .insert(
            GroupMembersCompanion.insert(
              groupId: 'cd' * 32,
              memberId: 'ee' * 32,
              displayName: 'Me',
              x25519Pub: '22' * 32,
              role: 0,
            ),
          );
      final group = await legacy.select(legacy.groupChannels).getSingle();
      expect(group.label, equals('Gruppe'));
      expect(group.keyEpoch, equals(0));
      final member = await legacy.select(legacy.groupMembers).getSingle();
      expect(member.displayName, equals('Me'));

      await legacy.close();
    });
  });
}
