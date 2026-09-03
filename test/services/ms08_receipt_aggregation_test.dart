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

/// MS08, Decision 13: outgoing group messages aggregate per-member
/// receipts — `routed` once every other member's mailbox confirmed via
/// R-ACK, `delivered` once every member sent a Channel-ACK.
void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;
  late MessageRepository messages;
  late GroupRepository groups;
  late OutboxService outbox;
  late MessageSyncService service;

  final groupId = 'ab' * 32;
  final me = 'aa' * 32;
  final bob = 'bb' * 32;
  final carol = 'cc' * 32;
  const messageIdHex = '00112233445566778899aabbccddeeff';

  setUp(() async {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    messages = MessageRepository(db);
    groups = GroupRepository(db);
    outbox = OutboxService(messages, client, groups);
    service = MessageSyncService(
      client,
      messages,
      OutboundHandleRepository(db),
      db,
      groups,
      outbox,
    );
    service.start();

    await groups.insertGroup(
      groupId: groupId,
      label: 'Runde',
      isAdmin: true,
      myMemberId: me,
      mySignSeed: '11' * 32,
      myX25519Priv: '22' * 32,
      keyEpoch: 1,
      members: [
        GroupMemberInfo(
          memberIdHex: me,
          displayName: 'Me',
          x25519PubHex: '33' * 32,
          role: GroupMemberInfo.roleAdmin,
        ),
        GroupMemberInfo(
          memberIdHex: bob,
          displayName: 'Bob',
          x25519PubHex: '44' * 32,
          role: GroupMemberInfo.roleMember,
        ),
        GroupMemberInfo(
          memberIdHex: carol,
          displayName: 'Carol',
          x25519PubHex: '55' * 32,
          role: GroupMemberInfo.roleMember,
        ),
      ],
    );

    // The outgoing group message under test (status sent).
    final rowId = await messages.insertOutgoing(
      conversationId: groupId,
      senderId: 'me-uuid',
      content: 'hallo gruppe',
      messageId: messageIdHex,
    );
    await messages.updateMessageStatus(rowId, MessageStatus.sent);
  });

  tearDown(() async {
    await service.stop();
    await outbox.dispose();
    await client.disconnect();
    await db.close();
  });

  Future<Message> messageRow() {
    return (db.select(
      db.messages,
    )..where((t) => t.messageId.equals(messageIdHex))).getSingle();
  }

  test('routed only after ALL other members confirmed via R-ACK', () async {
    await outbox.onRoutingAck(
      RoutingAckUpdate.ack(
        channelId: groupId,
        messageIdHex: messageIdHex,
        status: RoutingAck.statusStored,
        latencyMs: 100,
        memberIdHex: bob,
      ),
    );
    expect((await messageRow()).status, MessageStatus.sent);

    await outbox.onRoutingAck(
      RoutingAckUpdate.ack(
        channelId: groupId,
        messageIdHex: messageIdHex,
        status: RoutingAck.statusStored,
        latencyMs: 120,
        memberIdHex: carol,
      ),
    );
    expect((await messageRow()).status, MessageStatus.routed);
  });

  test('delivered only after ALL other members sent a Channel-ACK', () async {
    await outbox.onChannelAck(
      ChannelAckUpdate(
        channelId: groupId,
        messageIdHex: messageIdHex,
        timestampMs: 1,
        memberIdHex: bob,
      ),
    );
    expect((await messageRow()).status, MessageStatus.sent);

    await outbox.onChannelAck(
      ChannelAckUpdate(
        channelId: groupId,
        messageIdHex: messageIdHex,
        timestampMs: 2,
        memberIdHex: carol,
      ),
    );
    expect((await messageRow()).status, MessageStatus.delivered);
  });

  test('a member R-ACK timeout re-queues the fan-out', () async {
    await outbox.onRoutingAck(
      RoutingAckUpdate.timeout(
        channelId: groupId,
        messageIdHex: messageIdHex,
        memberIdHex: carol,
      ),
    );
    final row = await messageRow();
    expect(row.status, MessageStatus.pending);
    expect(row.retryCount, 1);
  });

  test('incoming group messages persist the authenticated sender', () async {
    await service.handleIncomingMessage(
      DecryptedMessage(
        id: 'ffee' * 8,
        content: 'hi von bob',
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        channelId: groupId,
        senderMemberIdHex: bob,
      ),
    );
    final row = await (db.select(
      db.messages,
    )..where((t) => t.messageId.equals('ffee' * 8))).getSingle();
    expect(row.senderMemberId, bob);
    expect(row.senderId, bob);
    expect(row.status, MessageStatus.received);
    expect(row.conversationId, groupId);

    // Receipts for foreign messages never downgrade received rows.
    await outbox.onChannelAck(
      ChannelAckUpdate(
        channelId: groupId,
        messageIdHex: 'ffee' * 8,
        timestampMs: 3,
        memberIdHex: carol,
      ),
    );
    await outbox.onChannelAck(
      ChannelAckUpdate(
        channelId: groupId,
        messageIdHex: 'ffee' * 8,
        timestampMs: 4,
        memberIdHex: me,
      ),
    );
    final after = await (db.select(
      db.messages,
    )..where((t) => t.messageId.equals('ffee' * 8))).getSingle();
    expect(after.status, MessageStatus.received);
  });

  test('drift companion for messages keeps senderMemberId nullable', () async {
    final row = await messageRow();
    expect(row.senderMemberId, isNull);
    await (db.update(db.messages)..where((t) => t.id.equals(row.id))).write(
      MessagesCompanion(senderMemberId: drift.Value(bob)),
    );
    expect((await messageRow()).senderMemberId, bob);
  });
}
