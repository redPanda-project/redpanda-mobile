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

    test(
      'resetForImmediateRetry re-queues a failed message with fresh backoff',
      () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'Hello',
        );
        await repo.markRetryAttempt(id, penalty: 5);
        await repo.updateMessageStatus(id, MessageStatus.failed);

        await repo.resetForImmediateRetry(id);

        final msg = (await repo.getPendingMessages()).single;
        expect(msg.id, equals(id));
        expect(msg.status, equals(MessageStatus.pending));
        expect(msg.retryCount, equals(0));
        expect(msg.lastRetryAt, isNull);
      },
    );
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
      'unique index rejects duplicate (conversation, message id) at DB level',
      () async {
        await repo.insertIncomingIfNew(
          messageId: 'dup',
          conversationId: 'channel-1',
          senderId: 'channel-1',
          content: 'first',
          timestamp: DateTime(2026, 6, 11),
        );

        // Bypasses the repository check; insertOrIgnore + unique index must
        // still prevent a second row in the same conversation.
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

    // --- C1 contract: receiver must keep EVERY message after the first ---

    test('two DIFFERENT messages both persist (regression for C1)', () async {
      final a = await repo.insertIncomingIfNew(
        messageId: 'id-aaa',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'first message',
        timestamp: DateTime(2026, 6, 11, 10),
      );
      final b = await repo.insertIncomingIfNew(
        messageId: 'id-bbb',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'second message',
        timestamp: DateTime(2026, 6, 11, 11),
      );

      expect(a, isTrue);
      expect(b, isTrue);
      final all = await db.select(db.messages).get();
      expect(all, hasLength(2));
      expect(
        all.map((m) => m.content),
        containsAll(['first message', 'second message']),
      );
    });

    test('the same message delivered twice is stored once', () async {
      final first = await repo.insertIncomingIfNew(
        messageId: 'same-id',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'hello',
        timestamp: DateTime(2026, 6, 11),
      );
      final again = await repo.insertIncomingIfNew(
        messageId: 'same-id',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'hello',
        timestamp: DateTime(2026, 6, 11),
      );

      expect(first, isTrue);
      expect(again, isFalse);
      expect(await db.select(db.messages).get(), hasLength(1));
    });

    test(
      'same message id in two channels both persist (per-conversation scope)',
      () async {
        final a = await repo.insertIncomingIfNew(
          messageId: 'shared-id',
          conversationId: 'channel-1',
          senderId: 'channel-1',
          content: 'in c1',
          timestamp: DateTime(2026, 6, 11),
        );
        final b = await repo.insertIncomingIfNew(
          messageId: 'shared-id',
          conversationId: 'channel-2',
          senderId: 'channel-2',
          content: 'in c2',
          timestamp: DateTime(2026, 6, 11),
        );

        expect(a, isTrue);
        expect(b, isTrue);
        expect(await db.select(db.messages).get(), hasLength(2));
      },
    );

    test('empty message ids never black-hole a channel', () async {
      // A malformed item whose decrypted id is empty must always insert,
      // never match a previous empty-id item.
      final a = await repo.insertIncomingIfNew(
        messageId: '',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'first malformed',
        timestamp: DateTime(2026, 6, 11, 10),
      );
      final b = await repo.insertIncomingIfNew(
        messageId: '',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'second malformed',
        timestamp: DateTime(2026, 6, 11, 11),
      );

      expect(a, isTrue);
      expect(b, isTrue);
      final all = await db.select(db.messages).get();
      expect(all, hasLength(2));
      // Empty ids are stored as NULL so the unique index does not group them.
      expect(all.every((m) => m.messageId == null), isTrue);
    });
  });
}
