import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Orchestrates MS08 group lifecycle on the app side: create, invite,
/// accept, membership changes and renames. Everything crypto- and
/// network-side lives in the light client; this service wires the
/// handshake events and persists the group rows.
///
/// Join flow (master spec MS08, Decision 8):
///
///   admin --InviteProposal (1:1)--> invitee      [proposal → invite row]
///   invitee: generate identity + group OH, store group (epoch 0)
///   invitee --JoinAccept (1:1)--> admin          [accept → member + rotate]
///   admin: rotateGroupKey(all members incl. newcomer)
///   invitee: sealed rotation arrives → epoch installed → group usable
class GroupService {
  final RedPandaClient _client;
  final GroupRepository _groups;
  final OutboundHandleRepository _outboundHandles;

  StreamSubscription<GroupHandshakeEvent>? _handshakeSub;

  GroupService(this._client, this._groups, this._outboundHandles);

  void start() {
    _handshakeSub ??= _client.groupHandshakeEvents.listen(
      (event) => unawaited(
        _handleHandshake(event).catchError(
          (Object e) =>
              debugPrint('GroupService: failed to handle handshake: $e'),
        ),
      ),
    );
  }

  Future<void> stop() async {
    await _handshakeSub?.cancel();
    _handshakeSub = null;
  }

  /// Creates a new group with this device as admin and sends an invite
  /// proposal over each of the given 1:1 channels. Returns the group id.
  Future<String> createGroup(String name, List<Channel> inviteChannels) async {
    if (inviteChannels.length + 1 > maxGroupMembers) {
      throw ArgumentError(
        'groups support at most $maxGroupMembers members (MS08, Decision 2)',
      );
    }

    final groupId = HEX.encode(CryptoUtils.randomBytes(32));
    final signKeys = await CryptoUtils.generateSigningKeypair();
    final x25519Keys = await CryptoUtils.generateEncryptionKeypair();
    final myMemberId = HEX.encode(signKeys.publicKey);

    // Own group OH — the mailbox other members deposit into (Decision 7).
    final ownDescriptor = await _outboundHandles.ensureOwnDescriptor(
      _client,
      groupId,
    );
    if (ownDescriptor == null) {
      throw StateError(
        'could not register a group mailbox (no connected node?)',
      );
    }

    final me = GroupMemberInfo(
      memberIdHex: myMemberId,
      displayName: 'Me',
      ohId: ownDescriptor.handleId,
      ohEndpoint: ownDescriptor.serverEndpoint,
      x25519PubHex: HEX.encode(x25519Keys.publicKey),
      role: GroupMemberInfo.roleAdmin,
    );

    await _groups.insertGroup(
      groupId: groupId,
      label: name,
      isAdmin: true,
      myMemberId: myMemberId,
      mySignSeed: HEX.encode(signKeys.privateSeed),
      myX25519Priv: HEX.encode(x25519Keys.privateKey),
      keyEpoch: 0,
      members: [me],
    );
    _client.registerGroup(
      GroupRegistration(
        groupId: groupId,
        label: name,
        isAdmin: true,
        myMemberIdHex: myMemberId,
        mySignSeed: signKeys.privateSeed,
        myX25519Priv: x25519Keys.privateKey,
        keyEpoch: 0,
        members: [me],
      ),
    );

    // Epoch 1 with only the admin — the group is immediately usable and
    // each accepted invite bumps the epoch with the grown member list.
    await _client.rotateGroupKey(groupId, members: [me], label: name);

    for (final channel in inviteChannels) {
      await sendInvite(groupId, channel.id);
    }
    return groupId;
  }

  /// Sends (or re-sends) an invite proposal for [groupId] over the 1:1
  /// channel [channelId].
  Future<void> sendInvite(String groupId, String channelId) async {
    final group = await _groups.getGroup(groupId);
    if (group == null || !group.isAdmin) {
      throw StateError('only the group admin can invite members');
    }
    final handshake = GroupHandshake.proposal(
      groupIdHex: groupId,
      groupName: group.label,
      adminMemberIdHex: group.myMemberId,
    );
    await _client.sendGroupHandshake(channelId, handshake.encode());
  }

  /// Accepts a pending invite: generates the own group identity, registers
  /// a group OH and answers with a JoinAccept over the invite's 1:1
  /// channel. The group becomes usable once the admin's rotation arrives.
  Future<void> acceptInvite(String groupId) async {
    final invite = await _groups.getInvite(groupId);
    if (invite == null) {
      throw StateError('no pending invite for group $groupId');
    }

    final signKeys = await CryptoUtils.generateSigningKeypair();
    final x25519Keys = await CryptoUtils.generateEncryptionKeypair();
    final myMemberId = HEX.encode(signKeys.publicKey);

    final ownDescriptor = await _outboundHandles.ensureOwnDescriptor(
      _client,
      groupId,
    );
    if (ownDescriptor == null) {
      throw StateError(
        'could not register a group mailbox (no connected node?)',
      );
    }

    // The pinned admin (Decision 9): rotations must carry its signature.
    // Its X25519 key and OH arrive with the first rotation's member list.
    final pinnedAdmin = GroupMemberInfo(
      memberIdHex: invite.adminMemberId,
      displayName: invite.groupName,
      x25519PubHex: '',
      role: GroupMemberInfo.roleAdmin,
    );
    final me = GroupMemberInfo(
      memberIdHex: myMemberId,
      displayName: 'Me',
      ohId: ownDescriptor.handleId,
      ohEndpoint: ownDescriptor.serverEndpoint,
      x25519PubHex: HEX.encode(x25519Keys.publicKey),
      role: GroupMemberInfo.roleMember,
    );

    await _groups.insertGroup(
      groupId: groupId,
      label: invite.groupName,
      isAdmin: false,
      myMemberId: myMemberId,
      mySignSeed: HEX.encode(signKeys.privateSeed),
      myX25519Priv: HEX.encode(x25519Keys.privateKey),
      keyEpoch: 0,
      members: [pinnedAdmin, me],
    );
    _client.registerGroup(
      GroupRegistration(
        groupId: groupId,
        label: invite.groupName,
        isAdmin: false,
        myMemberIdHex: myMemberId,
        mySignSeed: signKeys.privateSeed,
        myX25519Priv: x25519Keys.privateKey,
        keyEpoch: 0,
        members: [pinnedAdmin, me],
      ),
    );

    final accept = GroupHandshake.accept(
      groupIdHex: groupId,
      memberIdHex: myMemberId,
      x25519PubHex: HEX.encode(x25519Keys.publicKey),
      ohId: ownDescriptor.handleId,
      ohEndpoint: ownDescriptor.serverEndpoint,
    );
    await _client.sendGroupHandshake(invite.channelId, accept.encode());
    await _groups.deleteInvite(groupId);
  }

  Future<void> dismissInvite(String groupId) {
    return _groups.deleteInvite(groupId);
  }

  /// Removes [memberId] from the group and rotates the key so the removed
  /// member cannot read new messages (Decision 12).
  Future<void> removeMember(String groupId, String memberId) async {
    final group = await _groups.getGroup(groupId);
    if (group == null || !group.isAdmin) {
      throw StateError('only the group admin can remove members');
    }
    final members = await _groups.getMembers(groupId);
    final remaining = [
      for (final member in members)
        if (member.memberId != memberId) GroupRepository.memberToInfo(member),
    ];
    if (remaining.length == members.length) return; // not a member
    await _client.rotateGroupKey(groupId, members: remaining);
  }

  /// Renames the group (admin only) and broadcasts the change.
  Future<void> renameGroup(String groupId, String label) async {
    final group = await _groups.getGroup(groupId);
    if (group == null || !group.isAdmin) {
      throw StateError('only the group admin can rename the group');
    }
    await _client.sendGroupInfoUpdate(groupId, label);
  }

  /// Leaves the group locally (v1: no leave protocol — the admin removes
  /// unreachable members; our mailbox simply stops being fetched).
  Future<void> leaveGroup(String groupId) {
    return _groups.deleteGroup(groupId);
  }

  /// Restores persisted groups into the network client on startup and
  /// retries undelivered rotation boxes.
  Future<void> restorePersistedGroups() async {
    final groups = await _groups.getAllGroups();
    for (final row in groups) {
      final registration = await _groups.toRegistration(row);
      _client.registerGroup(registration);
      if (registration.pendingRotations.isNotEmpty) {
        unawaited(
          _client.retryPendingRotations(row.groupId).catchError((Object e) {
            debugPrint(
              'GroupService: rotation boxes for ${row.groupId} still '
              'pending: $e',
            );
          }),
        );
      }
    }
  }

  Future<void> _handleHandshake(GroupHandshakeEvent event) async {
    if (event.isProposal) {
      // Ignore proposals for groups we are already in (re-sent invites).
      if (await _groups.getGroup(event.groupIdHex) != null) return;
      await _groups.insertInvite(
        groupId: event.groupIdHex,
        groupName: event.groupName ?? 'Group',
        adminMemberId: event.adminMemberIdHex ?? '',
        channelId: event.channelId,
      );
      return;
    }

    // JoinAccept: only meaningful on the admin device of that group.
    final group = await _groups.getGroup(event.groupIdHex);
    if (group == null || !group.isAdmin) return;
    final memberId = event.memberIdHex;
    final x25519Pub = event.x25519PubHex;
    final ohId = event.ohId;
    if (memberId == null || x25519Pub == null || ohId == null) return;

    final members = await _groups.getMembers(event.groupIdHex);
    final infos = [
      for (final member in members) GroupRepository.memberToInfo(member),
    ];
    if (infos.any((m) => m.memberIdHex == memberId)) return; // duplicate
    if (infos.length + 1 > maxGroupMembers) {
      debugPrint(
        'GroupService: rejecting join for ${event.groupIdHex} — group full',
      );
      return;
    }

    // Display name: the label of the 1:1 channel the accept arrived on.
    final channelLabel = await _channelLabel(event.channelId);
    infos.add(
      GroupMemberInfo(
        memberIdHex: memberId,
        displayName: channelLabel ?? 'Member ${infos.length + 1}',
        ohId: ohId,
        ohEndpoint: event.ohEndpoint,
        x25519PubHex: x25519Pub,
        role: GroupMemberInfo.roleMember,
      ),
    );
    // The rotation distributes the full member list — including the
    // newcomer's "real" invite (Decision 8).
    await _client.rotateGroupKey(event.groupIdHex, members: infos);
  }

  Future<String?> _channelLabel(String channelId) async {
    final db = _groups.database;
    final row = await (db.select(
      db.channels,
    )..where((t) => t.uuid.equals(channelId))).getSingleOrNull();
    return row?.label;
  }
}

final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService(
    ref.watch(redPandaClientProvider),
    ref.watch(groupRepositoryProvider),
    ref.watch(outboundHandleRepositoryProvider),
  );
});
