import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Data access for MS08 groups: the group rows, member lists, buffered
/// unknown-epoch items, pending invites and per-member delivery receipts.
class GroupRepository {
  final AppDatabase _db;

  GroupRepository(this._db);

  /// The underlying database, for callers that need adjacent tables
  /// (e.g. resolving a 1:1 channel label for a joining member).
  AppDatabase get database => _db;

  Stream<List<GroupChannelRow>> watchGroups() {
    return _db.select(_db.groupChannels).watch();
  }

  Future<GroupChannelRow?> getGroup(String groupId) {
    return (_db.select(
      _db.groupChannels,
    )..where((t) => t.groupId.equals(groupId))).getSingleOrNull();
  }

  Future<List<GroupChannelRow>> getAllGroups() {
    return _db.select(_db.groupChannels).get();
  }

  Future<bool> isGroup(String conversationId) async {
    return await getGroup(conversationId) != null;
  }

  Future<List<GroupMemberRow>> getMembers(String groupId) {
    return (_db.select(
      _db.groupMembers,
    )..where((t) => t.groupId.equals(groupId))).get();
  }

  Stream<List<GroupMemberRow>> watchMembers(String groupId) {
    return (_db.select(
      _db.groupMembers,
    )..where((t) => t.groupId.equals(groupId))).watch();
  }

  /// Creates the local group row plus its initial member list.
  Future<void> insertGroup({
    required String groupId,
    required String label,
    required bool isAdmin,
    required String myMemberId,
    required String mySignSeed,
    required String myX25519Priv,
    required int keyEpoch,
    required List<GroupMemberInfo> members,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.groupChannels)
          .insert(
            GroupChannelsCompanion.insert(
              groupId: groupId,
              label: label,
              isAdmin: drift.Value(isAdmin),
              myMemberId: myMemberId,
              mySignSeed: mySignSeed,
              myX25519Priv: myX25519Priv,
              keyEpoch: drift.Value(keyEpoch),
              createdAt: drift.Value(DateTime.now()),
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
      await _replaceMembers(groupId, members);
    });
  }

  /// Applies a [GroupStateUpdate] snapshot from the network isolate:
  /// label, epoch, crypto state, pending rotations, member list and the
  /// unknown-epoch item buffer are replaced wholesale.
  Future<void> applyStateUpdate(GroupStateUpdate update) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.groupChannels,
      )..where((t) => t.groupId.equals(update.groupId))).write(
        GroupChannelsCompanion(
          label: drift.Value(update.label),
          keyEpoch: drift.Value(update.keyEpoch),
          cryptoState: drift.Value(update.cryptoStateJson),
          pendingRotations: drift.Value(
            update.pendingRotations.isEmpty
                ? null
                : jsonEncode({
                    for (final entry in update.pendingRotations.entries)
                      entry.key: HEX.encode(entry.value),
                  }),
          ),
        ),
      );
      await _replaceMembers(update.groupId, update.members);
      await (_db.delete(
        _db.groupPendingItems,
      )..where((t) => t.groupId.equals(update.groupId))).go();
      for (final item in update.pendingItems) {
        await _db
            .into(_db.groupPendingItems)
            .insert(
              GroupPendingItemsCompanion.insert(
                groupId: update.groupId,
                payload: Uint8List.fromList(item),
                receivedAt: DateTime.now(),
              ),
            );
      }
    });
  }

  Future<void> _replaceMembers(
    String groupId,
    List<GroupMemberInfo> members,
  ) async {
    await (_db.delete(
      _db.groupMembers,
    )..where((t) => t.groupId.equals(groupId))).go();
    for (final member in members) {
      await _db
          .into(_db.groupMembers)
          .insert(
            GroupMembersCompanion.insert(
              groupId: groupId,
              memberId: member.memberIdHex,
              displayName: member.displayName,
              ohId: drift.Value(
                member.ohId != null ? HEX.encode(member.ohId!) : null,
              ),
              ohEndpoint: drift.Value(member.ohEndpoint),
              x25519Pub: member.x25519PubHex,
              role: member.role,
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
    }
  }

  /// Rebuilds the [GroupRegistration] for restoring a persisted group into
  /// the network client after an app restart.
  Future<GroupRegistration> toRegistration(GroupChannelRow row) async {
    final members = await getMembers(row.groupId);
    final pendingItems = await (_db.select(
      _db.groupPendingItems,
    )..where((t) => t.groupId.equals(row.groupId))).get();

    Map<String, List<int>> pendingRotations = const {};
    final rotationsJson = row.pendingRotations;
    if (rotationsJson != null && rotationsJson.isNotEmpty) {
      final decoded = jsonDecode(rotationsJson) as Map<String, dynamic>;
      pendingRotations = {
        for (final entry in decoded.entries)
          entry.key: HEX.decode(entry.value as String),
      };
    }

    return GroupRegistration(
      groupId: row.groupId,
      label: row.label,
      isAdmin: row.isAdmin,
      myMemberIdHex: row.myMemberId,
      mySignSeed: HEX.decode(row.mySignSeed),
      myX25519Priv: HEX.decode(row.myX25519Priv),
      keyEpoch: row.keyEpoch,
      members: [for (final member in members) memberToInfo(member)],
      cryptoStateJson: row.cryptoState,
      pendingItems: [for (final item in pendingItems) item.payload.toList()],
      pendingRotations: pendingRotations,
    );
  }

  static GroupMemberInfo memberToInfo(GroupMemberRow row) {
    return GroupMemberInfo(
      memberIdHex: row.memberId,
      displayName: row.displayName,
      ohId: row.ohId != null ? HEX.decode(row.ohId!) : null,
      ohEndpoint: row.ohEndpoint,
      x25519PubHex: row.x25519Pub,
      role: row.role,
    );
  }

  Future<void> deleteGroup(String groupId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.groupMembers,
      )..where((t) => t.groupId.equals(groupId))).go();
      await (_db.delete(
        _db.groupPendingItems,
      )..where((t) => t.groupId.equals(groupId))).go();
      await (_db.delete(
        _db.messageReceipts,
      )..where((t) => t.conversationId.equals(groupId))).go();
      await (_db.delete(
        _db.groupChannels,
      )..where((t) => t.groupId.equals(groupId))).go();
    });
  }

  // -----------------------------------------------------------------------
  // Invites (Decision 8)
  // -----------------------------------------------------------------------

  Future<void> insertInvite({
    required String groupId,
    required String groupName,
    required String adminMemberId,
    required String channelId,
  }) async {
    await _db
        .into(_db.groupInvites)
        .insert(
          GroupInvitesCompanion.insert(
            groupId: groupId,
            groupName: groupName,
            adminMemberId: adminMemberId,
            channelId: channelId,
            receivedAt: DateTime.now(),
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
  }

  Stream<List<GroupInviteRow>> watchInvites() {
    return _db.select(_db.groupInvites).watch();
  }

  Future<GroupInviteRow?> getInvite(String groupId) {
    return (_db.select(
      _db.groupInvites,
    )..where((t) => t.groupId.equals(groupId))).getSingleOrNull();
  }

  Future<void> deleteInvite(String groupId) async {
    await (_db.delete(
      _db.groupInvites,
    )..where((t) => t.groupId.equals(groupId))).go();
  }

  // -----------------------------------------------------------------------
  // Per-member delivery receipts (Decision 13)
  // -----------------------------------------------------------------------

  Future<void> markReceipt({
    required String conversationId,
    required String messageId,
    required String memberId,
    bool routed = false,
    bool delivered = false,
  }) async {
    final existing =
        await (_db.select(_db.messageReceipts)..where(
              (t) =>
                  t.conversationId.equals(conversationId) &
                  t.messageId.equals(messageId) &
                  t.memberId.equals(memberId),
            ))
            .getSingleOrNull();
    await _db
        .into(_db.messageReceipts)
        .insert(
          MessageReceiptsCompanion.insert(
            conversationId: conversationId,
            messageId: messageId,
            memberId: memberId,
            routed: drift.Value(routed || (existing?.routed ?? false)),
            delivered: drift.Value(delivered || (existing?.delivered ?? false)),
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
  }

  /// True when every current member except [ownMemberId] has the given
  /// receipt flag for the message (Decision 13: routed/delivered only when
  /// ALL members confirmed).
  Future<bool> allMembersConfirmed({
    required String conversationId,
    required String messageId,
    required String ownMemberId,
    required bool delivered,
  }) async {
    final members = await getMembers(conversationId);
    final receipts =
        await (_db.select(_db.messageReceipts)..where(
              (t) =>
                  t.conversationId.equals(conversationId) &
                  t.messageId.equals(messageId),
            ))
            .get();
    final confirmed = {
      for (final receipt in receipts)
        if (delivered ? receipt.delivered : receipt.routed) receipt.memberId,
    };
    for (final member in members) {
      if (member.memberId == ownMemberId) continue;
      if (!confirmed.contains(member.memberId)) return false;
    }
    return members.length > 1;
  }
}

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(dbProvider));
});

/// All groups this device is a member of, as a live stream.
final groupsProvider = StreamProvider<List<GroupChannelRow>>((ref) {
  return ref.watch(groupRepositoryProvider).watchGroups();
});

/// Pending group invites, as a live stream.
final groupInvitesProvider = StreamProvider<List<GroupInviteRow>>((ref) {
  return ref.watch(groupRepositoryProvider).watchInvites();
});

/// Member list of one group, as a live stream.
final groupMembersProvider =
    StreamProvider.family<List<GroupMemberRow>, String>((ref, groupId) {
      return ref.watch(groupRepositoryProvider).watchMembers(groupId);
    });
