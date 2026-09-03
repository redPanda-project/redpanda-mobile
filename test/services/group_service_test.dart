import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart' hide Channel;
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;
  late GroupRepository groups;
  late GroupService service;

  setUp(() {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    client.ohRegistrationFactory = (channelId) async => OHRegistration(
      ohId: List.filled(20, 7),
      keypair: await OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      channelId: channelId,
      serverEndpoint: 'localhost:59558',
    );
    groups = GroupRepository(db);
    service = GroupService(client, groups, OutboundHandleRepository(db));
    service.start();
  });

  tearDown(() async {
    await service.stop();
    await client.disconnect();
    await db.close();
  });

  Future<Channel> insertCounterpartChannel(String label) async {
    final channel = Channel(
      label: label,
      channelSecret: List.filled(32, 3),
      encryptionKey: List.filled(32, 1),
      authPublicKey: List.filled(32, 2),
      counterpartOhDescriptor: OHDescriptor(
        serverEndpoint: 'localhost:59559',
        handleId: List.filled(20, 3),
        authPublicKey: List.filled(32, 4),
      ),
    );
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            conversationId: channel.id,
            label: label,
            encryptionKey: HEX.encode(channel.encryptionKey),
            authPublicKey: HEX.encode(channel.authPublicKey),
          ),
        );
    return channel;
  }

  test('createGroup registers the group, rotates to epoch 1 and sends '
      'invites over the 1:1 channels', () async {
    final channel = await insertCounterpartChannel('Bob');
    final groupId = await service.createGroup('Runde', [channel]);

    // Group row persisted with own identity.
    final row = await groups.getGroup(groupId);
    expect(row, isNotNull);
    expect(row!.isAdmin, isTrue);
    expect(row.myMemberId.length, 64);

    // Registered in the client and immediately keyed (epoch 1, admin only).
    expect(client.registeredGroups, hasLength(1));
    expect(client.rotations, hasLength(1));
    expect(client.rotations.single.members, hasLength(1));
    expect(
      client.rotations.single.members.single.role,
      GroupMemberInfo.roleAdmin,
    );

    // The invite proposal went out over the 1:1 channel and pins the admin.
    expect(client.sentHandshakes, hasLength(1));
    expect(client.sentHandshakes.single.channelId, channel.id);
    final handshake = GroupHandshake.decode(
      client.sentHandshakes.single.handshake,
    );
    expect(handshake.isProposal, isTrue);
    expect(handshake.proposalGroupIdHex, groupId);
    expect(handshake.proposalAdminMemberIdHex, row.myMemberId);
  });

  test('a received proposal becomes a pending invite; accepting it answers '
      'with a JoinAccept and stores the group waiting for keys', () async {
    client.stateController.add(
      const GroupHandshakeEvent(
        channelId: 'chan-1',
        isProposal: true,
        groupIdHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        groupName: 'Runde',
        adminMemberIdHex:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    );
    await pumpEventQueue();

    final invite = await groups.getInvite('a' * 64);
    expect(invite, isNotNull);
    expect(invite!.groupName, 'Runde');
    expect(invite.adminMemberId, 'b' * 64);

    await service.acceptInvite('a' * 64);

    // Group stored (epoch 0 = waiting) with the pinned admin.
    final row = await groups.getGroup('a' * 64);
    expect(row, isNotNull);
    expect(row!.isAdmin, isFalse);
    expect(row.keyEpoch, 0);
    final members = await groups.getMembers('a' * 64);
    expect(members, hasLength(2));
    expect(members.map((m) => m.memberId), contains('b' * 64));

    // JoinAccept went back over the invite channel with our fresh identity.
    expect(client.sentHandshakes, hasLength(1));
    final accept = GroupHandshake.decode(
      client.sentHandshakes.single.handshake,
    );
    expect(accept.isProposal, isFalse);
    expect(accept.acceptGroupIdHex, 'a' * 64);
    expect(accept.acceptMemberIdHex, row.myMemberId);
    expect(accept.acceptOhEndpoint, 'localhost:59558');

    // Invite consumed.
    expect(await groups.getInvite('a' * 64), isNull);
  });

  test(
    'a JoinAccept on the admin device rotates with the grown member list',
    () async {
      final channel = await insertCounterpartChannel('Carol');
      final groupId = await service.createGroup('Runde', const []);
      client.rotations.clear();

      client.stateController.add(
        GroupHandshakeEvent(
          channelId: channel.id,
          isProposal: false,
          groupIdHex: groupId,
          memberIdHex: 'c' * 64,
          x25519PubHex: 'd' * 64,
          ohId: List.filled(20, 9),
          ohEndpoint: 'localhost:59560',
        ),
      );
      await pumpEventQueue();

      expect(client.rotations, hasLength(1));
      final rotation = client.rotations.single;
      expect(rotation.groupId, groupId);
      expect(rotation.members, hasLength(2));
      final newcomer = rotation.members
          .where((m) => m.memberIdHex == 'c' * 64)
          .single;
      expect(newcomer.role, GroupMemberInfo.roleMember);
      expect(newcomer.displayName, 'Carol');
      expect(newcomer.ohEndpoint, 'localhost:59560');

      // Simulate the state persistence that follows a rotation in production
      // (GroupStateUpdate → applyStateUpdate), then verify a duplicate accept
      // does not rotate again.
      await groups.applyStateUpdate(
        GroupStateUpdate(
          groupId: groupId,
          label: 'Runde',
          keyEpoch: 2,
          members: rotation.members,
          cryptoStateJson: '{"v":1}',
          pendingItems: const [],
          pendingRotations: const {},
        ),
      );
      client.stateController.add(
        GroupHandshakeEvent(
          channelId: channel.id,
          isProposal: false,
          groupIdHex: groupId,
          memberIdHex: 'c' * 64,
          x25519PubHex: 'd' * 64,
          ohId: List.filled(20, 9),
          ohEndpoint: 'localhost:59560',
        ),
      );
      await pumpEventQueue();
      expect(client.rotations, hasLength(1));
    },
  );

  test('group state updates from the client are persisted wholesale', () async {
    final groupId = await service.createGroup('Runde', const []);

    // GroupStateUpdates are consumed by the MessageSyncService.
    final messages = MessageRepository(db);
    final sync = MessageSyncService(
      client,
      messages,
      OutboundHandleRepository(db),
      db,
      groups,
      OutboxService(messages, client, groups),
    );
    sync.start();
    client.stateController.add(
      GroupStateUpdate(
        groupId: groupId,
        label: 'Neuer Name',
        keyEpoch: 3,
        members: const [],
        cryptoStateJson: '{"v":1}',
        pendingItems: const [],
        pendingRotations: const {},
      ),
    );
    await pumpEventQueue();

    final row = await groups.getGroup(groupId);
    expect(row!.label, 'Neuer Name');
    expect(row.keyEpoch, 3);
    expect(row.cryptoState, '{"v":1}');

    // Restore rebuilds the registration from the persisted rows.
    final registration = await groups.toRegistration(row);
    expect(registration.keyEpoch, 3);
    expect(registration.cryptoStateJson, '{"v":1}');
    await sync.stop();
  });
}
