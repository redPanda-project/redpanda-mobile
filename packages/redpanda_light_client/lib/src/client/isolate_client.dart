import 'dart:async';
import 'dart:isolate';

import 'dart:typed_data';

import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/models/peer_stats_snapshot.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';

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

  final _incomingMessageController =
      StreamController<DecryptedMessage>.broadcast();

  final _ohMailboxUpdateController =
      StreamController<OhMailboxUpdate>.broadcast();

  // Pending OH registrations awaiting their isolate response, by requestId.
  final Map<int, Completer<OHRegistration>> _pendingOhRegistrations = {};

  // Pending sends awaiting their isolate response, by requestId.
  final Map<int, Completer<String>> _pendingSends = {};
  int _nextRequestId = 0;

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
      RpLog.debug('RedPandaIsolateClient: Failed to spawn isolate: $e');
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
    } else if (event is EventOhRegistered) {
      final completer = _pendingOhRegistrations.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        try {
          completer.complete(
            OHRegistration(
              ohId: event.ohId,
              keypair: OHKeypair.fromPrivateKeyBytes(
                Uint8List.fromList(event.privateKeyBytes),
              ),
              expiresAtMs: event.expiresAtMs,
              channelId: event.channelId,
              serverEndpoint: event.serverEndpoint,
            ),
          );
        } catch (e) {
          completer.completeError(e);
        }
      }
    } else if (event is EventOhRegisterFailed) {
      final completer = _pendingOhRegistrations.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          event.rateLimited ? RateLimitException() : StateError(event.error),
        );
      }
    } else if (event is EventMessageSent) {
      final completer = _pendingSends.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(event.messageId);
      }
    } else if (event is EventMessageSendFailed) {
      final completer = _pendingSends.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        final statusCode = event.statusCode;
        completer.completeError(
          statusCode != null
              ? DepositException(statusCode)
              : StateError(event.error),
        );
      }
    } else if (event is EventOhMailboxUpdate) {
      _ohMailboxUpdateController.add(
        OhMailboxUpdate(
          ohId: event.ohId,
          channelId: event.channelId,
          lastCursor: event.lastCursor,
          expiresAtMs: event.expiresAtMs,
          mailboxOverflow: event.mailboxOverflow,
        ),
      );
    } else if (event is EventLog) {
      RpLog.debug('[Isolate] ${event.message}');
    }
  }

  void _send(IsolateCommand cmd) {
    if (_sendPort != null) {
      _sendPort!.send(cmd);
    } else {
      // If isolate isn't ready, maybe queue? For now just log.
      RpLog.debug(
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
  Stream<DecryptedMessage> get incomingMessages =>
      _incomingMessageController.stream;

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
  Future<String> sendMessage(
    String channelId,
    String content, {
    String? messageId,
  }) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<String>();
    _pendingSends[requestId] = completer;
    _send(CmdSendMessage(requestId, channelId, content, messageId: messageId));
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingSends.remove(requestId);
        throw TimeoutException(
          'sendMessage timed out',
          const Duration(seconds: 15),
        );
      },
    );
  }

  @override
  Future<OHRegistration> registerOutboundHandle({String? channelId}) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<OHRegistration>();
    _pendingOhRegistrations[requestId] = completer;
    _send(CmdRegisterOutboundHandle(requestId, channelId: channelId));
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingOhRegistrations.remove(requestId);
        throw TimeoutException(
          'OH registration timed out',
          const Duration(seconds: 15),
        );
      },
    );
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async {
    // Polling is handled internally by the client in the isolate; fetched
    // messages are delivered via [incomingMessages]. This facade method
    // therefore has nothing to return directly.
    return [];
  }

  @override
  Future<void> restoreOutboundHandle(OHRegistration registration) async {
    await _isolateReady.future;
    _send(
      CmdRestoreOutboundHandle(
        ohId: registration.ohId,
        privateKeyBytes: registration.keypair.privateKeyBytes.toList(),
        expiresAtMs: registration.expiresAtMs,
        channelId: registration.channelId,
        serverEndpoint: registration.serverEndpoint,
        lastCursor: registration.lastCursor,
      ),
    );
  }

  @override
  Stream<OhMailboxUpdate> get ohMailboxUpdates =>
      _ohMailboxUpdateController.stream;

  /// Register channel encryption keys in the isolate client.
  @override
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? peerOhId,
  }) {
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
      RpLog.debug('RedPandaWorker: Initializing client...');

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

      // Forward OH mailbox updates (cursor/expiry/overflow) to main isolate
      client!.ohMailboxUpdates.listen((update) {
        mainSendPort.send(
          EventOhMailboxUpdate(
            ohId: update.ohId,
            channelId: update.channelId,
            lastCursor: update.lastCursor,
            expiresAtMs: update.expiresAtMs,
            mailboxOverflow: update.mailboxOverflow,
          ),
        );
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

      RpLog.info('RedPandaWorker: Client initialized.');
    } else if (client == null) {
      RpLog.info('RedPandaWorker: Error - Client not initialized yet.');
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
        try {
          final messageId = await client!.sendMessage(
            message.channelId,
            message.content,
            messageId: message.messageId,
          );
          mainSendPort.send(EventMessageSent(message.requestId, messageId));
        } on DepositException catch (e) {
          mainSendPort.send(
            EventMessageSendFailed(
              message.requestId,
              e.toString(),
              statusCode: e.statusName,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            EventMessageSendFailed(message.requestId, e.toString()),
          );
        }
      } else if (message is CmdRegisterOutboundHandle) {
        try {
          final registration = await client!.registerOutboundHandle(
            channelId: message.channelId,
          );
          mainSendPort.send(
            EventOhRegistered(
              requestId: message.requestId,
              ohId: registration.ohId,
              privateKeyBytes: registration.keypair.privateKeyBytes.toList(),
              expiresAtMs: registration.expiresAtMs,
              channelId: registration.channelId,
              serverEndpoint: registration.serverEndpoint,
            ),
          );
        } on RateLimitException catch (e) {
          mainSendPort.send(
            EventOhRegisterFailed(
              message.requestId,
              e.toString(),
              rateLimited: true,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            EventOhRegisterFailed(message.requestId, e.toString()),
          );
        }
      } else if (message is CmdAddChannelKeys) {
        client!.addChannelKeys(
          message.channelId,
          message.encryptionKey,
          peerOhId: message.peerOhId,
        );
      } else if (message is CmdRestoreOutboundHandle) {
        await client!.restoreOutboundHandle(
          OHRegistration(
            ohId: message.ohId,
            keypair: OHKeypair.fromPrivateKeyBytes(
              Uint8List.fromList(message.privateKeyBytes),
            ),
            expiresAtMs: message.expiresAtMs,
            channelId: message.channelId,
            serverEndpoint: message.serverEndpoint,
            lastCursor: message.lastCursor,
          ),
        );
      }
    } catch (e, stack) {
      RpLog.debug('RedPandaWorker: Error handling command $message: $e');
      RpLog.debug(stack.toString());
    }
  });
}
