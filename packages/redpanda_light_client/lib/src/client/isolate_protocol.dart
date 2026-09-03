import 'package:redpanda_light_client/src/domain/channel_doctor_report.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';

// --- Commands (Main -> Isolate) ---
abstract class IsolateCommand {}

class CmdInit extends IsolateCommand {
  final NodeId? nodeId;
  final KeyPair? keyPair;
  // We might want to pass seeds here too if they are dynamic
  final List<String> seeds;

  CmdInit({this.nodeId, this.keyPair, this.seeds = const []});
}

class CmdConnect extends IsolateCommand {}

class CmdDisconnect extends IsolateCommand {}

class CmdAddPeer extends IsolateCommand {
  final String address;
  CmdAddPeer(this.address);
}

class CmdLifecyclePause extends IsolateCommand {}

class CmdLifecycleResume extends IsolateCommand {}

class CmdSendMessage extends IsolateCommand {
  final int requestId;
  final String channelId;
  final String content;

  /// Stable hex message id reused across retries; null to let the network
  /// layer generate a fresh one.
  final String? messageId;
  CmdSendMessage(
    this.requestId,
    this.channelId,
    this.content, {
    this.messageId,
  });
}

/// Runs a loopback self-test (T20); answered with [EventLoopbackResult].
class CmdRunLoopbackTest extends IsolateCommand {
  final int requestId;
  final String channelId;
  CmdRunLoopbackTest(this.requestId, this.channelId);
}

/// Runs the connection doctor (T25); answered with [EventChannelDoctorResult].
class CmdRunChannelDoctor extends IsolateCommand {
  final int requestId;
  final String channelId;
  CmdRunChannelDoctor(this.requestId, this.channelId);
}

class CmdRegisterOutboundHandle extends IsolateCommand {
  final int requestId;
  final String? channelId;
  CmdRegisterOutboundHandle(this.requestId, {this.channelId});
}

/// Isolate-sendable form of an [OHDescriptor] (T42 multi-OH): plain
/// primitives that cross the isolate boundary unchanged.
class OhDescriptorData {
  final String endpoint;
  final List<int> ohId;
  final List<int> authPublicKey;
  const OhDescriptorData({
    required this.endpoint,
    required this.ohId,
    required this.authPublicKey,
  });
}

class CmdAddChannelKeys extends IsolateCommand {
  final String channelId;
  final List<int> encryptionKey;

  /// T44: the 32-byte channel secret (QR v4), needed for the rendezvous DHT
  /// derivations (record key, signature, k_enc). Null for legacy callers.
  final List<int>? channelSecret;

  /// T44: our display name to advertise in the rendezvous record.
  final String? ownDisplayName;

  final List<int>? peerOhId;

  /// MS04: host:port of the node hosting the peer's OH; kept out of the
  /// garlic hop path.
  final String? peerOhEndpoint;

  /// T42: the full persisted peer OH set to restore (multi-OH). Applied only
  /// when no richer set is live yet.
  final List<OhDescriptorData>? peerOhSet;

  /// MS03b: true only on the device that generated the channel; decides the
  /// channel ratchet role.
  final bool isChannelCreator;

  /// MS03b: previously persisted ratchet state (JSON) to restore, or null to
  /// initialize a fresh ratchet from the channel key.
  final String? ratchetState;

  /// MS05: persisted outstanding session tags (tag hex → createdAtMs) to
  /// restore; applied only on the first registration of the channel.
  final Map<String, int>? sessionTags;

  /// MS05: persisted pending ReverseGarlicBlock (serialized, hex) to restore.
  final String? pendingRgbHex;

  CmdAddChannelKeys(
    this.channelId,
    this.encryptionKey, {
    this.channelSecret,
    this.ownDisplayName,
    this.peerOhId,
    this.peerOhEndpoint,
    this.peerOhSet,
    required this.isChannelCreator,
    this.ratchetState,
    this.sessionTags,
    this.pendingRgbHex,
  });
}

/// Tops a channel up to the target OH redundancy (T42, k=3). Fire-and-forget:
/// the resulting set is published as an [OwnOhSetUpdate].
class CmdEnsureOhRedundancy extends IsolateCommand {
  final String channelId;
  CmdEnsureOhRedundancy(this.channelId);
}

/// Re-activates a persisted OH registration inside the isolate so it gets
/// polled and auto-renewed again. Carries only isolate-sendable primitives.
class CmdRestoreOutboundHandle extends IsolateCommand {
  final List<int> ohId;
  final List<int> privateKeyBytes;
  final int expiresAtMs;
  final String? channelId;
  final String? serverEndpoint;
  final int lastCursor;
  CmdRestoreOutboundHandle({
    required this.ohId,
    required this.privateKeyBytes,
    required this.expiresAtMs,
    this.channelId,
    this.serverEndpoint,
    this.lastCursor = 0,
  });
}

/// Feeds persisted node scores (MS06) back into the isolate on startup.
/// [NodeScore] carries only primitives and is isolate-sendable.
class CmdRestoreNodeScores extends IsolateCommand {
  final List<NodeScore> scores;
  CmdRestoreNodeScores(this.scores);
}

/// Registers a group (MS08). [GroupRegistration] carries only
/// isolate-sendable primitives and plain data classes.
class CmdRegisterGroup extends IsolateCommand {
  final GroupRegistration registration;
  CmdRegisterGroup(this.registration);
}

/// Sends a group message (MS08); answered with [EventMessageSent] /
/// [EventMessageSendFailed] like a 1:1 send.
class CmdSendGroupMessage extends IsolateCommand {
  final int requestId;
  final String groupId;
  final String content;
  final String? messageId;
  CmdSendGroupMessage(
    this.requestId,
    this.groupId,
    this.content, {
    this.messageId,
  });
}

/// Rotates the group key (MS08, admin only); answered with
/// [EventGroupOpDone].
class CmdRotateGroupKey extends IsolateCommand {
  final int requestId;
  final String groupId;
  final List<GroupMemberInfo> members;
  final String? label;
  CmdRotateGroupKey(this.requestId, this.groupId, this.members, {this.label});
}

/// Re-sends undelivered sealed rotation boxes (MS08); answered with
/// [EventGroupOpDone].
class CmdRetryPendingRotations extends IsolateCommand {
  final int requestId;
  final String groupId;
  CmdRetryPendingRotations(this.requestId, this.groupId);
}

/// Sends a group handshake over a 1:1 channel (MS08, Decision 8); answered
/// with [EventGroupOpDone].
class CmdSendGroupHandshake extends IsolateCommand {
  final int requestId;
  final String channelId;
  final List<int> handshake;
  CmdSendGroupHandshake(this.requestId, this.channelId, this.handshake);
}

/// Broadcasts a group rename (MS08, admin only); answered with
/// [EventGroupOpDone].
class CmdSendGroupInfoUpdate extends IsolateCommand {
  final int requestId;
  final String groupId;
  final String label;
  CmdSendGroupInfoUpdate(this.requestId, this.groupId, this.label);
}

// --- Events (Isolate -> Main) ---
abstract class IsolateEvent {}

class EventConnectionStatus extends IsolateEvent {
  final ConnectionStatus status;
  EventConnectionStatus(this.status);
}

class EventPeerCount extends IsolateEvent {
  final int count;
  EventPeerCount(this.count);
}

class EventLog extends IsolateEvent {
  final String message;
  EventLog(this.message);
}

class EventPeerStatsSnapshot extends IsolateEvent {
  final List<PeerStats> allPeers;
  final List<String> activePeerAddresses;
  final List<String> connectingPeerAddresses;
  EventPeerStatsSnapshot(
    this.allPeers,
    this.activePeerAddresses,
    this.connectingPeerAddresses,
  );
}

class EventMessageSent extends IsolateEvent {
  final int requestId;
  final String messageId;
  EventMessageSent(this.requestId, this.messageId);
}

class EventMessageSendFailed extends IsolateEvent {
  final int requestId;
  final String error;

  /// Proto Status name when the node rejected the deposit (MS02b), e.g.
  /// 'QUOTA_EXCEEDED'. Null for generic failures (no peer, timeout). Travels
  /// as a string so the event stays isolate-sendable; the main side rebuilds
  /// a DepositException from it.
  final String? statusCode;

  /// MS08: member ids (hex) a group fan-out could not reach; the main side
  /// rebuilds a GroupSendException from it. Null for 1:1 sends.
  final List<String>? failedMemberIds;

  /// MS08: the message id (hex) a partially delivered group fan-out used —
  /// travels with the failure so the retry reuses it.
  final String? messageIdHex;
  EventMessageSendFailed(
    this.requestId,
    this.error, {
    this.statusCode,
    this.failedMemberIds,
    this.messageIdHex,
  });
}

/// Outcome of a loopback self-test (T20). Mirrors [LoopbackResult] as
/// isolate-sendable primitives.
class EventLoopbackResult extends IsolateEvent {
  final int requestId;
  final bool success;
  final int? roundtripMs;
  final int? hopCount;
  final String? error;
  EventLoopbackResult({
    required this.requestId,
    required this.success,
    this.roundtripMs,
    this.hopCount,
    this.error,
  });
}

/// Outcome of runChannelDoctor (T25). [ChannelDoctorReport] carries only
/// isolate-sendable primitives (plain data classes + an enum), so it travels
/// as-is like [GroupStateUpdate].
class EventChannelDoctorResult extends IsolateEvent {
  final int requestId;
  final ChannelDoctorReport report;
  EventChannelDoctorResult({required this.requestId, required this.report});
}

class EventIncomingMessage extends IsolateEvent {
  final DecryptedMessage message;
  EventIncomingMessage(this.message);
}

/// Successful OH registration. Carries only isolate-sendable primitives;
/// the keypair travels as its 32-byte private scalar
/// (see OHKeypair.privateKeyBytes / OHKeypair.fromPrivateKeyBytes).
class EventOhRegistered extends IsolateEvent {
  final int requestId;
  final List<int> ohId;
  final List<int> privateKeyBytes;
  final int expiresAtMs;
  final String? channelId;
  final String? serverEndpoint;
  EventOhRegistered({
    required this.requestId,
    required this.ohId,
    required this.privateKeyBytes,
    required this.expiresAtMs,
    this.channelId,
    this.serverEndpoint,
  });
}

class EventOhRegisterFailed extends IsolateEvent {
  final int requestId;
  final String error;

  /// True when the node rejected the registration with RATE_LIMIT (MS02b);
  /// the main side rebuilds a RateLimitException from it.
  final bool rateLimited;
  EventOhRegisterFailed(this.requestId, this.error, {this.rateLimited = false});
}

/// Completion of a group operation (rotate/retry/handshake/rename, MS08).
class EventGroupOpDone extends IsolateEvent {
  final int requestId;

  /// Null on success; otherwise the error description.
  final String? error;

  /// Set when the failure was a partial fan-out ([GroupSendException]).
  final List<String>? failedMemberIds;

  /// Proto Status name when a node rejected a deposit (DepositException).
  final String? statusCode;
  EventGroupOpDone(
    this.requestId, {
    this.error,
    this.failedMemberIds,
    this.statusCode,
  });
}

/// The ONE state event (see [StateUpdate]): every one-way state change the
/// worker publishes — ratchet, garlic session, OH mailbox/fetch/own-set/
/// peer-set, ACKs, node scores, group state and handshakes — crosses the
/// isolate boundary inside this envelope. A new state event needs no new
/// protocol class, no `_handleEvent` branch and no controller here.
///
/// The payload is isolate-sendable by construction: [StateUpdate] subtypes
/// are plain Dart objects (the own-OH set carries [OHRegistration]s whose
/// keypair is just the 32-byte Ed25519 seed plus verify key).
class EventStateUpdate extends IsolateEvent {
  final StateUpdate update;
  EventStateUpdate(this.update);
}
