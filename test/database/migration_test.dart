import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';

import '../helpers/test_database.dart';

void main() {
  group('AppDatabase schema v7 (MS02)', () {
    late AppDatabase db;

    setUp(() {
      db = createTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('schema version is 7', () {
      expect(db.schemaVersion, equals(7));
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
  });
}
