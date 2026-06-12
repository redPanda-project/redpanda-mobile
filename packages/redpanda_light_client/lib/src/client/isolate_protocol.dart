import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
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

class CmdRegisterOutboundHandle extends IsolateCommand {
  final int requestId;
  final String? channelId;
  CmdRegisterOutboundHandle(this.requestId, {this.channelId});
}

class CmdAddChannelKeys extends IsolateCommand {
  final String channelId;
  final List<int> encryptionKey;
  final List<int>? peerOhId;

  /// MS04: host:port of the node hosting the peer's OH; kept out of the
  /// garlic hop path.
  final String? peerOhEndpoint;

  /// MS03b: true only on the device that generated the channel; decides the
  /// channel ratchet role.
  final bool isChannelCreator;

  /// MS03b: previously persisted ratchet state (JSON) to restore, or null to
  /// initialize a fresh ratchet from the channel key.
  final String? ratchetState;

  CmdAddChannelKeys(
    this.channelId,
    this.encryptionKey, {
    this.peerOhId,
    this.peerOhEndpoint,
    required this.isChannelCreator,
    this.ratchetState,
  });
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
  EventMessageSendFailed(this.requestId, this.error, {this.statusCode});
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

/// Advanced channel ratchet state (MS03b) forwarded from the isolate so the
/// main isolate can persist it on-device. Carries the state as its JSON
/// serialization to stay isolate-sendable.
class EventRatchetStateUpdate extends IsolateEvent {
  final String channelId;
  final String stateJson;
  EventRatchetStateUpdate({required this.channelId, required this.stateJson});
}

/// OH state change (cursor advanced, renewal, mailbox overflow) forwarded
/// from the isolate so the main isolate can persist cursor/expiry.
class EventOhMailboxUpdate extends IsolateEvent {
  final List<int> ohId;
  final String? channelId;
  final int lastCursor;
  final int expiresAtMs;
  final bool mailboxOverflow;
  EventOhMailboxUpdate({
    required this.ohId,
    required this.lastCursor,
    required this.expiresAtMs,
    this.channelId,
    this.mailboxOverflow = false,
  });
}
