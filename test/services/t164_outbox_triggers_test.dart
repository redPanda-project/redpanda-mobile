import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

/// T164: the outbox reacts to what the network client learns instead of
/// sitting out its backoff schedule.
///
/// Every test drives the app the way the client does — a state update on
/// [FakeRedPandaClient.stateController], routed through
/// [MessageSyncService]'s persistence chain into the outbox — and never
/// calls the outbox's trigger methods directly. "At once" means: within the
/// pass the trigger kicks, long before the backoff window (>= 30 s) ends.
void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;
  late MessageRepository messages;
  late OutboxService outbox;
  late MessageSyncService sync;
  late GroupRepository groups;

  const channelId = 'chan-1';
  const otherChannelId = 'chan-2';

  setUp(() {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    messages = MessageRepository(db);
    groups = GroupRepository(db);
    outbox = OutboxService(messages, client, groups);
    sync = MessageSyncService(
      client,
      messages,
      OutboundHandleRepository(db),
      db,
      groups,
      outbox,
    );
    sync.start();
  });

  tearDown(() async {
    client.beforeSend = null;
    await sync.dispose();
    await outbox.dispose();
    await client.disconnect();
    await db.close();
  });

  Future<void> insertChannel(String id) => db
      .into(db.channels)
      .insert(
        ChannelsCompanion.insert(
          conversationId: id,
          label: 'Test $id',
          encryptionKey: '00' * 32,
          authPublicKey: '11' * 32,
        ),
        mode: drift.InsertMode.insertOrIgnore,
      );

  Future<Message> messageById(int id) =>
      (db.select(db.messages)..where((t) => t.id.equals(id))).getSingle();

  /// Lets the persistence chain apply what was emitted, then waits for the
  /// pass it kicked.
  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await outbox.settled;
  }

  CounterpartOhUpdate ohUpdate(String channel) => CounterpartOhUpdate(
    channelId: channel,
    descriptors: [
      OHDescriptor(
        serverEndpoint: '127.0.0.1:59558',
        handleId: List<int>.filled(32, 7),
        authPublicKey: List<int>.filled(32, 9),
      ),
    ],
  );

  /// A negative R-ACK ([status]) or, with [status] null, an R-ACK timeout.
  RoutingAckUpdate negativeAck(
    String messageIdHex, {
    int? status,
    String conversationId = channelId,
    String? memberIdHex,
  }) => status == null
      ? RoutingAckUpdate.timeout(
          channelId: conversationId,
          messageIdHex: messageIdHex,
          memberIdHex: memberIdHex,
        )
      : RoutingAckUpdate.ack(
          channelId: conversationId,
          messageIdHex: messageIdHex,
          status: status,
          latencyMs: 20000,
          memberIdHex: memberIdHex,
        );

  /// Enqueues a message whose first attempt succeeds; returns its row id
  /// and the network id the fake client assigned.
  Future<(int, String)> sentMessage() async {
    await insertChannel(channelId);
    final id = await outbox.enqueue(conversationId: channelId, content: 'hi');
    await outbox.settled;
    final msg = await messageById(id);
    expect(msg.status, MessageStatus.sent);
    return (id, msg.messageId!);
  }

  group('T164a: the counterpart mailbox becomes known', () {
    test('a message that failed with UnknownCounterpartException goes out as '
        'soon as CounterpartOhUpdate arrives, not after its backoff', () async {
      await insertChannel(channelId);
      client.sendError = UnknownCounterpartException(channelId);
      final id = await outbox.enqueue(
        conversationId: channelId,
        content: 'hallo',
      );
      await outbox.settled;
      var msg = await messageById(id);
      expect(msg.status, MessageStatus.pending);
      expect(msg.retryCount, 1);
      // Backoff window still open: a plain pass (the 10 s tick) sends nothing.
      expect(OutboxService.isDue(msg, DateTime.now()), isFalse);
      await outbox.runPass();
      expect(client.sentMessages, isEmpty);

      // The client learns the partner's mailbox (rendezvous / oh_update).
      client.sendError = null;
      client.stateController.add(ohUpdate(channelId));
      await settle();

      msg = await messageById(id);
      expect(client.sentMessages.map((m) => m.content), ['hallo']);
      expect(msg.status, MessageStatus.sent);
      // The flush is an attempt like any other — no retry bookkeeping reset.
      expect(msg.retryCount, 1);
      // ... and the new mailbox set is persisted as before.
      final channel = await (db.select(
        db.channels,
      )..where((c) => c.conversationId.equals(channelId))).getSingle();
      expect(channel.counterpartOhSet, isNotNull);
    });

    test('flushes every pending message of THAT channel and only that one, '
        'in one pass', () async {
      await insertChannel(channelId);
      await insertChannel(otherChannelId);
      Future<int> waiting(String channel, String content) => db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: channel,
              content: content,
              timestamp: DateTime.now(),
              status: MessageStatus.pending,
              type: 0,
              retryCount: const drift.Value(3),
              lastRetryAt: drift.Value(DateTime.now()),
            ),
          );
      await waiting(channelId, 'a1');
      await waiting(channelId, 'a2');
      final other = await waiting(otherChannelId, 'b1');

      client.stateController.add(ohUpdate(channelId));
      await settle();

      expect(client.sentMessages.map((m) => m.content), ['a1', 'a2']);
      expect((await messageById(other)).status, MessageStatus.pending);
    });

    test(
      'maxRetries still holds: an exhausted message is failed, not sent',
      () async {
        await insertChannel(channelId);
        final id = await db
            .into(db.messages)
            .insert(
              MessagesCompanion.insert(
                conversationId: channelId,
                content: 'too late',
                timestamp: DateTime.now(),
                status: MessageStatus.pending,
                type: 0,
                retryCount: const drift.Value(OutboxService.maxRetries),
                lastRetryAt: drift.Value(DateTime.now()),
              ),
            );

        client.stateController.add(ohUpdate(channelId));
        await settle();

        expect(client.sentMessages, isEmpty);
        expect((await messageById(id)).status, MessageStatus.failed);
      },
    );

    test('the flush does not hold up the persistence chain while the send '
        'is in flight', () async {
      await insertChannel(channelId);
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: channelId,
              content: 'slow',
              timestamp: DateTime.now(),
              status: MessageStatus.pending,
              type: 0,
              retryCount: const drift.Value(1),
              lastRetryAt: drift.Value(DateTime.now()),
            ),
          );
      final release = Completer<void>();
      client.beforeSend = () => release.future;

      client.stateController.add(ohUpdate(channelId));
      client.stateController.add(
        const RatchetStateUpdate(channelId: channelId, stateJson: '{"r":1}'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The send is still blocked, yet the next state update was written.
      expect(client.sentMessages, isEmpty);
      final channel = await (db.select(
        db.channels,
      )..where((c) => c.conversationId.equals(channelId))).getSingle();
      expect(channel.ratchetState, '{"r":1}');

      release.complete();
      await outbox.settled;
      expect(client.sentMessages.map((m) => m.content), ['slow']);
    });
  });

  group('T164b: negative routing feedback', () {
    for (final (label, status) in <(String, int?)>[
      ('HANDLE_EXPIRED', RoutingAck.statusHandleExpired),
      ('REJECTED', RoutingAck.statusRejected),
      ('an unknown status', 42),
      ('a timeout', null),
    ]) {
      test('$label re-sends the message at once with the same id', () async {
        final (id, netId) = await sentMessage();

        client.stateController.add(negativeAck(netId, status: status));
        await settle();

        final msg = await messageById(id);
        expect(client.sentMessages.map((m) => m.messageId), [null, netId]);
        expect(msg.status, MessageStatus.sent);
        expect(msg.retryCount, 1);
      });
    }

    test('MAILBOX_FULL keeps the normal backoff (re-sending cannot help '
        'until the recipient fetched)', () async {
      final (id, netId) = await sentMessage();

      client.stateController.add(
        negativeAck(netId, status: RoutingAck.statusMailboxFull),
      );
      await settle();

      final msg = await messageById(id);
      expect(client.sentMessages, hasLength(1));
      expect(msg.status, MessageStatus.pending);
      expect(OutboxService.isDue(msg, DateTime.now()), isFalse);
    });

    test(
      'a negative R-ACK for a message no longer `sent` re-sends nothing',
      () async {
        final (id, netId) = await sentMessage();
        client.stateController.add(
          RoutingAckUpdate.ack(
            channelId: channelId,
            messageIdHex: netId,
            status: RoutingAck.statusStored,
            latencyMs: 50,
          ),
        );
        client.stateController.add(
          negativeAck(netId, status: RoutingAck.statusHandleExpired),
        );
        await settle();

        expect(client.sentMessages, hasLength(1));
        expect((await messageById(id)).status, MessageStatus.routed);
      },
    );

    test('loop bound: "send, negative R-ACK, send at once" stops after '
        'maxImmediateAckRetries; then the normal backoff applies', () async {
      final (id, netId) = await sentMessage();

      // A route that fails every time: each send is answered negatively.
      for (var i = 0; i < OutboxService.maxImmediateAckRetries + 2; i++) {
        client.stateController.add(
          negativeAck(
            netId,
            // Timeouts and negative statuses draw on the same budget.
            status: i.isEven ? RoutingAck.statusHandleExpired : null,
          ),
        );
        await settle();
      }

      // 1 first send + maxImmediateAckRetries immediate re-sends. The third
      // negative R-ACK re-queued with backoff; the fourth found the message
      // `pending` (not `sent`) and changed nothing.
      expect(
        client.sentMessages,
        hasLength(1 + OutboxService.maxImmediateAckRetries),
      );
      final msg = await messageById(id);
      expect(msg.status, MessageStatus.pending);
      expect(msg.retryCount, OutboxService.maxImmediateAckRetries + 1);
      expect(OutboxService.isDue(msg, DateTime.now()), isFalse);

      // The regular tick respects that window.
      await outbox.runPass();
      expect(
        client.sentMessages,
        hasLength(1 + OutboxService.maxImmediateAckRetries),
      );
    });

    test(
      'loop bound: the immediate re-send never exceeds maxRetries',
      () async {
        final (id, netId) = await sentMessage();
        await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
          const MessagesCompanion(
            retryCount: drift.Value(OutboxService.maxRetries - 1),
          ),
        );

        client.stateController.add(
          negativeAck(netId, status: RoutingAck.statusHandleExpired),
        );
        await settle();

        expect(client.sentMessages, hasLength(1));
        expect((await messageById(id)).status, MessageStatus.failed);
        // L2: the bookkeeping of a failed message is dropped.
        expect(outbox.trackedAckStates, 0);
      },
    );
  });

  group('T164 review rounds 1 and 2', () {
    final groupId = 'ab' * 32;
    final me = 'aa' * 32;
    final bob = 'bb' * 32;
    final carol = 'cc' * 32;

    Future<void> insertGroup() => groups.insertGroup(
      groupId: groupId,
      label: 'Runde',
      isAdmin: true,
      myMemberId: me,
      mySignSeed: '11' * 32,
      myX25519Priv: '22' * 32,
      keyEpoch: 1,
      members: [
        for (final (id, name) in [(me, 'Me'), (bob, 'Bob'), (carol, 'Carol')])
          GroupMemberInfo(
            memberIdHex: id,
            displayName: name,
            x25519PubHex: '33' * 32,
            role: id == me
                ? GroupMemberInfo.roleAdmin
                : GroupMemberInfo.roleMember,
          ),
      ],
    );

    /// A group message whose first fan-out succeeded.
    Future<(int, String)> sentGroupMessage() async {
      await insertGroup();
      final id = await outbox.enqueue(conversationId: groupId, content: 'g');
      await outbox.settled;
      final msg = await messageById(id);
      expect(msg.status, MessageStatus.sent);
      expect(client.sentGroupMessages, hasLength(1));
      return (id, msg.messageId!);
    }

    test('round 2: a group message keeps the pre-T164 behaviour — negative '
        'member R-ACKs and timeouts re-queue with the normal backoff, '
        'nothing is re-sent at once', () async {
      final (id, netId) = await sentGroupMessage();

      client.stateController.add(
        negativeAck(
          netId,
          status: RoutingAck.statusHandleExpired,
          conversationId: groupId,
          memberIdHex: bob,
        ),
      );
      await settle();

      var msg = await messageById(id);
      expect(client.sentGroupMessages, hasLength(1));
      expect(msg.status, MessageStatus.pending);
      expect(msg.retryCount, 1);
      expect(OutboxService.isDue(msg, DateTime.now()), isFalse);
      // Carol's timeout for the same attempt finds the row `pending`: no-op.
      client.stateController.add(
        negativeAck(netId, conversationId: groupId, memberIdHex: carol),
      );
      await settle();
      msg = await messageById(id);
      expect(client.sentGroupMessages, hasLength(1));
      expect(msg.retryCount, 1);
      expect(outbox.trackedAckStates, 0);

      // Due again after the backoff → one fan-out; a member timeout for it
      // re-queues again, still without an immediate re-send.
      await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
        MessagesCompanion(
          lastRetryAt: drift.Value(
            DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ),
      );
      await outbox.runPass();
      expect(client.sentGroupMessages, hasLength(2));
      client.stateController.add(
        negativeAck(netId, conversationId: groupId, memberIdHex: bob),
      );
      await settle();
      msg = await messageById(id);
      expect(client.sentGroupMessages, hasLength(2));
      expect(msg.status, MessageStatus.pending);
      expect(msg.retryCount, 2);
      expect(outbox.trackedAckStates, 0);
    });

    test(
      'round 2 R8: "send again" restores the immediate re-send budget',
      () async {
        final (id, netId) = await sentMessage();
        for (var i = 0; i <= OutboxService.maxImmediateAckRetries; i++) {
          client.stateController.add(
            negativeAck(netId, status: RoutingAck.statusHandleExpired),
          );
          await settle();
        }
        // Budget used up: the last negative ack left it pending with backoff.
        expect(
          client.sentMessages,
          hasLength(1 + OutboxService.maxImmediateAckRetries),
        );
        expect((await messageById(id)).status, MessageStatus.pending);

        expect(await outbox.retryNow(id), isTrue);
        await outbox.settled;
        expect(
          client.sentMessages,
          hasLength(2 + OutboxService.maxImmediateAckRetries),
        );

        // After the manual retry a negative R-ACK re-sends at once again.
        client.stateController.add(
          negativeAck(netId, status: RoutingAck.statusHandleExpired),
        );
        await settle();
        expect(
          client.sentMessages,
          hasLength(3 + OutboxService.maxImmediateAckRetries),
        );
        expect((await messageById(id)).status, MessageStatus.sent);
      },
    );

    test('round 2, 1:1 stale feedback: the timeout of an attempt that failed '
        'after its ack tag was stored hits the NEXT attempt — it costs at '
        'most the budget, then the backoff takes over', () async {
      // A1 ok → negative R-ACK → A2 at once (budget 1), but A2 fails in the
      // app's eyes (e.g. the isolate call timed out) after the worker had
      // already stored its ack tag.
      final (id, netId) = await sentMessage();
      client.sendError = StateError('isolate call timed out');
      client.stateController.add(
        negativeAck(netId, status: RoutingAck.statusRejected),
      );
      await settle();
      expect((await messageById(id)).status, MessageStatus.pending);

      // A3 on the regular schedule.
      client.sendError = null;
      await outbox.runPass(ignoreBackoff: true);
      expect(client.sentMessages, hasLength(2)); // A1, A3
      expect((await messageById(id)).status, MessageStatus.sent);

      // A2's timeout arrives while A3 is in flight: taken for A3 → A4 at
      // once (budget 2).
      client.stateController.add(negativeAck(netId));
      await settle();
      expect(client.sentMessages, hasLength(3));

      // A3's own negative R-ACK now meets A4: budget used up → backoff.
      client.stateController.add(
        negativeAck(netId, status: RoutingAck.statusHandleExpired),
      );
      await settle();
      expect(client.sentMessages, hasLength(3));
      final msg = await messageById(id);
      expect(msg.status, MessageStatus.pending);
      expect(OutboxService.isDue(msg, DateTime.now()), isFalse);
    });

    test('L1: a pass that fails before reading the pending set keeps the '
        'targeted request for the next pass', () async {
      final flaky = _FlakyMessageRepository(db);
      final local = OutboxService(flaky, client, groups);
      addTearDown(local.dispose);
      await insertChannel(channelId);
      final id = await local.enqueue(conversationId: channelId, content: 'x');
      await local.settled;
      final netId = (await messageById(id)).messageId!;

      flaky.failNextPendingRead = true;
      await local.onRoutingAck(
        negativeAck(netId, status: RoutingAck.statusHandleExpired),
      );
      // This pass throws; `settled` hands the error on.
      await expectLater(local.settled, throwsStateError);
      expect(client.sentMessages, hasLength(1));
      expect((await messageById(id)).status, MessageStatus.pending);

      await local.runPass(); // the next tick
      expect(client.sentMessages, hasLength(2));
      expect((await messageById(id)).status, MessageStatus.sent);
    });

    test('L3: a row confirmed while the pass was busy elsewhere is not '
        'sent with its stale snapshot', () async {
      await insertChannel(channelId);
      Future<int> pending(String content, String netId) => db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: channelId,
              content: content,
              timestamp: DateTime.now(),
              status: MessageStatus.pending,
              type: 0,
              retryCount: const drift.Value(1),
              lastRetryAt: drift.Value(DateTime.now()),
              messageId: drift.Value(netId),
            ),
          );
      await pending('first', 'net-a');
      final second = await pending('second', 'net-b');
      final release = Completer<void>();
      client.beforeSend = () {
        client.beforeSend = null;
        return release.future;
      };

      client.stateController.add(ohUpdate(channelId));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // 'first' is in flight; the partner confirms 'second' meanwhile.
      client.stateController.add(
        const ChannelAckUpdate(
          timestampMs: 0,
          channelId: channelId,
          messageIdHex: 'net-b',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      release.complete();
      await outbox.settled;

      expect(client.sentMessages.map((m) => m.content), ['first']);
      expect((await messageById(second)).status, MessageStatus.delivered);
    });

    test('a targeted request that arrives while another pass is sending is '
        'served by the rerun, despite an open backoff window', () async {
      final (sentId, netId) = await sentMessage();
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: channelId,
              content: 'blocker',
              timestamp: DateTime.now(),
              status: MessageStatus.pending,
              type: 0,
            ),
          );
      final release = Completer<void>();
      client.beforeSend = () {
        client.beforeSend = null;
        return release.future;
      };
      unawaited(outbox.runPass()); // sends 'blocker', blocks
      await Future<void>.delayed(const Duration(milliseconds: 20));

      client.stateController.add(
        negativeAck(netId, status: RoutingAck.statusHandleExpired),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      release.complete();
      await outbox.settled;

      expect(client.sentMessages.map((m) => m.content), [
        'hi',
        'blocker',
        'hi',
      ]);
      expect((await messageById(sentId)).status, MessageStatus.sent);
    });

    test('a negative R-ACK after dispose sends nothing', () async {
      final (_, netId) = await sentMessage();
      await outbox.dispose();

      await outbox.onRoutingAck(
        negativeAck(netId, status: RoutingAck.statusHandleExpired),
      );
      await outbox.settled;

      expect(client.sentMessages, hasLength(1));
    });

    test('M2 (kept): a Channel-ACK that beat the timeout leaves nothing to '
        're-send', () async {
      final (id, netId) = await sentMessage();
      client.stateController.add(
        ChannelAckUpdate(
          timestampMs: 0,
          channelId: channelId,
          messageIdHex: netId,
        ),
      );
      client.stateController.add(negativeAck(netId));
      await settle();

      expect(client.sentMessages, hasLength(1));
      expect((await messageById(id)).status, MessageStatus.delivered);
    });
  });
}

/// A repository whose next pending-set read fails (T164 review L1).
class _FlakyMessageRepository extends MessageRepository {
  _FlakyMessageRepository(super.db);

  bool failNextPendingRead = false;

  @override
  Future<List<Message>> getPendingMessages() {
    if (failNextPendingRead) {
      failNextPendingRead = false;
      return Future.error(StateError('disk I/O error'));
    }
    return super.getPendingMessages();
  }
}
