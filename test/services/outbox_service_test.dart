import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart'
    show
        ChannelAckUpdate,
        DepositException,
        DepositStatus,
        RoutingAck,
        RoutingAckUpdate,
        UnknownPeerException;

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late MessageRepository repo;
  late FakeRedPandaClient client;
  late OutboxService outbox;

  setUp(() {
    db = createTestDatabase();
    repo = MessageRepository(db);
    client = FakeRedPandaClient();
    outbox = OutboxService(repo, client, GroupRepository(db));
  });

  tearDown(() async {
    client.beforeSend = null;
    await outbox.dispose();
    await client.disconnect();
    await db.close();
  });

  Future<int> insertPending({
    String content = 'msg',
    int retryCount = 0,
    DateTime? lastRetryAt,
    String? messageId,
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
            messageId: drift.Value(messageId),
          ),
        );
  }

  Future<Message> messageById(int id) {
    return (db.select(db.messages)..where((t) => t.id.equals(id))).getSingle();
  }

  group('OutboxService.runPass', () {
    test('successful retry marks the message as sent', () async {
      final id = await insertPending(content: 'retry me');

      await outbox.runPass();

      expect(client.sentMessages, hasLength(1));
      expect(client.sentMessages.single.content, equals('retry me'));
      expect((await messageById(id)).status, equals(MessageStatus.sent));
    });

    test(
      'failed retry increments retryCount and keeps the message pending',
      () async {
        client.sendError = StateError('no active peer');
        final id = await insertPending();

        await outbox.runPass();

        final msg = await messageById(id);
        expect(msg.status, equals(MessageStatus.pending));
        expect(msg.retryCount, equals(1));
        expect(msg.lastRetryAt, isNotNull);
      },
    );

    test('message is marked failed after maxRetries attempts', () async {
      final id = await insertPending(retryCount: OutboxService.maxRetries);

      await outbox.runPass();

      expect((await messageById(id)).status, equals(MessageStatus.failed));
      expect(client.sentMessages, isEmpty);
    });

    test('respects the backoff window between attempts', () async {
      // Last attempt just now with 3 failures → due again in 2 minutes.
      await insertPending(retryCount: 3, lastRetryAt: DateTime.now());

      await outbox.runPass();

      expect(client.sentMessages, isEmpty);
    });

    test('retries again once the backoff window has elapsed', () async {
      final id = await insertPending(
        retryCount: 3,
        lastRetryAt: DateTime.now().subtract(const Duration(minutes: 9)),
      );

      await outbox.runPass();

      expect(client.sentMessages, hasLength(1));
      expect((await messageById(id)).status, equals(MessageStatus.sent));
    });

    test('first send persists the network message id on the row', () async {
      final id = await insertPending(content: 'first send');

      await outbox.runPass();

      // The fake mints "fake-1" when no id is supplied; it must be stored.
      expect(client.sentMessages.single.messageId, isNull);
      expect((await messageById(id)).messageId, equals('fake-1'));
    });

    test('retry reuses the same network message id across attempts', () async {
      // A pending message that already carries a stable network id (e.g. a
      // previous attempt assigned it). Every retry must pass that exact id.
      final id = await insertPending(
        content: 'stable',
        messageId: 'stable-net-id',
      );

      await outbox.runPass();

      expect(client.sentMessages, hasLength(1));
      expect(client.sentMessages.single.messageId, equals('stable-net-id'));
      // The id is unchanged after the send.
      expect((await messageById(id)).messageId, equals('stable-net-id'));
    });

    test('BAD_REQUEST (item too large) marks the message failed', () async {
      // MS02b: re-sending an oversize payload can never succeed.
      client.sendError = DepositException(DepositStatus.badRequest);
      final id = await insertPending();

      await outbox.runPass();

      expect((await messageById(id)).status, equals(MessageStatus.failed));
    });

    test('QUOTA_EXCEEDED keeps pending with a widened backoff', () async {
      // MS02b: recipient mailbox is full (reject-new) — back off harder.
      client.sendError = DepositException(DepositStatus.quotaExceeded);
      final id = await insertPending();

      await outbox.runPass();

      final msg = await messageById(id);
      expect(msg.status, equals(MessageStatus.pending));
      expect(msg.retryCount, equals(OutboxService.quotaExceededPenalty));
      expect(msg.lastRetryAt, isNotNull);
    });

    test('NOT_FOUND keeps pending with the normal backoff', () async {
      // MS02b: not deliverable right now (hop limit) — routing may recover.
      client.sendError = DepositException(DepositStatus.notFound);
      final id = await insertPending();

      await outbox.runPass();

      final msg = await messageById(id);
      expect(msg.status, equals(MessageStatus.pending));
      expect(msg.retryCount, equals(1));
    });

    test('REDPANDAJ-2DR: unknown peer OH keeps the message pending with the '
        'normal backoff instead of a doomed empty-oh_id deposit', () async {
      // sendMessage refuses to deposit with an empty oh_id (would be
      // misparsed by the node as a GMAck frame) and throws
      // UnknownPeerException instead — the message must stay queued for
      // retry, not be marked failed or lost.
      client.sendError = UnknownPeerException('channel-1');
      final id = await insertPending();

      await outbox.runPass();

      final msg = await messageById(id);
      expect(msg.status, equals(MessageStatus.pending));
      expect(msg.retryCount, equals(1));
      expect(msg.lastRetryAt, isNotNull);
    });

    test('REDPANDAJ-2DR: once the peer OH becomes known, a subsequent retry '
        'pass delivers the message', () async {
      client.sendError = UnknownPeerException('channel-1');
      final id = await insertPending(
        retryCount: 3,
        lastRetryAt: DateTime.now().subtract(const Duration(minutes: 9)),
      );

      await outbox.runPass();
      expect((await messageById(id)).status, equals(MessageStatus.pending));
      expect(client.sentMessages, isEmpty);

      // Peer OH is now known (e.g. the partner's handshake arrived) —
      // sendMessage succeeds on the next due retry pass. Push lastRetryAt
      // back far enough for the backoff window to be open again.
      client.sendError = null;
      await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
        MessagesCompanion(
          lastRetryAt: drift.Value(
            DateTime.now().subtract(const Duration(minutes: 30)),
          ),
        ),
      );

      await outbox.runPass();

      expect(client.sentMessages, hasLength(1));
      expect((await messageById(id)).status, equals(MessageStatus.sent));
    });

    test('does not touch sent or failed messages', () async {
      final sentId = await insertPending(content: 'already sent');
      await repo.updateMessageStatus(sentId, MessageStatus.sent);
      final failedId = await insertPending(content: 'already failed');
      await repo.updateMessageStatus(failedId, MessageStatus.failed);

      await outbox.runPass();

      expect(client.sentMessages, isEmpty);
    });

    test('TD002/T51: a message stuck sent without an ack (e.g. no ack tag was '
        'ever requested) self-heals during a running session, no app restart '
        'needed', () async {
      final id = await insertPending(content: 'lost without an ack tag');
      // First attempt "succeeds" (handed to the network) but never gets an
      // R-ACK — the scenario RedPandaLightClient._buildReturnPath produces
      // when the sender has no own OH yet / the payload exceeds the ack
      // budget: sendMessage() returns normally, so the row is marked sent,
      // but no AckTagStore entry (and hence no timeout requeue) ever
      // exists for it.
      await outbox.runPass();
      expect((await messageById(id)).status, equals(MessageStatus.sent));
      expect(client.sentMessages, hasLength(1));

      // Backdate lastRetryAt past the staleSentThreshold — simulates time
      // passing with the app still running (no restart, no
      // requeueStuckSent()).
      await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
        MessagesCompanion(
          lastRetryAt: drift.Value(
            DateTime.now().subtract(
              OutboxService.staleSentThreshold + const Duration(seconds: 1),
            ),
          ),
        ),
      );

      await outbox.runPass();

      expect(
        client.sentMessages,
        hasLength(2),
        reason:
            'the stale-sent sweep must pull the message back into '
            'pending and the very same pass must resend it',
      );
      expect((await messageById(id)).status, equals(MessageStatus.sent));
    });

    test('TD002/T51: a permanently ack-less send with a high retryCount is '
        'swept back to pending but respects its backoff — no immediate '
        'resend in the same pass', () async {
      // Simulates a message the sweep already requeued and resent several
      // times without ever getting an ack: retryCount climbed, but
      // lastRetryAt is deliberately never touched by requeueStaleSent, so
      // it still reflects the ORIGINAL stale-sent timestamp — 4 minutes
      // ago clears the 3 min sweep threshold but is nowhere near
      // backoffFor(6) = 16 min.
      final id = await insertPending(content: 'endless ack-less send');
      await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
        MessagesCompanion(
          status: const drift.Value(MessageStatus.sent),
          retryCount: const drift.Value(5),
          lastRetryAt: drift.Value(
            DateTime.now().subtract(const Duration(minutes: 4)),
          ),
        ),
      );

      await outbox.runPass();

      expect(
        client.sentMessages,
        isEmpty,
        reason:
            'the sweep must pull the row back to pending (proven by the '
            'status below), but the pending-pass in the very same call '
            'must not resend it — retryCount 5→6 is nowhere near its due '
            'time yet',
      );
      final msg = await messageById(id);
      expect(msg.status, equals(MessageStatus.pending));
      expect(msg.retryCount, equals(6));
    });

    test('TD002/T51: a sent message still within the ack-timeout window is '
        'left alone by the stale-sent sweep', () async {
      final id = await insertPending(content: 'freshly sent');
      await outbox.runPass();
      expect(client.sentMessages, hasLength(1));

      // Immediately re-run the sweep: lastRetryAt is only seconds old, far
      // below staleSentThreshold — must not be touched (would otherwise
      // race the normal R-ACK-timeout requeue and duplicate-send).
      await outbox.runPass();

      expect(client.sentMessages, hasLength(1));
      expect((await messageById(id)).status, equals(MessageStatus.sent));
    });
  });

  group('OutboxService.enqueue (T112: the UI only enqueues)', () {
    test('inserts a pending row and sends it in the same breath', () async {
      final rowId = await outbox.enqueue(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'hello',
      );

      // enqueue() returns as soon as the row exists; the attempt itself runs
      // on the outbox's own pass.
      await outbox.settled;

      expect(client.sentMessages.single.content, equals('hello'));
      final msg = await messageById(rowId);
      expect(msg.status, equals(MessageStatus.sent));
      expect(msg.messageId, equals('fake-1'));
    });

    test('a message enqueued while a pass is running still goes out '
        'immediately (rerun instead of drop)', () async {
      // Block the first pass inside the send so the second enqueue lands
      // while _passInProgress is set.
      final gate = Completer<void>();
      client.beforeSend = () => gate.future;
      await insertPending(content: 'slow one');
      final pass = outbox.runPass();
      await pumpEventQueue();

      client.beforeSend = null;
      await outbox.enqueue(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'while busy',
      );
      gate.complete();
      await pass;
      await outbox.settled;

      expect(
        client.sentMessages.map((m) => m.content),
        containsAll(<String>['slow one', 'while busy']),
        reason:
            'the composer used to bypass the queue to get this latency; '
            'the rerun is what replaces that',
      );
    });

    test('QUOTA_EXCEEDED on the FIRST attempt gets the same penalty as on a '
        'retry (one policy, T112)', () async {
      // The chat screen used to apply plain markRetryAttempt() here, so a
      // composer send into a full mailbox retried after 10 s instead of the
      // 4 min the queue would have waited.
      client.sendError = DepositException(DepositStatus.quotaExceeded);

      final rowId = await outbox.enqueue(
        conversationId: 'channel-1',
        senderId: 'me',
        content: 'mailbox full',
      );
      await outbox.settled;

      final msg = await messageById(rowId);
      expect(msg.status, equals(MessageStatus.pending));
      expect(msg.retryCount, equals(OutboxService.quotaExceededPenalty));
    });

    test('retryNow refuses to re-send a message an ACK already confirmed '
        '(adversarial review)', () async {
      // The details sheet offers "send again" from a SNAPSHOT of the row; an
      // ACK can land between rendering that button and the tap. Before T112
      // resetForImmediateRetry was an unconditional write and would have
      // re-sent a message the recipient already had.
      final id = await insertPending(messageId: 'net-1');
      await outbox.runPass();
      await outbox.onChannelAck(
        const ChannelAckUpdate(
          channelId: 'channel-1',
          messageIdHex: 'net-1',
          timestampMs: 1,
        ),
      );
      final sentBefore = client.sentMessages.length;

      expect(await outbox.retryNow(id), isFalse);
      await outbox.settled;

      expect(client.sentMessages, hasLength(sentBefore));
      expect((await messageById(id)).status, equals(MessageStatus.delivered));
    });

    test('a retry attempt is not booked on a message confirmed mid-send '
        '(adversarial review)', () async {
      // The send fails, but while it was in flight the Channel-ACK arrived.
      // markRetryAttempt must not stamp a fresh backoff window on a row that
      // is done — the status column stays put either way, so only the
      // bookkeeping shows it.
      final id = await insertPending(messageId: 'net-1');
      client.beforeSend = () async {
        await outbox.onChannelAck(
          const ChannelAckUpdate(
            channelId: 'channel-1',
            messageIdHex: 'net-1',
            timestampMs: 1,
          ),
        );
        throw StateError('no active peer');
      };

      await outbox.runPass();

      final msg = await messageById(id);
      expect(msg.status, equals(MessageStatus.delivered));
      expect(msg.retryCount, equals(0));
      expect(msg.lastRetryAt, isNull);
    });

    test('retryNow clears the backoff and attempts immediately', () async {
      final id = await insertPending(
        retryCount: 7,
        lastRetryAt: DateTime.now(),
      );

      await outbox.retryNow(id);
      await outbox.settled;

      expect(client.sentMessages, hasLength(1));
      final msg = await messageById(id);
      expect(msg.status, equals(MessageStatus.sent));
    });
  });

  group('OutboxService.attempts (T112 DeliveryAttempt)', () {
    test(
      'reports the outcome of every attempt with its attempt number',
      () async {
        final seen = <DeliveryAttempt>[];
        final sub = outbox.attempts.listen(seen.add);

        client.sendError = DepositException(DepositStatus.notFound);
        final id = await insertPending(content: 'attempt me');
        await outbox.runPass();

        client.sendError = null;
        await outbox.runPass(ignoreBackoff: true);
        await pumpEventQueue();
        await sub.cancel();

        expect(seen, hasLength(2));
        expect(seen.first.messageRowId, equals(id));
        expect(seen.first.conversationId, equals('channel-1'));
        expect(seen.first.attempt, equals(1));
        expect(seen.first.failure, equals(DeliveryFailure.depositRejected));
        expect(seen.first.succeeded, isFalse);
        expect(seen.last.attempt, equals(2));
        expect(seen.last.succeeded, isTrue);
      },
    );

    test('the attempt number is the backoff step, which the QUOTA penalty '
        'advances by more than one (Copilot review)', () async {
      final seen = <DeliveryAttempt>[];
      final sub = outbox.attempts.listen(seen.add);
      client.sendError = DepositException(DepositStatus.quotaExceeded);
      await insertPending();

      await outbox.runPass();
      await outbox.runPass(ignoreBackoff: true);
      await pumpEventQueue();
      await sub.cancel();

      expect(
        seen.map((a) => a.attempt),
        equals([1, 1 + OutboxService.quotaExceededPenalty]),
        reason:
            'attempt is retryCount + 1, so it is a backoff step, not a '
            'count of network attempts — only attempt == 1 is load-bearing',
      );
    });

    test(
      'an unreachable counterpart is reported as its own failure kind',
      () async {
        final seen = <DeliveryAttempt>[];
        final sub = outbox.attempts.listen(seen.add);
        client.sendError = UnknownPeerException('channel-1');
        await insertPending();

        await outbox.runPass();
        await pumpEventQueue();
        await sub.cancel();

        expect(seen.single.failure, equals(DeliveryFailure.unknownCounterpart));
      },
    );
  });

  group('OutboxService ack transitions (T112: one owner)', () {
    test('a stored R-ACK moves the message to routed', () async {
      final id = await insertPending(messageId: 'net-1');
      await outbox.runPass();
      expect((await messageById(id)).status, equals(MessageStatus.sent));

      await outbox.onRoutingAck(
        const RoutingAckUpdate.ack(
          channelId: 'channel-1',
          messageIdHex: 'net-1',
          status: RoutingAck.statusStored,
          latencyMs: 12,
        ),
      );

      expect((await messageById(id)).status, equals(MessageStatus.routed));
    });

    test('an R-ACK timeout re-queues the message for fresh hops', () async {
      final id = await insertPending(messageId: 'net-1');
      await outbox.runPass();

      await outbox.onRoutingAck(
        const RoutingAckUpdate.timeout(
          channelId: 'channel-1',
          messageIdHex: 'net-1',
        ),
      );

      final msg = await messageById(id);
      expect(msg.status, equals(MessageStatus.pending));
      expect(msg.retryCount, equals(1));
    });

    test('a Channel-ACK moves the message to delivered', () async {
      final id = await insertPending(messageId: 'net-1');
      await outbox.runPass();

      await outbox.onChannelAck(
        const ChannelAckUpdate(
          channelId: 'channel-1',
          messageIdHex: 'net-1',
          timestampMs: 1,
        ),
      );

      expect((await messageById(id)).status, equals(MessageStatus.delivered));
    });

    test('a late R-ACK never downgrades a delivered message', () async {
      final id = await insertPending(messageId: 'net-1');
      await outbox.runPass();
      await outbox.onChannelAck(
        const ChannelAckUpdate(
          channelId: 'channel-1',
          messageIdHex: 'net-1',
          timestampMs: 1,
        ),
      );

      await outbox.onRoutingAck(
        const RoutingAckUpdate.ack(
          channelId: 'channel-1',
          messageIdHex: 'net-1',
          status: RoutingAck.statusStored,
          latencyMs: 12,
        ),
      );

      expect((await messageById(id)).status, equals(MessageStatus.delivered));
    });

    test('a Channel-ACK that lands between the deposit and markSent is not '
        'downgraded to sent (lifecycle guard, T112)', () async {
      // The real race: sendMessage() has returned, the ack for the very same
      // message arrives while the outbox is still writing the row. Before
      // T112 markSent() was an unguarded write and turned `delivered` back
      // into `sent`, hiding the double check from the user forever.
      final id = await insertPending(messageId: 'net-1');
      client.beforeSend = () async {
        await outbox.onChannelAck(
          const ChannelAckUpdate(
            channelId: 'channel-1',
            messageIdHex: 'net-1',
            timestampMs: 1,
          ),
        );
      };

      await outbox.runPass();

      expect((await messageById(id)).status, equals(MessageStatus.delivered));
    });
  });

  group('OutboxService backoff', () {
    test('fast early retries then exponential tail', () {
      // retryCount 0/1 fire within seconds so a dropped first attempt
      // re-sends quickly; from retryCount 2 the tail doubles per step.
      expect(OutboxService.backoffFor(0), const Duration(seconds: 10));
      expect(OutboxService.backoffFor(1), const Duration(seconds: 30));
      expect(OutboxService.backoffFor(2), const Duration(minutes: 1));
      expect(OutboxService.backoffFor(3), const Duration(minutes: 2));
      expect(OutboxService.backoffFor(4), const Duration(minutes: 4));
      expect(OutboxService.backoffFor(5), const Duration(minutes: 8));
      expect(OutboxService.backoffFor(6), const Duration(minutes: 16));
    });

    test('is capped at 30 minutes', () {
      expect(OutboxService.backoffFor(7), const Duration(minutes: 30));
      expect(OutboxService.backoffFor(12), const Duration(minutes: 30));
    });

    test('QUOTA_EXCEEDED penalty still backs off at least 4 minutes', () {
      // The mailbox-full penalty must not shrink to a few-second early
      // window: backoffFor(quotaExceededPenalty) must stay >= 4 minutes.
      expect(
        OutboxService.backoffFor(OutboxService.quotaExceededPenalty),
        greaterThanOrEqualTo(const Duration(minutes: 4)),
      );
    });

    test('a message with no previous attempt is immediately due', () async {
      final id = await insertPending();
      final msg = await messageById(id);
      expect(OutboxService.isDue(msg, DateTime.now()), isTrue);
    });
  });
}
