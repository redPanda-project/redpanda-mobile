import 'package:equatable/equatable.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';

/// One member of a group (Frontend MS08).
///
/// The member id **is** the member's group-specific Ed25519 verify key
/// (master spec MS08, Decision 4) — sender authenticity checks need no
/// separate key lookup, and ids are unlinkable across groups. All fields are
/// isolate-sendable primitives.
class GroupMemberInfo extends Equatable {
  /// 32-byte Ed25519 verify key, lowercase hex (64 chars).
  final String memberIdHex;

  final String displayName;

  /// 20-byte OH mailbox id of the member's group OH; null until the member
  /// has announced it (a member without one cannot receive group messages).
  final List<int>? ohId;

  /// host:port of the node hosting the member's group OH.
  final String? ohEndpoint;

  /// 32-byte X25519 public key for sealed controls (hex, 64 chars).
  final String x25519PubHex;

  /// 0 = admin (the group creator), 1 = member (Decision 9: one admin).
  final int role;

  const GroupMemberInfo({
    required this.memberIdHex,
    required this.displayName,
    this.ohId,
    this.ohEndpoint,
    required this.x25519PubHex,
    required this.role,
  });

  static const int roleAdmin = 0;
  static const int roleMember = 1;

  @override
  List<Object?> get props => [
    memberIdHex,
    displayName,
    ohId,
    ohEndpoint,
    x25519PubHex,
    role,
  ];
}

/// Registers a group with the network client (Frontend MS08) — the group
/// counterpart of `addChannelKeys`. Carries only isolate-sendable
/// primitives; persisted state is restored through [cryptoStateJson],
/// [pendingItems] and [pendingRotations] (see [GroupStateUpdate]).
class GroupRegistration {
  /// 32-byte group id, lowercase hex — also the `channelId` of the group OH.
  final String groupId;

  final String label;

  /// True only on the creator device (Decision 9).
  final bool isAdmin;

  /// Own member id (= own Ed25519 verify key, hex).
  final String myMemberIdHex;

  /// Own 32-byte Ed25519 signing seed (group-specific, never leaves the
  /// device except inside this registration to the network isolate).
  final List<int> mySignSeed;

  /// Own 32-byte X25519 private key for unsealing controls.
  final List<int> myX25519Priv;

  /// Current key epoch; 0 while waiting for the first rotation (joiner).
  final int keyEpoch;

  /// Full member list including self.
  final List<GroupMemberInfo> members;

  /// Persisted [GroupCryptoSession] state, or null for a fresh group.
  final String? cryptoStateJson;

  /// Buffered items of a not-yet-installed epoch (Decision 10).
  final List<List<int>> pendingItems;

  /// Sealed rotation boxes not yet delivered, member id hex → payload
  /// (the epoch secret is deleted at install time, so unsent boxes must
  /// survive restarts to retry — Decision 10: rotations arrive reliably).
  final Map<String, List<int>> pendingRotations;

  const GroupRegistration({
    required this.groupId,
    required this.label,
    required this.isAdmin,
    required this.myMemberIdHex,
    required this.mySignSeed,
    required this.myX25519Priv,
    required this.keyEpoch,
    required this.members,
    this.cryptoStateJson,
    this.pendingItems = const [],
    this.pendingRotations = const {},
  });
}

/// A group state change emitted by the network client so the app layer can
/// persist it (Frontend MS08) — the group counterpart of
/// `RatchetStateUpdate`/`GarlicSessionUpdate`. Snapshots the full mutable
/// state: crypto chains, epoch, member list, buffered items and undelivered
/// rotation boxes.
class GroupStateUpdate extends StateUpdate {
  final String groupId;
  final String label;
  final int keyEpoch;
  final List<GroupMemberInfo> members;

  /// Serialized [GroupCryptoSession] (key material — on-device only).
  final String cryptoStateJson;

  /// Buffered items of a not-yet-installed epoch (Decision 10).
  final List<List<int>> pendingItems;

  /// Sealed rotation boxes not yet delivered, member id hex → payload.
  final Map<String, List<int>> pendingRotations;

  const GroupStateUpdate({
    required this.groupId,
    required this.label,
    required this.keyEpoch,
    required this.members,
    required this.cryptoStateJson,
    required this.pendingItems,
    required this.pendingRotations,
  });
}

/// A group handshake received over an existing 1:1 channel (Decision 8):
/// either an invite proposal (admin → invitee) or a join accept
/// (invitee → admin). Field semantics follow `GroupHandshakeCodec`.
class GroupHandshakeEvent extends StateUpdate {
  /// The 1:1 channel the handshake arrived on.
  final String channelId;

  /// True for an invite proposal, false for a join accept.
  final bool isProposal;

  final String groupIdHex;

  /// Group name (proposal only).
  final String? groupName;

  /// Admin member id to pin (proposal only): key rotations for this group
  /// must carry a signature by this Ed25519 key.
  final String? adminMemberIdHex;

  /// Invitee's member id / X25519 key / group OH (accept only).
  final String? memberIdHex;
  final String? x25519PubHex;
  final List<int>? ohId;
  final String? ohEndpoint;

  const GroupHandshakeEvent({
    required this.channelId,
    required this.isProposal,
    required this.groupIdHex,
    this.groupName,
    this.adminMemberIdHex,
    this.memberIdHex,
    this.x25519PubHex,
    this.ohId,
    this.ohEndpoint,
  });
}

/// Hard cap on the group size in v1 (master spec MS08, Decision 2).
const int maxGroupMembers = 20;

/// Thrown when a group fan-out could not reach every member (Frontend MS08).
/// The caller retries with the same message id — receivers deduplicate, so
/// members that were already reached simply drop the duplicate.
class GroupSendException implements Exception {
  /// Member ids (hex) whose delivery failed.
  final List<String> failedMemberIds;

  final String message;

  /// The network message id (hex) the partially delivered fan-out used —
  /// callers MUST persist it and retry with the same id, otherwise members
  /// that were already reached would see the retry as a new message.
  /// Null for non-message operations (rotations, renames).
  final String? messageIdHex;

  GroupSendException(this.failedMemberIds, [String? message, this.messageIdHex])
    : message =
          message ??
          'group send failed for ${failedMemberIds.length} member(s)';

  @override
  String toString() => 'GroupSendException: $message';
}
