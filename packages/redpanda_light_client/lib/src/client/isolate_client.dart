import 'dart:async';
import 'dart:isolate';

import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/models/peer_stats_snapshot.dart';

/// A facade that implements [RedPandaClient] but proxies all operations
/// to a background [Isolate] to prevent UI jank.
class RedPandaIsolateClient implements RedPandaClient {
  final NodeId? _explicitNodeId;
  final KeyPair? _explicitKeys;
  final List<String> seeds;

  // Isolate? _isolate; // Kept only if we need to kill it explicitly
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Completer<void> _isolateReady = Completer<void>();

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  final _peerStatsController = StreamController<PeerStatsSnapshot>.broadcast();
  PeerStatsSnapshot? _lastSnapshot;

  final _incomingMessageController = StreamController<DecryptedMessage>.broadcast();

  // Cache last known status
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  int _currentPeerCount = 0;

  RedPandaIsolateClient({
    NodeId? selfNodeId,
    KeyPair? selfKeys,
    this.seeds = const [],
  }) : _explicitNodeId = selfNodeId,
       _explicitKeys = selfKeys {
    _startIsolate();
  }

  Future<void> _startIsolate() async {
    try {
      await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort.sendPort,
        debugName: 'RedPandaNetworkWorker',
      );

      _receivePort.listen((message) {
        if (message is SendPort) {
          _sendPort = message;
          _sendInitCommand();
          _isolateReady.complete();
        } else if (message is IsolateEvent) {
          _handleEvent(message);
        }
      });
    } catch (e) {
      print('RedPandaIsolateClient: Failed to spawn isolate: $e');
    }
  }

  void _sendInitCommand() {
    _sendPort?.send(
      CmdInit(nodeId: _explicitNodeId, keyPair: _explicitKeys, seeds: seeds),
    );
  }

  void _handleEvent(IsolateEvent event) {
    if (event is EventConnectionStatus) {
      _currentStatus = event.status;
      _connectionStatusController.add(event.status);
    } else if (event is EventPeerCount) {
      _currentPeerCount = event.count;
      _peerCountController.add(event.count);
    } else if (event is EventPeerStatsSnapshot) {
      final snapshot = PeerStatsSnapshot(
        allPeers: event.allPeers,
        activePeerAddresses: event.activePeerAddresses.toSet(),
        connectingPeerAddresses: event.connectingPeerAddresses.toSet(),
      );
      _lastSnapshot = snapshot;
      _peerStatsController.add(snapshot);
    } else if (event is EventIncomingMessage) {
      _incomingMessageController.add(event.message);
    } else if (event is EventLog) {
      print('[Isolate] ${event.message}');
    }
  }

  void _send(IsolateCommand cmd) {
    if (_sendPort != null) {
      _sendPort!.send(cmd);
    } else {
      // If isolate isn't ready, maybe queue? For now just log.
      print(
        'RedPandaIsolateClient: Warning - Isolate not ready. Dropping command $cmd',
      );
    }
  }

  @override
  Stream<ConnectionStatus> get connectionStatus async* {
    yield _currentStatus;
    yield* _connectionStatusController.stream;
  }

  @override
  Stream<int> get peerCountStream async* {
    yield _currentPeerCount;
    yield* _peerCountController.stream;
  }

  @override
  Stream<PeerStatsSnapshot> get peerStatsStream async* {
    if (_lastSnapshot != null) {
      yield _lastSnapshot!;
    }
    yield* _peerStatsController.stream;
  }

  @override
  Stream<DecryptedMessage> get incomingMessages => _incomingMessageController.stream;

  @override
  Future<void> connect() async {
    await _isolateReady.future;
    _send(CmdConnect());
  }

  @override
  Future<void> disconnect() async {
    _send(CmdDisconnect());
  }

  @override
  Future<void> addPeer(String address) async {
    _send(CmdAddPeer(address));
  }

  @override
  Future<String> sendMessage(String channelId, String content) async {
    _send(CmdSendMessage(channelId, content));
    // TODO: Wait for EventMessageSent response from isolate
    return '${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<OHRegistration> registerOutboundHandle() async {
    _send(CmdRegisterOutboundHandle());
    // TODO: Wait for response from isolate with actual registration
    throw UnimplementedError(
      'registerOutboundHandle via isolate not yet wired - use direct client for now',
    );
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async {
    // Polling is handled internally by the client in the isolate
    return [];
  }

  /// Register channel encryption keys in the isolate client.
  void addChannelKeys(String channelId, List<int> encryptionKey, {List<int>? peerOhId}) {
    _send(CmdAddChannelKeys(channelId, encryptionKey, peerOhId: peerOhId));
  }

  // Lifecycle hooks proxied
  void onPause() {
    _send(CmdLifecyclePause());
  }

  void onResume() {
    _send(CmdLifecycleResume());
  }
}

/// The entry point for the background isolate.
void _isolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  RedPandaLightClient? client;

  receivePort.listen((message) async {
    if (message is CmdInit) {
      print('RedPandaWorker: Initializing client...');

      NodeId nodeId =
          message.nodeId ?? NodeId.fromPublicKey(KeyPair.generate());
      KeyPair keyPair = message.keyPair ?? KeyPair.generate();

      // Ensure specific keys match if one provided (edge case, not expected)
      if (message.nodeId == null || message.keyPair == null) {
        keyPair = message.keyPair ?? KeyPair.generate();
        nodeId = message.nodeId ?? NodeId.fromPublicKey(keyPair);
      } else {
        keyPair = message.keyPair!;
        nodeId = message.nodeId!;
      }

      client = RedPandaLightClient(
        selfNodeId: nodeId,
        selfKeys: keyPair,
        seeds: message.seeds,
      );

      // Listen to client streams and forward to main isolate
      client!.connectionStatus.listen((status) {
        mainSendPort.send(EventConnectionStatus(status));
      });

      client!.peerCountStream.listen((count) {
        mainSendPort.send(EventPeerCount(count));
      });

      // Forward incoming messages to main isolate
      client!.incomingMessages.listen((msg) {
        mainSendPort.send(EventIncomingMessage(msg));
      });

      // Send periodic peer stats snapshots to main thread
      Timer.periodic(const Duration(seconds: 3), (_) {
        if (client != null) {
          mainSendPort.send(
            EventPeerStatsSnapshot(
              client!.getDebugPeerStats(),
              client!.activePeerAddresses.toList(),
              client!.connectingPeerAddresses.toList(),
            ),
          );
        }
      });

      print('RedPandaWorker: Client initialized.');
    } else if (client == null) {
      print('RedPandaWorker: Error - Client not initialized yet.');
      return;
    }

    // Handle other commands
    try {
      if (message is CmdConnect) {
        await client!.connect();
      } else if (message is CmdDisconnect) {
        await client!.disconnect();
      } else if (message is CmdAddPeer) {
        await client!.addPeer(message.address);
      } else if (message is CmdLifecyclePause) {
        client!.onPause();
      } else if (message is CmdLifecycleResume) {
        client!.onResume();
      } else if (message is CmdSendMessage) {
        final messageId = await client!.sendMessage(message.channelId, message.content);
        mainSendPort.send(EventMessageSent(messageId));
      } else if (message is CmdRegisterOutboundHandle) {
        await client!.registerOutboundHandle();
      } else if (message is CmdAddChannelKeys) {
        client!.addChannelKeys(
          message.channelId,
          message.encryptionKey,
          peerOhId: message.peerOhId,
        );
      }
    } catch (e, stack) {
      print('RedPandaWorker: Error handling command $message: $e');
      print(stack);
    }
  });
}
