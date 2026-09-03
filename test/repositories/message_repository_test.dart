import 'package:drift/drift.dart' as drift;
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
    test('requeueStuckSent re-queues only sent messages', () async {
      Future<int> insertWithStatus(String content, int status) async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: content,
        );
        await repo.updateMessageStatus(id, status);
        return id;
      }

      final sentId = await insertWithStatus('stuck', MessageStatus.sent);
      await insertWithStatus('routed', MessageStatus.routed);
      await insertWithStatus('delivered', MessageStatus.delivered);
      await insertWithStatus('failed', MessageStatus.failed);
      final pendingId = await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'already pending',
      );
      await repo.insertIncomingIfNew(
        messageId: 'in-1',
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'incoming',
        timestamp: DateTime.now(),
      );

      final count = await repo.requeueStuckSent();

      expect(count, equals(1));
      final pending = await repo.getPendingMessages();
      expect(pending.map((m) => m.id), unorderedEquals([sentId, pendingId]));
      // Backoff bookkeeping is untouched — the restart is not a failed
      // send attempt.
      final requeued = pending.singleWhere((m) => m.id == sentId);
      expect(requeued.retryCount, equals(0));
      expect(requeued.lastRetryAt, isNull);
    });

    test('markSent stamps lastRetryAt so the message is a stale-sent '
        'candidate later', () async {
      final id = await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'Hello',
      );

      await repo.markSent(id);

      final msg = await (db.select(
        db.messages,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(msg.status, equals(MessageStatus.sent));
      expect(msg.lastRetryAt, isNotNull);
      expect(
        DateTime.now().difference(msg.lastRetryAt!),
        lessThan(const Duration(seconds: 5)),
      );
    });

    group('requeueStaleSent (TD002/T51 safety net)', () {
      test('re-queues a sent message stuck past the threshold', () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'stuck without an ack tag',
        );
        await repo.markSent(id);
        // Backdate lastRetryAt as if the send happened 5 minutes ago — well
        // past both the R-ACK timeout (90s) and the default 3 min threshold.
        final backdated = DateTime.now().subtract(const Duration(minutes: 5));
        await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
          MessagesCompanion(lastRetryAt: drift.Value(backdated)),
        );

        final count = await repo.requeueStaleSent();

        expect(count, equals(1));
        final pending = await repo.getPendingMessages();
        expect(pending.map((m) => m.id), contains(id));
      });

      test('increments retryCount but leaves lastRetryAt untouched, so a '
          'permanently ack-less send eventually falls into the normal '
          'backoff tail instead of resending every 3 min forever', () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'stuck without an ack tag',
        );
        await repo.markSent(id);
        // Drift persists DateTime as a whole-second unix timestamp for
        // sqlite, so round the expectation to seconds too.
        final backdated = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now()
                  .subtract(const Duration(minutes: 5))
                  .millisecondsSinceEpoch ~/
              1000 *
              1000,
        );
        await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
          MessagesCompanion(lastRetryAt: drift.Value(backdated)),
        );

        await repo.requeueStaleSent();

        final msg = await (db.select(
          db.messages,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(msg.status, equals(MessageStatus.pending));
        expect(msg.retryCount, equals(1));
        expect(
          msg.lastRetryAt,
          equals(backdated),
          reason:
              'lastRetryAt must stay at its old value — OutboxService'
              '.isDue() reads it against the new retryCount to decide '
              'whether the backoff window has elapsed',
        );
      });

      test('leaves a recently sent message alone (still within its R-ACK '
          'window)', () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'freshly sent',
        );
        await repo.markSent(id);

        final count = await repo.requeueStaleSent();

        expect(count, equals(0));
        expect(await repo.getPendingMessages(), isEmpty);
      });

      test('never touches pending/routed/delivered/failed messages', () async {
        Future<int> insertWithStatus(String content, int status) async {
          final id = await repo.insertOutgoing(
            conversationId: 'channel-1',
            senderId: 'me',
            content: content,
          );
          await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
            MessagesCompanion(
              status: drift.Value(status),
              lastRetryAt: drift.Value(
                DateTime.now().subtract(const Duration(minutes: 5)),
              ),
            ),
          );
          return id;
        }

        await insertWithStatus('routed', MessageStatus.routed);
        await insertWithStatus('delivered', MessageStatus.delivered);
        await insertWithStatus('failed', MessageStatus.failed);
        final pendingId = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'already pending',
        );

        final count = await repo.requeueStaleSent();

        expect(count, equals(0));
        final pending = await repo.getPendingMessages();
        expect(pending.map((m) => m.id), equals([pendingId]));
      });

      test('a stale sent message with no lastRetryAt is not touched '
          '(pre-fix rows / defensive)', () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'sent without a stamp',
        );
        // Simulates a row written before this fix via the generic
        // updateMessageStatus (no lastRetryAt stamp).
        await repo.updateMessageStatus(id, MessageStatus.sent);

        final count = await repo.requeueStaleSent(olderThan: Duration.zero);

        expect(count, equals(0));
        expect(await repo.getPendingMessages(), isEmpty);
      });

      test('respects a custom olderThan threshold', () async {
        final id = await repo.insertOutgoing(
          conversationId: 'channel-1',
          senderId: 'me',
          content: 'sent 2 minutes ago',
        );
        await repo.markSent(id);
        await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
          MessagesCompanion(
            lastRetryAt: drift.Value(
              DateTime.now().subtract(const Duration(minutes: 2)),
            ),
          ),
        );

        // Still within a 3 min threshold.
        expect(await repo.requeueStaleSent(), equals(0));
        // But past a 1 min threshold.
        expect(
          await repo.requeueStaleSent(olderThan: const Duration(minutes: 1)),
          equals(1),
        );
      });
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

  // T114: the two insert paths ARE the two directions, so each stamps its own.
  // Nothing downstream may re-derive it from senderId or status.
  group('MessageRepository: direction', () {
    test('insertOutgoing stamps outgoing', () async {
      await repo.insertOutgoing(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'Hello',
      );

      final row = await db.select(db.messages).getSingle();
      expect(row.direction, equals(MessageDirection.outgoing));
    });

    test('insertIncomingIfNew stamps incoming', () async {
      await repo.insertIncomingIfNew(
        messageId: 'aa' * 8,
        conversationId: 'channel-1',
        senderId: 'channel-1',
        content: 'Hi',
        timestamp: DateTime.now(),
      );

      final row = await db.select(db.messages).getSingle();
      expect(row.direction, equals(MessageDirection.incoming));
    });

    test(
      'a group message keeps its direction independent of the sender',
      () async {
        await repo.insertIncomingIfNew(
          messageId: 'bb' * 8,
          conversationId: 'group-1',
          senderId: 'ee' * 32,
          content: 'from a member',
          timestamp: DateTime.now(),
          senderMemberId: 'ee' * 32,
        );

        final row = await db.select(db.messages).getSingle();
        expect(row.direction, equals(MessageDirection.incoming));
        expect(row.senderId, isNot(equals(row.conversationId)));
      },
    );
  });
}
