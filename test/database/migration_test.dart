import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';

import '../helpers/test_database.dart';
import 'historic_schemas.dart';

void main() {
  group('AppDatabase schema v9 (MS03)', () {
    late AppDatabase db;

    setUp(() {
      db = createTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('schema version is 19', () {
      expect(db.schemaVersion, equals(19));
    });

    // T114 renamed the Dart-side names of these columns (peer* → counterpart*,
    // the conversation id onto one name) WITHOUT touching the database. The
    // physical names are pinned with `named(...)`; if one of those pins is
    // dropped, drift silently generates a differently spelled column and every
    // existing install loses the data in it on the next open. This test is the
    // guard: it asserts the on-disk spelling, not the Dart spelling.
    test('T114: renamed columns keep their historical SQL names', () async {
      Future<Set<String>> columnsOf(String table) async {
        final rows = await db.customSelect('PRAGMA table_info($table)').get();
        return {for (final row in rows) row.read<String>('name')};
      }

      expect(
        await columnsOf('channels'),
        containsAll(<String>[
          'uuid',
          'peer_oh_endpoint',
          'peer_oh_id',
          'peer_oh_public_key',
          'peer_oh_set',
        ]),
      );
      expect(await columnsOf('session_tags'), contains('channel_id'));
      expect(await columnsOf('outbound_handles'), contains('channel_id'));
      expect(await columnsOf('group_invites'), contains('channel_id'));
      // The conversation id was never called `conversation_id` in these
      // tables; if a pin is lost the new spelling shows up here.
      expect(await columnsOf('channels'), isNot(contains('conversation_id')));
      expect(
        await columnsOf('outbound_handles'),
        isNot(contains('conversation_id')),
      );
    });

    test('dedup is scoped per conversation: same id in two channels', () async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: 'c1',
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
        "INSERT INTO messages (conversation_id, content, timestamp, status, type) "
        "VALUES ('c1', 'old row', 0, 0, 0);",
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
        "INSERT INTO messages (conversation_id, content, timestamp, status, type, message_id) "
        "VALUES ('c1', 'a', 0, 0, 0, 'shared');",
      );
      await legacy.customStatement(
        "INSERT INTO messages (conversation_id, content, timestamp, status, type, message_id) "
        "VALUES ('c2', 'b', 0, 0, 0, 'shared');",
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
        "INSERT INTO messages (conversation_id, content, timestamp, status, type) "
        "VALUES ('old-id', 'old msg', 0, 0, 0);",
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
              conversationId: 'new-id',
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
        "INSERT INTO messages (conversation_id, content, timestamp, status, type) "
        "VALUES ('kept-id', 'kept msg', 0, 0, 0);",
      );

      await legacy.migration.onUpgrade(legacy.createMigrator(), 9, 10);

      // MS03b is non-destructive: existing channels and messages survive.
      final channel = await legacy.select(legacy.channels).getSingle();
      expect(channel.conversationId, equals('kept-id'));
      expect(channel.ratchetState, isNull);
      final message = await legacy.select(legacy.messages).getSingle();
      expect(message.content, equals('kept msg'));

      // The new column is writable.
      await (legacy.update(legacy.channels)
            ..where((c) => c.conversationId.equals('kept-id')))
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
      expect(channel.conversationId, equals('kept-id'));
      expect(channel.pendingRgb, isNull);

      // The new column and table are writable.
      await (legacy.update(legacy.channels)
            ..where((c) => c.conversationId.equals('kept-id')))
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
              conversationId: 'kept-id',
              createdAt: DateTime(2026, 6, 13),
            ),
          );
      final tag = await legacy.select(legacy.sessionTags).getSingle();
      expect(tag.tag, equals('ef' * 16));
      expect(tag.conversationId, equals('kept-id'));

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
        "INSERT INTO messages (conversation_id, content, "
        "timestamp, status, type) VALUES ('kept-id', 'hi', 0, 4, 0);",
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

    // T114 + T143 against a database that really is at v17/v18
    // (historic_schemas.dart): the current schema no longer has `sender_id`,
    // so these fixtures cannot be reshaped from a fresh database any more.
    // The rows cover all three meanings `sender_id` used to have — own uuid,
    // the conversation id standing in for the 1:1 counterpart, a group
    // member id — plus a group row whose `sender_member_id` was never set.
    for (final from in [17, 18]) {
      test('v$from → current: direction backfilled (T114) and every author '
          'kept when sender_id is dropped (T143)', () async {
        final member = 'ee' * 32;
        final legacyMember = 'dd' * 32;
        // v17 has no direction column; v18 has it, filled by the v18 step
        // with exactly the values the v18 backfill computes.
        String row(
          String conv,
          String sender,
          String content,
          int status, {
          String? memberId,
          int? direction,
        }) {
          final withDirection = from >= 18;
          return 'INSERT INTO messages (conversation_id, sender_id, content, '
              'timestamp, status, type, sender_member_id'
              '${withDirection ? ', direction' : ''}) VALUES '
              "('$conv', '$sender', '$content', 0, $status, 0, "
              "${memberId == null ? 'NULL' : "'$memberId'"}"
              '${withDirection ? ', ${direction!}' : ''})';
        }

        const incoming = MessageDirection.incoming;
        const outgoing = MessageDirection.outgoing;
        final legacy = createTestDatabaseAtVersion(from, [
          ...ddlForSchemaVersion(from),
          "INSERT INTO channels (uuid, label, encryption_key, auth_public_key) "
              "VALUES ('chan', 'Chat', '${'aa' * 32}', '${'bb' * 32}')",
          'INSERT INTO group_channels (group_id, label, my_member_id, '
              "my_sign_seed, my_x25519_priv) VALUES ('grp', 'Group', "
              "'${'11' * 32}', '${'22' * 32}', '${'33' * 32}')",
          // 1:1 incoming: the channel id stands in for "them".
          row('chan', 'chan', 'theirs', 4, direction: incoming),
          // Own outgoing 1:1 message, already delivered.
          row('chan', 'my-uuid', 'mine', 3, direction: outgoing),
          // Group incoming, attributed the MS08 way (both columns).
          row(
            'grp',
            member,
            'group theirs',
            4,
            memberId: member,
            direction: incoming,
          ),
          // Group incoming whose member id lives ONLY in sender_id.
          row('grp', legacyMember, 'group legacy', 4, direction: incoming),
          // Own outgoing group message, still pending.
          row('grp', 'my-uuid', 'group mine', 0, direction: outgoing),
        ]);
        addTearDown(legacy.close);

        final byContent = {
          for (final row in await legacy.select(legacy.messages).get())
            row.content: row,
        };
        expect(byContent, hasLength(5));

        expect(byContent['theirs']!.direction, equals(incoming));
        expect(byContent['mine']!.direction, equals(outgoing));
        expect(byContent['group theirs']!.direction, equals(incoming));
        expect(byContent['group legacy']!.direction, equals(incoming));
        expect(byContent['group mine']!.direction, equals(outgoing));

        // Author = direction + senderMemberId, one meaning per value.
        expect(byContent['theirs']!.senderMemberId, isNull); // counterpart
        expect(byContent['mine']!.senderMemberId, isNull); // me
        expect(byContent['group theirs']!.senderMemberId, equals(member));
        expect(
          byContent['group legacy']!.senderMemberId,
          equals(legacyMember),
          reason: 'a group author that lived only in sender_id must survive',
        );
        expect(byContent['group mine']!.senderMemberId, isNull); // me

        final columns = await legacy
            .customSelect('PRAGMA table_info(messages)')
            .get();
        expect(
          columns.map((row) => row.read<String>('name')),
          isNot(contains('sender_id')),
        );
      });
    }
  });

  // T124 (TD149). The test above covers the two versions T114 happened to
  // touch; this one covers EVERY historic version, against a database that
  // really is at that version (historic_schemas.dart) instead of a current
  // one reshaped with DROP COLUMN. Three more steps died the same way:
  //
  //   v2/v3  -> `duplicate column name: node_id`       (peers, v4 step)
  //   v2..v5 -> `duplicate column name: last_cursor`   (outbound_handles, v7)
  //   v2..v8 -> `duplicate column name: peer_oh_set`   (channels, v16)
  //
  // Each of them is an app that never starts again after the update, so the
  // parametrisation stays: a new step with a missing lower bound turns this
  // red for exactly the versions it breaks.
  //
  // What it does NOT catch, for the three tables the v17 step re-creates
  // (channels, messages, outbound_handles): a lower bound that is too HIGH,
  // so a column is skipped without an error — v17 hands it back from the
  // current schema, and the end state looks right. Only the crash direction
  // is covered there. For every other table (peers, session_tags,
  // node_scores, the group tables) nothing re-creates them afterwards, so
  // both directions are covered.
  group('multi-version jump to the current schema (T124)', () {
    Future<Map<String, Set<String>>> layoutOf(AppDatabase db) async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      return {
        for (final table in tables)
          table.read<String>('name'): {
            for (final column
                in await db
                    .customSelect(
                      'PRAGMA table_info(${table.read<String>('name')})',
                    )
                    .get())
              column.read<String>('name'),
          },
      };
    }

    late Map<String, Set<String>> current;

    setUpAll(() async {
      final fresh = createTestDatabase();
      current = await layoutOf(fresh);
      await fresh.close();
    });

    for (
      var from = oldestReachableSchemaVersion;
      from < AppDatabase.currentSchemaVersion;
      from++
    ) {
      test('v$from opens on the current schema', () async {
        final legacy = createTestDatabaseAtVersion(
          from,
          ddlForSchemaVersion(from),
        );
        addTearDown(legacy.close);

        // The first statement opens the database, which is what runs
        // onUpgrade(from, current). A failing step throws right here.
        final version = await legacy
            .customSelect('PRAGMA user_version')
            .getSingle();

        expect(
          version.read<int>('user_version'),
          equals(AppDatabase.currentSchemaVersion),
          reason: 'a migration that throws never bumps user_version',
        );
        // Not just "it did not crash": the upgraded database must have the
        // same tables and columns a fresh install gets, or the app reads
        // NULLs out of columns that silently stayed behind.
        expect(await layoutOf(legacy), equals(current));

        // Indexes are not part of PRAGMA table_info, and dedup silently
        // stops working without this one.
        final indexes = await legacy
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND tbl_name = 'messages'",
            )
            .get();
        expect(
          indexes.map((row) => row.read<String>('name')),
          contains('idx_messages_conv_message_id'),
          reason: 'v$from must end up with the per-conversation dedup index',
        );
      });
    }
  });
}
