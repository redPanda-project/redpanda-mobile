import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

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
  final String recipientPublicKey;
  final String content;
  CmdSendMessage(this.recipientPublicKey, this.content);
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

// TODO: Add EventMessageReceived when we have message handling
