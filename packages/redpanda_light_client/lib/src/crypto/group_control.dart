import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:protobuf/protobuf.dart' as pb_runtime;

import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/generated/client/group_control.pb.dart'
    as client_pb;

/// Codecs for the MS08 group control plane. These messages never touch the
/// backend (client-to-client only); the schema is
/// `protos/client/group_control.proto` (TD098/T142) and the classes below are
/// hex/nullable views over the generated `client_pb` messages.
///
/// Wire compatibility with deployed clients: the encoders set only
/// non-default fields, because the protobuf-dart runtime writes an explicitly
/// set default (`display_name = ''` → `12 00`) while the hand-written encoder
/// this replaced did not. `test/unit/client_protos_roundtrip_test.dart` pins
/// the bytes.
///
/// Decoding leniency against that hand-written decoder (same reasoning as
/// `RoutingAck.decode`): a known field with the wrong wire type is skipped
/// like an unknown field, and `uint32` fields (`key_epoch`, `role`) keep only
/// their low 32 bits. Every structural check (lengths, presence, epoch >= 1)
/// is still enforced below.
class GroupControl {
  /// Set for a key rotation (sealed control, envelope v6).
  final KeyRotation? keyRotation;

  /// Set for a rename (broadcast as a regular group message, envelope v5).
  final GroupInfoUpdate? infoUpdate;

  const GroupControl.rotation(KeyRotation this.keyRotation) : infoUpdate = null;
  const GroupControl.info(GroupInfoUpdate this.infoUpdate) : keyRotation = null;

  Uint8List encode() {
    final pb = client_pb.GroupControl();
    final rotation = keyRotation;
    if (rotation != null) pb.keyRotation = rotation._toProto();
    final info = infoUpdate;
    // An empty rename encodes to an empty GroupInfoUpdate, which the original
    // encoder dropped entirely (leaving no action set, so receivers reject
    // it). Setting the oneof would put `12 00` on the wire instead.
    if (info != null && info.name.isNotEmpty) pb.infoUpdate = info._toProto();
    return pb.writeToBuffer();
  }

  factory GroupControl.decode(List<int> bytes) {
    final pb = _parse(bytes, client_pb.GroupControl.fromBuffer, 'GroupControl');
    switch (pb.whichAction()) {
      case client_pb.GroupControl_Action.keyRotation:
        return GroupControl.rotation(KeyRotation._fromProto(pb.keyRotation));
      case client_pb.GroupControl_Action.infoUpdate:
        return GroupControl.info(GroupInfoUpdate(name: pb.infoUpdate.name));
      case client_pb.GroupControl_Action.notSet:
        throw const FormatException('GroupControl: no action set');
    }
  }
}

/// Distributes a new epoch secret plus the authoritative member list
/// (master spec MS08, Decisions 3/6/12). Travels only inside a sealed v6
/// envelope.
class KeyRotation {
  final Uint8List groupSecret;
  final int keyEpoch;
  final List<GroupMemberInfo> members;
  final String groupName;

  const KeyRotation({
    required this.groupSecret,
    required this.keyEpoch,
    required this.members,
    required this.groupName,
  });

  /// Encodes the bare rotation (without the GroupControl wrapper).
  Uint8List encode() => _toProto().writeToBuffer();

  client_pb.KeyRotation _toProto() {
    final pb = client_pb.KeyRotation(members: members.map(_memberToProto));
    if (groupSecret.isNotEmpty) pb.groupSecret = groupSecret;
    if (keyEpoch != 0) pb.keyEpoch = keyEpoch;
    if (groupName.isNotEmpty) pb.groupName = groupName;
    return pb;
  }

  factory KeyRotation.decode(List<int> bytes) => KeyRotation._fromProto(
    _parse(bytes, client_pb.KeyRotation.fromBuffer, 'KeyRotation'),
  );

  factory KeyRotation._fromProto(client_pb.KeyRotation pb) {
    if (pb.groupSecret.length != 32) {
      throw const FormatException('KeyRotation: missing or malformed secret');
    }
    if (pb.keyEpoch < 1) {
      throw const FormatException('KeyRotation: epoch must be >= 1');
    }
    return KeyRotation(
      groupSecret: Uint8List.fromList(pb.groupSecret),
      keyEpoch: pb.keyEpoch,
      members: [for (final m in pb.members) _memberFromProto(m)],
      groupName: pb.groupName,
    );
  }

  static client_pb.GroupMember _memberToProto(GroupMemberInfo member) {
    final pb = client_pb.GroupMember();
    final memberId = HEX.decode(member.memberIdHex);
    if (memberId.isNotEmpty) pb.memberId = memberId;
    if (member.displayName.isNotEmpty) pb.displayName = member.displayName;
    final ohId = member.ohId;
    if (ohId != null && ohId.isNotEmpty) pb.ohId = ohId;
    final endpoint = member.ohEndpoint;
    if (endpoint != null && endpoint.isNotEmpty) pb.ohEndpoint = endpoint;
    final x25519Pub = HEX.decode(member.x25519PubHex);
    if (x25519Pub.isNotEmpty) pb.x25519Pub = x25519Pub;
    // proto3: an omitted varint is 0 — and 0 is roleAdmin (master spec MS08
    // protobuf sketch), so exactly the admin's role byte is omitted.
    if (member.role != 0) pb.role = member.role;
    return pb;
  }

  static GroupMemberInfo _memberFromProto(client_pb.GroupMember pb) {
    if (pb.memberId.length != 32) {
      throw const FormatException('GroupMember: malformed member_id');
    }
    if (pb.x25519Pub.length != 32) {
      throw const FormatException('GroupMember: malformed x25519_pub');
    }
    if (pb.hasOhId() && pb.ohId.length != 20) {
      throw const FormatException('GroupMember: malformed oh_id');
    }
    return GroupMemberInfo(
      memberIdHex: HEX.encode(pb.memberId),
      displayName: pb.displayName,
      ohId: pb.hasOhId() ? List<int>.of(pb.ohId) : null,
      ohEndpoint: pb.hasOhEndpoint() ? pb.ohEndpoint : null,
      x25519PubHex: HEX.encode(pb.x25519Pub),
      role: pb.role,
    );
  }
}

/// Rename broadcast (admin only); travels as a regular group message.
class GroupInfoUpdate {
  final String name;

  const GroupInfoUpdate({required this.name});

  Uint8List encode() => _toProto().writeToBuffer();

  client_pb.GroupInfoUpdate _toProto() {
    final pb = client_pb.GroupInfoUpdate();
    if (name.isNotEmpty) pb.name = name;
    return pb;
  }

  factory GroupInfoUpdate.decode(List<int> bytes) => GroupInfoUpdate(
    name: _parse(
      bytes,
      client_pb.GroupInfoUpdate.fromBuffer,
      'GroupInfoUpdate',
    ).name,
  );
}

/// The two-way join handshake over an existing 1:1 channel (Decision 8),
/// carried in `ChannelMessage.group_handshake` (field 7).
class GroupHandshake {
  /// Proposal: admin → invitee (group id + name + pinned admin identity).
  final String? proposalGroupIdHex;
  final String? proposalGroupName;
  final String? proposalAdminMemberIdHex;

  /// Accept: invitee → admin (freshly generated member identity + group OH).
  final String? acceptGroupIdHex;
  final String? acceptMemberIdHex;
  final String? acceptX25519PubHex;
  final List<int>? acceptOhId;
  final String? acceptOhEndpoint;

  const GroupHandshake.proposal({
    required String groupIdHex,
    required String groupName,
    required String adminMemberIdHex,
  }) : proposalGroupIdHex = groupIdHex,
       proposalGroupName = groupName,
       proposalAdminMemberIdHex = adminMemberIdHex,
       acceptGroupIdHex = null,
       acceptMemberIdHex = null,
       acceptX25519PubHex = null,
       acceptOhId = null,
       acceptOhEndpoint = null;

  const GroupHandshake.accept({
    required String groupIdHex,
    required String memberIdHex,
    required String x25519PubHex,
    required List<int> ohId,
    required String ohEndpoint,
  }) : proposalGroupIdHex = null,
       proposalGroupName = null,
       proposalAdminMemberIdHex = null,
       acceptGroupIdHex = groupIdHex,
       acceptMemberIdHex = memberIdHex,
       acceptX25519PubHex = x25519PubHex,
       acceptOhId = ohId,
       acceptOhEndpoint = ohEndpoint;

  bool get isProposal => proposalGroupIdHex != null;

  Uint8List encode() {
    final pb = client_pb.GroupHandshake();
    if (isProposal) {
      final groupId = HEX.decode(proposalGroupIdHex!);
      final name = proposalGroupName ?? '';
      final adminMemberId = HEX.decode(proposalAdminMemberIdHex!);
      final proposal = client_pb.InviteProposal();
      if (groupId.isNotEmpty) proposal.groupId = groupId;
      if (name.isNotEmpty) proposal.groupName = name;
      if (adminMemberId.isNotEmpty) proposal.adminMemberId = adminMemberId;
      pb.proposal = proposal;
    } else {
      final groupId = HEX.decode(acceptGroupIdHex!);
      final memberId = HEX.decode(acceptMemberIdHex!);
      final x25519Pub = HEX.decode(acceptX25519PubHex!);
      final ohId = acceptOhId!;
      final endpoint = acceptOhEndpoint!;
      final accept = client_pb.JoinAccept();
      if (groupId.isNotEmpty) accept.groupId = groupId;
      if (memberId.isNotEmpty) accept.memberId = memberId;
      if (x25519Pub.isNotEmpty) accept.x25519Pub = x25519Pub;
      if (ohId.isNotEmpty) accept.ohId = ohId;
      if (endpoint.isNotEmpty) accept.ohEndpoint = endpoint;
      pb.accept = accept;
    }
    return pb.writeToBuffer();
  }

  factory GroupHandshake.decode(List<int> bytes) {
    final pb = _parse(
      bytes,
      client_pb.GroupHandshake.fromBuffer,
      'GroupHandshake',
    );
    switch (pb.whichKind()) {
      case client_pb.GroupHandshake_Kind.proposal:
        final proposal = pb.proposal;
        if (proposal.groupId.length != 32) {
          throw const FormatException('GroupHandshake: malformed group_id');
        }
        if (proposal.adminMemberId.length != 32) {
          throw const FormatException(
            'GroupHandshake: malformed admin_member_id',
          );
        }
        return GroupHandshake.proposal(
          groupIdHex: HEX.encode(proposal.groupId),
          groupName: proposal.groupName,
          adminMemberIdHex: HEX.encode(proposal.adminMemberId),
        );
      case client_pb.GroupHandshake_Kind.accept:
        final accept = pb.accept;
        if (accept.groupId.length != 32) {
          throw const FormatException('GroupHandshake: malformed group_id');
        }
        if (accept.memberId.length != 32) {
          throw const FormatException('GroupHandshake: malformed member_id');
        }
        if (accept.x25519Pub.length != 32) {
          throw const FormatException('GroupHandshake: malformed x25519_pub');
        }
        if (accept.ohId.length != 20) {
          throw const FormatException('GroupHandshake: malformed oh_id');
        }
        return GroupHandshake.accept(
          groupIdHex: HEX.encode(accept.groupId),
          memberIdHex: HEX.encode(accept.memberId),
          x25519PubHex: HEX.encode(accept.x25519Pub),
          ohId: List<int>.of(accept.ohId),
          ohEndpoint: accept.ohEndpoint,
        );
      case client_pb.GroupHandshake_Kind.notSet:
        throw const FormatException('GroupHandshake: no kind set');
    }
  }
}

/// Parses [bytes] with [fromBuffer], mapping protobuf errors to
/// [FormatException] as the callers expect.
T _parse<T>(List<int> bytes, T Function(List<int>) fromBuffer, String what) {
  try {
    return fromBuffer(bytes);
  } on pb_runtime.InvalidProtocolBufferException catch (e) {
    throw FormatException('$what: ${e.message}');
  }
}
