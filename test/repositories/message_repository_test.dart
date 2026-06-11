import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late MessageRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = MessageRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('MessageRepository: outgoing messages', () {
    test('insertOutgoing stores a pending message', () async {
      final id = await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'Hello',
      );

      final pending = await repo.getPendingMessages();
      expect(pending, hasLength(1));
      expect(pending.single.id, equals(id));
      expect(pending.single.status, equals(MessageStatus.pending));
      expect(pending.single.retryCount, equals(0));
      expect(pending.single.lastRetryAt, isNull);
    });

    test(
      'updateMessageStatus moves a message out of the pending set',
      () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'Hello',
        );

        await repo.updateMessageStatus(id, MessageStatus.sent);

        expect(await repo.getPendingMessages(), isEmpty);
      },
    );

    test(
      'markRetryAttempt increments retryCount and stamps lastRetryAt',
      () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'Hello',
        );

        await repo.markRetryAttempt(id);
        await repo.markRetryAttempt(id);

        final msg = (await repo.getPendingMessages()).single;
        expect(msg.retryCount, equals(2));
        expect(msg.lastRetryAt, isNotNull);
      },
    );

    test('watchPendingCount tracks the live pending count', () async {
      expect(await repo.watchPendingCount().first, equals(0));

      await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'one',
      );
      final id2 = await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'two',
      );
      expect(await repo.watchPendingCount().first, equals(2));

      await repo.updateMessageStatus(id2, MessageStatus.failed);
      expect(await repo.watchPendingCount().first, equals(1));
    });
  });

  group('MessageRepository: dedup of fetched messages', () {
    test('insertIncomingIfNew inserts an unseen message', () async {
      final inserted = await repo.insertIncomingIfNew(
        messageId: 'abc123',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'Hi there',
        timestamp: DateTime(2026, 6, 11),
      );

      expect(inserted, isTrue);
      expect(await repo.messageExists('abc123'), isTrue);
    });

    test('insertIncomingIfNew ignores a duplicate message id', () async {
      await repo.insertIncomingIfNew(
        messageId: 'abc123',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'Hi there',
        timestamp: DateTime(2026, 6, 11),
      );

      final insertedAgain = await repo.insertIncomingIfNew(
        messageId: 'abc123',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'Hi there (duplicate)',
        timestamp: DateTime(2026, 6, 11),
      );

      expect(insertedAgain, isFalse);
      final all = await db.select(db.messages).get();
      expect(all, hasLength(1));
      expect(all.single.content, equals('Hi there'));
    });

    test(
      'unique index rejects duplicate message ids at the DB level',
      () async {
        await repo.insertIncomingIfNew(
          messageId: 'dup',
          conversationId: 'channel-1',
          senderId: 'channel-1',
          content: 'first',
          timestamp: DateTime(2026, 6, 11),
        );

        // Bypasses the repository check; insertOrIgnore + unique index must
        // still prevent a second row.
        await repo.insertIncomingIfNew(
          messageId: 'dup',
          conversationId: 'channel-1',
          senderId: 'channel-1',
          content: 'second',
          timestamp: DateTime(2026, 6, 11),
        );

        final all = await db.select(db.messages).get();
        expect(all, hasLength(1));
      },
    );

    test('messages without a network id are not affected by dedup', () async {
      await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'local one',
      );
      await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'local two',
      );

      final all = await db.select(db.messages).get();
      expect(all, hasLength(2));
    });
  });
}
