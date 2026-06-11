import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/services/send_retry_queue.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late MessageRepository repo;
  late FakeRedPandaClient client;
  late SendRetryQueue queue;

  setUp(() {
    db = createTestDatabase();
    repo = MessageRepository(db);
    client = FakeRedPandaClient();
    queue = SendRetryQueue(repo, client);
  });

  tearDown(() async {
    queue.stop();
    await client.disconnect();
    await db.close();
  });

  Future<int> insertPending({
    String content = 'msg',
    int retryCount = 0,
    DateTime? lastRetryAt,
  }) async {
    return db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            conversationId: 'channel-1',
            senderId: 'me',
            content: content,
            timestamp: DateTime.now(),
            status: MessageStatus.pending,
            type: 0,
            retryCount: drift.Value(retryCount),
            lastRetryAt: drift.Value(lastRetryAt),
          ),
        );
  }

  Future<Message> messageById(int id) {
    return (db.select(db.messages)..where((t) => t.id.equals(id))).getSingle();
  }

  group('SendRetryQueue.retryPending', () {
    test('successful retry marks the message as sent', () async {
      final id = await insertPending(content: 'retry me');

      await queue.retryPending();

      expect(client.sentMessages, hasLength(1));
      expect(client.sentMessages.single.content, equals('retry me'));
      expect((await messageById(id)).status, equals(MessageStatus.sent));
    });

    test(
      'failed retry increments retryCount and keeps the message pending',
      () async {
        client.sendError = StateError('no active peer');
        final id = await insertPending();

        await queue.retryPending();

        final msg = await messageById(id);
        expect(msg.status, equals(MessageStatus.pending));
        expect(msg.retryCount, equals(1));
        expect(msg.lastRetryAt, isNotNull);
      },
    );

    test('message is marked failed after maxRetries attempts', () async {
      final id = await insertPending(retryCount: SendRetryQueue.maxRetries);

      await queue.retryPending();

      expect((await messageById(id)).status, equals(MessageStatus.failed));
      expect(client.sentMessages, isEmpty);
    });

    test('respects the backoff window between attempts', () async {
      // Last attempt just now with 3 failures → due again in 8 minutes.
      await insertPending(retryCount: 3, lastRetryAt: DateTime.now());

      await queue.retryPending();

      expect(client.sentMessages, isEmpty);
    });

    test('retries again once the backoff window has elapsed', () async {
      final id = await insertPending(
        retryCount: 3,
        lastRetryAt: DateTime.now().subtract(const Duration(minutes: 9)),
      );

      await queue.retryPending();

      expect(client.sentMessages, hasLength(1));
      expect((await messageById(id)).status, equals(MessageStatus.sent));
    });

    test('does not touch sent or failed messages', () async {
      final sentId = await insertPending(content: 'already sent');
      await repo.updateMessageStatus(sentId, MessageStatus.sent);
      final failedId = await insertPending(content: 'already failed');
      await repo.updateMessageStatus(failedId, MessageStatus.failed);

      await queue.retryPending();

      expect(client.sentMessages, isEmpty);
    });
  });

  group('SendRetryQueue backoff', () {
    test('doubles per retry: 1, 2, 4, 8 minutes', () {
      expect(SendRetryQueue.backoffFor(0), const Duration(minutes: 1));
      expect(SendRetryQueue.backoffFor(1), const Duration(minutes: 2));
      expect(SendRetryQueue.backoffFor(2), const Duration(minutes: 4));
      expect(SendRetryQueue.backoffFor(3), const Duration(minutes: 8));
    });

    test('is capped at 30 minutes', () {
      expect(SendRetryQueue.backoffFor(5), const Duration(minutes: 30));
      expect(SendRetryQueue.backoffFor(10), const Duration(minutes: 30));
    });

    test('a message with no previous attempt is immediately due', () async {
      final id = await insertPending();
      final msg = await messageById(id);
      expect(SendRetryQueue.isDue(msg, DateTime.now()), isTrue);
    });
  });
}
