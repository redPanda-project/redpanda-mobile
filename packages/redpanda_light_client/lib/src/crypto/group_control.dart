import 'dart:convert';
import 'dart:typed_data';

import 'package:hex/hex.dart';

import 'package:redpanda_light_client/src/domain/group_state.dart';

/// Hand-rolled proto3-compatible codecs for the MS08 group control plane —
/// same rationale as `ChannelMessage`: the committed generated protobuf
/// files are hand-post-processed and not regenerable here, and these
/// messages never touch the backend (client-to-client only), so plain
/// proto3 wire compatibility is all that is required.
///
/// ```
/// GroupMember {
///   bytes  member_id   = 1;  // 32 B Ed25519 verify key (= identity)
///   string display_name = 2;
///   bytes  oh_id        = 3;  // 20 B group-OH mailbox id
///   string oh_endpoint  = 4;  // host:port of the OH host
///   bytes  x25519_pub   = 5;  // 32 B, for sealed controls
///   uint32 role         = 6;  // 0 = admin, 1 = member
/// }
///
/// GroupControl {
///   oneof action {
///     KeyRotation     key_rotation = 1;  // travels sealed (envelope v6)
///     GroupInfoUpdate info_update  = 2;  // travels as group message (v5)
///   }
/// }
///
/// KeyRotation {
///   bytes  group_secret = 1;  // 32 B epoch secret (Decision 3)
///   uint32 key_epoch    = 2;
///   repeated GroupMember members = 3;  // full replacement list
///   string group_name   = 4;
/// }
///
/// GroupInfoUpdate { string name = 1; }
///
/// GroupHandshake {                      // 1:1 channel, Decision 8
///   oneof kind {
///     InviteProposal proposal = 1;
///     JoinAccept     accept   = 2;
///   }
/// }
/// InviteProposal {
///   bytes  group_id        = 1;
///   string group_name      = 2;
///   bytes  admin_member_id = 3;  // pinned by the invitee: rotations must be
///                                // signed by this Ed25519 key
/// }
/// JoinAccept {
///   bytes  group_id    = 1;
///   bytes  member_id   = 2;
///   bytes  x25519_pub  = 3;
///   bytes  oh_id       = 4;
///   string oh_endpoint = 5;
/// }
/// ```
class GroupControl {
  /// Set for a key rotation (sealed control, envelope v6).
  final KeyRotation? keyRotation;

  /// Set for a rename (broadcast as a regular group message, envelope v5).
  final GroupInfoUpdate? infoUpdate;

  const GroupControl.rotation(KeyRotation this.keyRotation) : infoUpdate = null;
  const GroupControl.info(GroupInfoUpdate this.infoUpdate) : keyRotation = null;

  Uint8List encode() {
    final out = BytesBuilder();
    final rotation = keyRotation;
    if (rotation != null) {
      _Proto.writeBytes(out, 1, rotation.encode());
    }
    final info = infoUpdate;
    if (info != null) {
      _Proto.writeBytes(out, 2, info.encode());
    }
    return out.toBytes();
  }

  factory GroupControl.decode(List<int> bytes) {
    KeyRotation? rotation;
    GroupInfoUpdate? info;
    _Proto.forEachField(bytes, (field, value) {
      switch (field) {
        case 1:
          rotation = KeyRotation.decode(value);
          break;
        case 2:
          info = GroupInfoUpdate.decode(value);
          break;
      }
    });
    if (rotation != null) return GroupControl.rotation(rotation!);
    if (info != null) return GroupControl.info(info!);
    throw const FormatException('GroupControl: no action set');
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

  Uint8List encode() {
    final out = BytesBuilder();
    _Proto.writeBytes(out, 1, groupSecret);
    _Proto.writeVarintField(out, 2, keyEpoch);
    for (final member in members) {
      _Proto.writeBytes(out, 3, _encodeMember(member));
    }
    _Proto.writeString(out, 4, groupName);
    return out.toBytes();
  }

  factory KeyRotation.decode(List<int> bytes) {
    Uint8List? secret;
    var epoch = 0;
    final members = <GroupMemberInfo>[];
    var name = '';
    _Proto.forEachField(
      bytes,
      (field, value) {
        switch (field) {
          case 1:
            secret = value;
            break;
          case 3:
            members.add(_decodeMember(value));
            break;
          case 4:
            name = utf8.decode(value);
            break;
        }
      },
      onVarint: (field, value) {
        if (field == 2) epoch = value;
      },
    );
    if (secret == null || secret!.length != 32) {
      throw const FormatException('KeyRotation: missing or malformed secret');
    }
    if (epoch < 1) {
      throw const FormatException('KeyRotation: epoch must be >= 1');
    }
    return KeyRotation(
      groupSecret: secret!,
      keyEpoch: epoch,
      members: members,
      groupName: name,
    );
  }

  static Uint8List _encodeMember(GroupMemberInfo member) {
    final out = BytesBuilder();
    _Proto.writeBytes(
      out,
      1,
      Uint8List.fromList(HEX.decode(member.memberIdHex)),
    );
    _Proto.writeString(out, 2, member.displayName);
    final ohId = member.ohId;
    if (ohId != null) {
      _Proto.writeBytes(out, 3, Uint8List.fromList(ohId));
    }
    final endpoint = member.ohEndpoint;
    if (endpoint != null) {
      _Proto.writeString(out, 4, endpoint);
    }
    _Proto.writeBytes(
      out,
      5,
      Uint8List.fromList(HEX.decode(member.x25519PubHex)),
    );
    _Proto.writeVarintField(out, 6, member.role);
    return out.toBytes();
  }

  static GroupMemberInfo _decodeMember(List<int> bytes) {
    Uint8List? memberId;
    var displayName = '';
    Uint8List? ohId;
    String? endpoint;
    Uint8List? x25519Pub;
    // proto3: an omitted varint is 0 — and 0 is roleAdmin (master spec MS08
    // protobuf sketch). Our encoder omits exactly the admin's role byte.
    var role = GroupMemberInfo.roleAdmin;
    _Proto.forEachField(
      bytes,
      (field, value) {
        switch (field) {
          case 1:
            memberId = value;
            break;
          case 2:
            displayName = utf8.decode(value);
            break;
          case 3:
            ohId = value;
            break;
          case 4:
            endpoint = utf8.decode(value);
            break;
          case 5:
            x25519Pub = value;
            break;
        }
      },
      onVarint: (field, value) {
        if (field == 6) role = value;
      },
    );
    if (memberId == null || memberId!.length != 32) {
      throw const FormatException('GroupMember: malformed member_id');
    }
    if (x25519Pub == null || x25519Pub!.length != 32) {
      throw const FormatException('GroupMember: malformed x25519_pub');
    }
    if (ohId != null && ohId!.length != 20) {
      throw const FormatException('GroupMember: malformed oh_id');
    }
    return GroupMemberInfo(
      memberIdHex: HEX.encode(memberId!),
      displayName: displayName,
      ohId: ohId?.toList(),
      ohEndpoint: endpoint,
      x25519PubHex: HEX.encode(x25519Pub!),
      role: role,
    );
  }
}

/// Rename broadcast (admin only); travels as a regular group message.
class GroupInfoUpdate {
  final String name;

  const GroupInfoUpdate({required this.name});

  Uint8List encode() {
    final out = BytesBuilder();
    _Proto.writeString(out, 1, name);
    return out.toBytes();
  }

  factory GroupInfoUpdate.decode(List<int> bytes) {
    var name = '';
    _Proto.forEachField(bytes, (field, value) {
      if (field == 1) name = utf8.decode(value);
    });
    return GroupInfoUpdate(name: name);
  }
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
    final out = BytesBuilder();
    if (isProposal) {
      final proposal = BytesBuilder();
      _Proto.writeBytes(
        proposal,
        1,
        Uint8List.fromList(HEX.decode(proposalGroupIdHex!)),
      );
      _Proto.writeString(proposal, 2, proposalGroupName ?? '');
      _Proto.writeBytes(
        proposal,
        3,
        Uint8List.fromList(HEX.decode(proposalAdminMemberIdHex!)),
      );
      _Proto.writeBytes(out, 1, proposal.toBytes());
    } else {
      final accept = BytesBuilder();
      _Proto.writeBytes(
        accept,
        1,
        Uint8List.fromList(HEX.decode(acceptGroupIdHex!)),
      );
      _Proto.writeBytes(
        accept,
        2,
        Uint8List.fromList(HEX.decode(acceptMemberIdHex!)),
      );
      _Proto.writeBytes(
        accept,
        3,
        Uint8List.fromList(HEX.decode(acceptX25519PubHex!)),
      );
      _Proto.writeBytes(accept, 4, Uint8List.fromList(acceptOhId!));
      _Proto.writeString(accept, 5, acceptOhEndpoint!);
      _Proto.writeBytes(out, 2, accept.toBytes());
    }
    return out.toBytes();
  }

  factory GroupHandshake.decode(List<int> bytes) {
    Uint8List? proposalBytes;
    Uint8List? acceptBytes;
    _Proto.forEachField(bytes, (field, value) {
      switch (field) {
        case 1:
          proposalBytes = value;
          break;
        case 2:
          acceptBytes = value;
          break;
      }
    });

    if (proposalBytes != null) {
      Uint8List? groupId;
      var name = '';
      Uint8List? adminMemberId;
      _Proto.forEachField(proposalBytes!, (field, value) {
        if (field == 1) groupId = value;
        if (field == 2) name = utf8.decode(value);
        if (field == 3) adminMemberId = value;
      });
      if (groupId == null || groupId!.length != 32) {
        throw const FormatException('GroupHandshake: malformed group_id');
      }
      if (adminMemberId == null || adminMemberId!.length != 32) {
        throw const FormatException(
          'GroupHandshake: malformed admin_member_id',
        );
      }
      return GroupHandshake.proposal(
        groupIdHex: HEX.encode(groupId!),
        groupName: name,
        adminMemberIdHex: HEX.encode(adminMemberId!),
      );
    }

    if (acceptBytes != null) {
      Uint8List? groupId;
      Uint8List? memberId;
      Uint8List? x25519Pub;
      Uint8List? ohId;
      var endpoint = '';
      _Proto.forEachField(acceptBytes!, (field, value) {
        switch (field) {
          case 1:
            groupId = value;
            break;
          case 2:
            memberId = value;
            break;
          case 3:
            x25519Pub = value;
            break;
          case 4:
            ohId = value;
            break;
          case 5:
            endpoint = utf8.decode(value);
            break;
        }
      });
      if (groupId == null || groupId!.length != 32) {
        throw const FormatException('GroupHandshake: malformed group_id');
      }
      if (memberId == null || memberId!.length != 32) {
        throw const FormatException('GroupHandshake: malformed member_id');
      }
      if (x25519Pub == null || x25519Pub!.length != 32) {
        throw const FormatException('GroupHandshake: malformed x25519_pub');
      }
      if (ohId == null || ohId!.length != 20) {
        throw const FormatException('GroupHandshake: malformed oh_id');
      }
      return GroupHandshake.accept(
        groupIdHex: HEX.encode(groupId!),
        memberIdHex: HEX.encode(memberId!),
        x25519PubHex: HEX.encode(x25519Pub!),
        ohId: ohId!.toList(),
        ohEndpoint: endpoint,
      );
    }

    throw const FormatException('GroupHandshake: no kind set');
  }
}

/// Minimal proto3 wire helpers shared by the codecs above. Length-delimited
/// fields are dispatched through [forEachField]; varint fields through its
/// optional `onVarint` callback. Unknown fields are skipped.
class _Proto {
  _Proto._();

  static void writeVarint(BytesBuilder out, int value) {
    var v = value;
    while (true) {
      final byte = v & 0x7F;
      v = v >>> 7;
      if (v == 0) {
        out.addByte(byte);
        break;
      }
      out.addByte(byte | 0x80);
    }
  }

  static void writeVarintField(BytesBuilder out, int field, int value) {
    if (value == 0) return;
    writeVarint(out, (field << 3) | 0);
    writeVarint(out, value);
  }

  static void writeBytes(BytesBuilder out, int field, Uint8List value) {
    if (value.isEmpty) return;
    writeVarint(out, (field << 3) | 2);
    writeVarint(out, value.length);
    out.add(value);
  }

  static void writeString(BytesBuilder out, int field, String value) {
    writeBytes(out, field, Uint8List.fromList(utf8.encode(value)));
  }

  static void forEachField(
    List<int> bytes,
    void Function(int field, Uint8List value) onBytes, {
    void Function(int field, int value)? onVarint,
  }) {
    final data = Uint8List.fromList(bytes);
    var offset = 0;

    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (offset >= data.length) {
          throw const FormatException('group proto: truncated varint');
        }
        final b = data[offset++];
        result |= (b & 0x7F) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
        if (shift > 63) {
          throw const FormatException('group proto: varint too long');
        }
      }
      return result;
    }

    while (offset < data.length) {
      final tag = readVarint();
      final field = tag >> 3;
      final wireType = tag & 0x7;
      switch (wireType) {
        case 0:
          final value = readVarint();
          onVarint?.call(field, value);
          break;
        case 2:
          final len = readVarint();
          if (offset + len > data.length) {
            throw const FormatException('group proto: truncated field');
          }
          onBytes(field, Uint8List.sublistView(data, offset, offset + len));
          offset += len;
          break;
        case 1:
          offset += 8;
          break;
        case 5:
          offset += 4;
          break;
        default:
          throw FormatException('group proto: unknown wire type $wireType');
      }
      if (offset > data.length) {
        throw const FormatException('group proto: truncated field');
      }
    }
  }
}
