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

  const channelId = 'chan-1';
  const otherChannelId = 'chan-2';

  setUp(() {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    messages = MessageRepository(db);
    final groups = GroupRepository(db);
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

  RoutingAckUpdate negativeAck(String messageIdHex, {int? status}) =>
      status == null
      ? RoutingAckUpdate.timeout(
          channelId: channelId,
          messageIdHex: messageIdHex,
        )
      : RoutingAckUpdate.ack(
          channelId: channelId,
          messageIdHex: messageIdHex,
          status: status,
          latencyMs: 20000,
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
      },
    );
  });
}
