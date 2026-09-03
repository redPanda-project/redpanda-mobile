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

/// Frontend MS06: R-ACK / Channel-ACK handling and node-score persistence
/// in the app layer.
void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;
  late MessageRepository messages;
  late MessageSyncService service;

  const channelId = 'chan-1';
  const messageIdHex = 'aabbccdd00112233aabbccdd00112233';

  setUp(() {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    messages = MessageRepository(db);
    final groups = GroupRepository(db);
    // T112: the sync service routes ACK updates into the outbox, which owns
    // the transitions — these tests drive the whole path from the wire event.
    service = MessageSyncService(
      client,
      messages,
      OutboundHandleRepository(db),
      db,
      groups,
      OutboxService(messages, client, groups),
    );
    service.start();
  });

  tearDown(() async {
    await service.dispose();
    await client.disconnect();
    await db.close();
  });

  Future<int> insertSentMessage({int status = MessageStatus.sent}) async {
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            uuid: channelId,
            label: 'Test',
            encryptionKey: '00' * 32,
            authPublicKey: '11' * 32,
          ),
          mode: drift.InsertMode.insertOrIgnore,
        );
    final id = await messages.insertOutgoing(
      conversationId: channelId,
      senderId: 'me',
      content: 'hallo',
      messageId: messageIdHex,
    );
    await messages.updateMessageStatus(id, status);
    return id;
  }

  Future<Message> messageById(int id) =>
      (db.select(db.messages)..where((t) => t.id.equals(id))).getSingle();

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 50));

  group('R-ACK handling', () {
    test('stored R-ACK moves sent → routed', () async {
      final id = await insertSentMessage();
      client.stateController.add(
        const RoutingAckUpdate.ack(
          channelId: channelId,
          messageIdHex: messageIdHex,
          status: RoutingAck.statusStored,
          latencyMs: 1234,
        ),
      );
      await pump();
      expect((await messageById(id)).status, MessageStatus.routed);
    });

    test('a late R-ACK never downgrades delivered', () async {
      final id = await insertSentMessage(status: MessageStatus.delivered);
      client.stateController.add(
        const RoutingAckUpdate.ack(
          channelId: channelId,
          messageIdHex: messageIdHex,
          status: RoutingAck.statusStored,
          latencyMs: 1234,
        ),
      );
      await pump();
      expect((await messageById(id)).status, MessageStatus.delivered);
    });

    test('HANDLE_EXPIRED re-queues the message with backoff', () async {
      final id = await insertSentMessage();
      client.stateController.add(
        const RoutingAckUpdate.ack(
          channelId: channelId,
          messageIdHex: messageIdHex,
          status: RoutingAck.statusHandleExpired,
          latencyMs: 1234,
        ),
      );
      await pump();
      final msg = await messageById(id);
      expect(msg.status, MessageStatus.pending);
      expect(msg.retryCount, 1);
      expect(msg.lastRetryAt, isNotNull);
    });

    test('timeout re-queues only messages still in sent', () async {
      final id = await insertSentMessage(status: MessageStatus.routed);
      client.stateController.add(
        const RoutingAckUpdate.timeout(
          channelId: channelId,
          messageIdHex: messageIdHex,
        ),
      );
      await pump();
      expect((await messageById(id)).status, MessageStatus.routed);
    });
  });

  group('Channel-ACK handling', () {
    test('moves the message to delivered from any send state', () async {
      final id = await insertSentMessage(status: MessageStatus.failed);
      client.stateController.add(
        const ChannelAckUpdate(
          channelId: channelId,
          messageIdHex: messageIdHex,
          timestampMs: 1,
        ),
      );
      await pump();
      expect((await messageById(id)).status, MessageStatus.delivered);
    });
  });

  group('node score persistence', () {
    test('snapshots are upserted and restored on startup', () async {
      client.stateController.add(
        NodeScoreUpdate([
          NodeScore(
            nodeIdHex: 'aa' * 20,
            successCount: 4,
            failureCount: 1,
            avgLatencyMs: 250,
            lastUpdatedMs: 1751500000000,
          ),
        ]),
      );
      await pump();

      final rows = await db.select(db.nodeScores).get();
      expect(rows, hasLength(1));
      expect(rows.single.successCount, 4);

      // Second snapshot for the same node replaces the row.
      client.stateController.add(
        NodeScoreUpdate([
          NodeScore(
            nodeIdHex: 'aa' * 20,
            successCount: 5,
            failureCount: 1,
            avgLatencyMs: 240,
            lastUpdatedMs: 1751500001000,
          ),
        ]),
      );
      await pump();
      final updated = await db.select(db.nodeScores).get();
      expect(updated.single.successCount, 5);

      await service.restorePersistedState();
      expect(client.restoredNodeScores, hasLength(1));
      expect(client.restoredNodeScores.single.successCount, 5);
    });
  });
}
