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
  final String channelId;
  final String content;
  CmdSendMessage(this.channelId, this.content);
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
  CmdAddChannelKeys(this.channelId, this.encryptionKey, {this.peerOhId});
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
  final String messageId;
  EventMessageSent(this.messageId);
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
  EventOhRegisterFailed(this.requestId, this.error);
}
