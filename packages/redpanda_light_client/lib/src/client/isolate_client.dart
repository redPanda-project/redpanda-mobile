import 'dart:async';
import 'dart:isolate';

import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// A facade that implements [RedPandaClient] but proxies all operations
/// to a background [Isolate] to prevent UI jank.
class RedPandaIsolateClient implements RedPandaClient {
  final NodeId selfNodeId;
  final KeyPair selfKeys;
  final List<String> seeds;

  // Isolate? _isolate; // Kept only if we need to kill it explicitly
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Completer<void> _isolateReady = Completer<void>();

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  // Cache last known status
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  int _currentPeerCount = 0;

  RedPandaIsolateClient({
    required this.selfNodeId,
    required this.selfKeys,
    this.seeds = const [],
  }) {
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
      CmdInit(nodeId: selfNodeId, keyPair: selfKeys, seeds: seeds),
    );
  }

  void _handleEvent(IsolateEvent event) {
    if (event is EventConnectionStatus) {
      _currentStatus = event.status;
      _connectionStatusController.add(event.status);
    } else if (event is EventPeerCount) {
      _currentPeerCount = event.count;
      _peerCountController.add(event.count);
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
  Future<String> sendMessage(String recipientPublicKey, String content) async {
    _send(CmdSendMessage(recipientPublicKey, content));
    // TODO: Wait for response/ack? Facade currently returns Future<String>
    // For now return dummy
    return "Queued";
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
      client = RedPandaLightClient(
        selfNodeId: message.nodeId,
        selfKeys: message.keyPair,
        seeds: message.seeds,
      );

      // Listen to client streams and forward to main isolate
      client!.connectionStatus.listen((status) {
        mainSendPort.send(EventConnectionStatus(status));
      });

      client!.peerCountStream.listen((count) {
        mainSendPort.send(EventPeerCount(count));
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
        await client!.sendMessage(message.recipientPublicKey, message.content);
      }
    } catch (e, stack) {
      print('RedPandaWorker: Error handling command $message: $e');
      print(stack);
    }
  });
}
