import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/ecc/api.dart'; // Needed for ECPublicKey field

import 'package:redpanda_light_client/src/security/encryption_manager.dart';

import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';

/// The implementation of the RedPanda Light Client.
/// Manages network connections, encryption, and routing.
/// Factory for creating sockets (allows mocking).
typedef SocketFactory = Future<Socket> Function(String host, int port);

/// The implementation of the RedPanda Light Client.
/// Manages network connections, encryption, and routing.
class RedPandaLightClient implements RedPandaClient {
  final NodeId selfNodeId;
  final KeyPair selfKeys;

  // TODO: Inject NetworkManager/ConnectionManager
  // final NetworkManager _networkManager;

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  static const List<String> defaultSeeds = [
    'localhost:59558',
    'localhost:59559',
  ];

  final SocketFactory _socketFactory;
  // final Set<String> _knownAddresses = {}; // Replaced by PeerRepository
  final PeerRepository _peerRepository;
  final Map<String, ActivePeer> _peers = {};
  Timer? _connectionTimer;
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  // Configuration
  static const int maxConnections = 5;
  static const int coreSlots = 3;
  static const int roamingSlots = 2;
  static const Duration backoffDuration = Duration(seconds: 10);
  
  // State for mobile Optimization
  bool _isBackgrounded = false; // To be set by flutter lifecycle
  bool _isBadInternetDetected = false;
  DateTime _lastGlobalConnectionAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  // Backoff state
  final Map<String, DateTime> _nextRetryTime = {};
  final Map<String, int> _retryCounts = {}; // Restored
  final Set<String> _intentionalDisconnects = {};
  static const Duration _initialBackoff = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(minutes: 5);

  bool get isEncryptionActive => _peers.values.any((p) => p.isEncryptionActive);
  bool get isPongSent => _peers.values.any((p) => p.isPongSent);

  RedPandaLightClient({
    required this.selfNodeId,
    required this.selfKeys,
    List<String> seeds = defaultSeeds,
    SocketFactory? socketFactory,
    // Injectable repository for testing? For now we create it.
    PeerRepository? peerRepository,
  }) : _socketFactory = socketFactory ?? ((h, p) => Socket.connect(h, p)),
       _peerRepository = peerRepository ?? InMemoryPeerRepository() {
    _peerRepository.load().then((_) {
      _peerRepository.addAll(seeds);
      // Fast boot: Trigger immediate check after load
      _runConnectionCheck(); 
    });
  }

  /// Called when app goes to background
  void onPause() {
    _isBackgrounded = true;
    _peerRepository.save();
    // Maybe reduce timer frequency?
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 30), (_) => _runConnectionCheck());
  }

  /// Called when app resumes
  void onResume() {
    _isBackgrounded = false;
    _isBadInternetDetected = false; // transform optimism
     _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 3), (_) => _runConnectionCheck());
    _runConnectionCheck(); // Immediate
  }

  @override
  Stream<ConnectionStatus> get connectionStatus async* {
    yield _currentStatus;
    yield* _connectionStatusController.stream;
  }

  @override
  Stream<int> get peerCountStream async* {
    yield _peers.values.where((p) => p.isHandshakeVerified).length;
    yield* _peerCountController.stream;
  }

  /// PROVISIONAL: Stream of currently connected peer addresses.
  Stream<List<String>> get activePeersStream async* {
    yield _peers.values.where((p) => p.isHandshakeVerified).map((p) => p.address).toList();
    // We reuse the peerCount controller to signal updates for now? 
    // Or we need a new controller.
    // Let's create a new controller or just reuse peerCount logic as a trigger.
    await for (final _ in _peerCountController.stream) {
      yield _peers.values.where((p) => p.isHandshakeVerified).map((p) => p.address).toList();
    }
  }

  Stream<List<String>> get connectingPeersStream async* {
    yield _peers.values.where((p) => !p.isHandshakeVerified).map((p) => p.address).toList();
    await for (final _ in _peerCountController.stream) {
      yield _peers.values.where((p) => !p.isHandshakeVerified).map((p) => p.address).toList();
    }
  }

  void _updateStatus(ConnectionStatus status) {
    // Recalculate connected peers
    int connectedCount = _peers.values
        .where((p) => p.isHandshakeVerified)
        .length;
    _peerCountController.add(connectedCount);

    // Simple aggregation: If ANY connected -> Connected.
    // If ALL disconnected -> Disconnected.
    // Logic:
    // If incoming status is connected -> set global connected.
    // If incoming is disconnected -> Check if others are connected.

    if (status == ConnectionStatus.connected) {
      if (_currentStatus != ConnectionStatus.connected) {
        _currentStatus = ConnectionStatus.connected;
        _connectionStatusController.add(ConnectionStatus.connected);

        // Clear backoff for connected peers
        // Note: The logic here is global status, but we want per-peer reset.
        // Better to do it in the loop or listener?
        // Actually, onStatusChange is called by specific peer.
        // We don't have the peer address here easily unless passed.
        // Let's modify ActivePeer to pass itself or address?
        // Or cleaner: Iterate peers and clear for connected ones.
        for (final entry in _peers.entries) {
          if (entry.value.isHandshakeVerified) {
            _nextRetryTime.remove(entry.key);
            _retryCounts.remove(entry.key);
          }
        }
      }
    } else if (status == ConnectionStatus.connecting) {
      if (_currentStatus != ConnectionStatus.connected) {
        _currentStatus = ConnectionStatus.connecting;
        _connectionStatusController.add(ConnectionStatus.connecting);
      }
    } else {
      // Check if any peer is connected
      bool anyConnected = _peers.values.any((p) => p.isHandshakeVerified);
      if (!anyConnected && _currentStatus != ConnectionStatus.disconnected) {
        _currentStatus = ConnectionStatus.disconnected;
        _connectionStatusController.add(ConnectionStatus.disconnected);
      }
    }
  }

  @override
  Future<void> connect() async {
    _updateStatus(ConnectionStatus.connecting);
    print('RedPandaLightClient: Starting connection routine...');

    _startConnectionRoutine();
  }

  void _startConnectionRoutine() {
    _runConnectionCheck();
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _runConnectionCheck();
    });
  }

  Future<void> _runConnectionCheck() async {
    // 0. If bad internet detected, throttle
    if (_isBadInternetDetected) {
      if (DateTime.now().difference(_lastGlobalConnectionAttempt).inSeconds < 10) {
        return; // Wait 10s before trying again if we think logic is bad
      }
      _isBadInternetDetected = false; // Reset and try again
    }
    _lastGlobalConnectionAttempt = DateTime.now();

    print(
      'RedPandaLightClient: Running connection check. Known peers: ${_peerRepository.knownAddresses.length}',
    );

    // 1. Cleanup disconnected
    _peers.removeWhere((address, peer) {
      if (peer.isDisconnected) {
        print('RedPandaLightClient: Removing disconnected peer $address');
        return true;
      }
      // Also ping active peers periodically
      if (peer.isHandshakeVerified) {
         // If hasn't pinged in 10s, ping
         // We can do this based on timer or here
         peer.ping();
      }
      return false;
    });

    // 2. Classify Current Peers
    // A. Verify Capacity
    if (_peers.length > maxConnections) {
        // Disconnect worst performing extra peers
        final sortedParams = _peers.values.toList()
          ..sort((a, b) => a.averageLatencyMs.compareTo(b.averageLatencyMs)); // Lower latency first
        
        // Remove active peers that are worst
        for (var i = maxConnections; i < sortedParams.length; i++) {
           print('RedPandaLightClient: Over capacity. Disconnecting ${sortedParams[i].address}');
           sortedParams[i].disconnect();
        }
    }

    // B. Rotate Roaming Peers
    // B. Rotate Roaming Peers
    final best3 = _peerRepository.getBestPeers(3).map((p) => p.address).toSet();
    final connectedRoaming = _peers.values
        .where((p) => p.isHandshakeVerified && !best3.contains(p.address))
        .toList();

    if (connectedRoaming.length >= 2) {
      // Find candidates for rotation (Age > 10s)
      final candidates = connectedRoaming.where((p) {
         final age = DateTime.now().difference(p.connectedSince).inSeconds;
         // print('DEBUG: Rotation Candidate: ${p.address} Age=${age}s');
         return age >= 10;
      }).toList();

      // Disconnect ONLY ONE (the oldest)
      if (candidates.isNotEmpty) {
          candidates.sort((a, b) => a.connectedSince.compareTo(b.connectedSince)); // Oldest first
          final victim = candidates.first;
          final age = DateTime.now().difference(victim.connectedSince).inSeconds;
          
          print('RedPandaLightClient: Rotating ONE roaming peer ${victim.address} (Connected ${age}s). Keeping others.');
          _intentionalDisconnects.add(victim.address);
          victim.disconnect();
      }
    }
    
    // 3. Slot Filling
    // Identify Best Candidates from Repository
    // Strategy: Reserve 3 slots for Core (Best), 2 for Roaming (Random/New)
    final int targetCore = 3; 

    final candidates = _peerRepository.getBestPeers(10);
    int connectedCount = _peers.length;
    
    final toConnect = <String>[];
    
    // A. CORE: Fill up to targetCore with Best Peers
    for (final candidate in candidates) {
        if (connectedCount >= maxConnections) break; // Hard limit
        if (connectedCount >= targetCore && _peers.length >= targetCore) {
           // If we already have enough core-like connections, stop filling from top list
           // Note: _peers.length includes current connections. We need to be careful not to count roaming as core?
           // Actually, we just want to ensure we don't fill ALL slots with candidates.
           // We break if we have reached the "Core" saturation for this loop.
           break; 
        }

        if (!_peers.containsKey(candidate.address)) {
             // Check backoff
             if (_nextRetryTime.containsKey(candidate.address)) {
                if (DateTime.now().isBefore(_nextRetryTime[candidate.address]!)) {
                  continue; 
                }
             }
             toConnect.add(candidate.address);
             connectedCount++;
        }
    }
    
    // Random filling if we still have space (Roaming)
    if (connectedCount < maxConnections) {
       final all = _peerRepository.knownAddresses.toList()..shuffle();
       for (final addr in all) {
          if (connectedCount >= maxConnections) break;
          if (!_peers.containsKey(addr) && !toConnect.contains(addr)) {
               // Check backoff
               if (_waitInBackoff(addr)) continue;
               toConnect.add(addr);
               connectedCount++;
          }
       }
    }

    if (toConnect.isEmpty && _peers.isEmpty) {
       if (_peerRepository.knownAddresses.isNotEmpty) {
         print('RedPandaLightClient: No peers to connect to. Bad Internet?');
         _isBadInternetDetected = true;
       }
       return;
    }

    // 4. Connect
    // Resolve Deduplication done in ActivePeer or before connect?
    // We do simplified resolve check here
    final connectedIps = await _resolveConnectedIps();

    for (final address in toConnect) {
      try {
       if (await _isAliasOfConnected(address, connectedIps)) {
           continue; 
        }
        
        final peer = ActivePeer(
          address: address,
          selfNodeId: selfNodeId,
          selfKeys: selfKeys,
          socketFactory: _socketFactory,
          onStatusChange: _updateStatus,
          onNodeIdDiscovered: (nodeId) {
             _peerRepository.updatePeer(address, nodeId: nodeId);
          },
          onDisconnect: () {
            if (_intentionalDisconnects.contains(address)) {
               print('RedPandaLightClient: Peer $address disconnected intentionally (Rotation). No failure recorded.');
               _intentionalDisconnects.remove(address);
               _handleBackoff(address); // Still backoff to ensure we rotate
            } else {
               _peerRepository.updatePeer(address, isFailure: true);
               _handleBackoff(address);
            }
          },
          onPeersReceived: (peers) {
            print(
              'RedPandaLightClient: Received ${peers.length} peers from $address',
            );
            _peerRepository.addAll(peers);
            // Trigger check to potentially fill slots immediately?
            // _runConnectionCheck();
          },
          onPeerListRequested: () {
             // Return top 20 best peers to share
             return _peerRepository.getBestPeers(20).map((p) => p.address).toList();
          },
          onHandshakeComplete: () {
             _peerRepository.updatePeer(address, isSuccess: true);
             // Clear backoff
             _nextRetryTime.remove(address);
          },
          onLatencyUpdate: (latency) {
             _peerRepository.updatePeer(address, latencyMs: latency, isSuccess: true);
          }
        );
        _peers[address] = peer;
        peer.connect(); // Fire and forget (it is async inside)
      } catch (e) {
        print('RedPandaLightClient: Failed to initiate peer $address: $e');
        _peerRepository.updatePeer(address, isFailure: true);
      }
    }
  }

  // --- Helper Methods ---
  
  bool _waitInBackoff(String address) {
      if (_nextRetryTime.containsKey(address)) {
        if (DateTime.now().isBefore(_nextRetryTime[address]!)) {
          return true;
        }
      }
      return false;
  }
  
  void _handleBackoff(String address) {
       // Simple exponential backoff
       int currentDelay = 5;
       if (_nextRetryTime.containsKey(address)) {
           // If we just failed, and we were already in backoff cycle (implied), increase
           // But here we usually clear backoff on success.
           // Let's just set a standard backoff for now.
       }
       _nextRetryTime[address] = DateTime.now().add(Duration(seconds: 10)); // simple fixed for now
  }

  Future<Set<String>> _resolveConnectedIps() async {
    final connectedIps = <String>{};
    for (final peer in _peers.values) {
      if (!peer.isDisconnected) {
         try {
          final parts = peer.address.split(':');
          final host = parts[0];
          final lookup = await InternetAddress.lookup(host);
          for (final addr in lookup) {
            connectedIps.add('${addr.address}:${parts[1]}');
          }
        } catch (e) {}
      }
    }
    return connectedIps;
  }

  Future<bool> _isAliasOfConnected(String address, Set<String> connectedIps) async {
      try {
        final parts = address.split(':');
        final host = parts[0];
        final port = parts[1];
        final lookup = await InternetAddress.lookup(host);
        
        for (final addr in lookup) {
          if (connectedIps.contains('${addr.address}:$port')) {
            return true;
          }
        }
      } catch (e) {
        // resolution failed
      }
      return false;
  }

  @override
  Future<void> addPeer(String address) async {
    _peerRepository.updatePeer(address);
    _runConnectionCheck();
  }


  @override
  Future<void> disconnect() async {
    _connectionTimer?.cancel();
    for (final peer in _peers.values) {
      await peer.disconnect();
    }
    _peers.clear();
    _updateStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<String> sendMessage(String recipientPublicKey, String content) async {
    // TODO: Implement Garlic Routing / Flaschenpost
    throw UnimplementedError(
      "sendMessage not implemented in RealRedPandaClient yet",
    );
  }

  /// DEBUG ONLY: Get current peer stats
  List<PeerStats> getDebugPeerStats() {
    return _peerRepository.getBestPeers(100);
  }
}

/// Represents a single active connection attempt or established connection.
class ActivePeer {
  static const String _magic = "k3gV";
  static const int _protocolVersion = 22;
  static const int _handshakeLength = 30;

  // Commands
  static const int _cmdRequestPublicKey = 1;
  static const int _cmdSendPublicKey = 2;
  static const int _cmdActivateEncryption = 3;
  static const int _cmdPing = 5;
  static const int _cmdPong = 6;
  static const int _cmdRequestPeerList = 7;
  static const int _cmdSendPeerList = 8;
  static const int _cmdUpdateRequestTimestamp = 9;
  static const int _cmdAndroidUpdateRequestTimestamp = 13;
  static const int _cmdKademliaStore = 120;
  static const int _cmdKademliaGet = 121;
  static const int _cmdKademliaGetAnswer = 122;
  static const int _cmdJobAck = 130;
  static const int _cmdFlaschenpostPut = 141;

  final String address;
  final NodeId selfNodeId;
  final KeyPair selfKeys;
  final SocketFactory socketFactory;
  final void Function(ConnectionStatus) onStatusChange;
  final void Function() onDisconnect;
  final void Function(List<String>)? onPeersReceived;
  final void Function(int latencyMs)? onLatencyUpdate;
  final void Function()? onHandshakeComplete;
  final List<String> Function()? onPeerListRequested;
  final void Function(String nodeId)? onNodeIdDiscovered;

  Socket? _socket;
  final List<int> _buffer = [];

  // State
  bool _handshakeVerified = false;
  Future<void>? _handshakeInitiationFuture;

  final EncryptionManager _encryptionManager = EncryptionManager();
  
  // Stats
  final DateTime connectedSince = DateTime.now();
  int averageLatencyMs = 9999;
  Stopwatch? _pingStopwatch;

  bool get isEncryptionActive => _encryptionManager.isEncryptionActive;
  bool get isPongSent => _pongSent;
  bool get isHandshakeVerified => _handshakeVerified;
  bool get isDisconnected => _socket == null && _isDisconnecting;
  bool _isDisconnecting = false; // Flag if we are logically disconnected

  ECPublicKey? _peerPublicKey;
  Uint8List? _randomFromUs;
  bool _pongSent = false;
  bool _isProcessingBuffer = false;

  ActivePeer({
    required this.address,
    required this.selfNodeId,
    required this.selfKeys,
    required this.socketFactory,
    required this.onStatusChange,
    required this.onDisconnect,
    this.onPeersReceived,
    this.onPeerListRequested,
    this.onLatencyUpdate,
    this.onHandshakeComplete,
    this.onNodeIdDiscovered,
  });

  Future<void> connect() async {
    try {
      final parts = address.split(':');
      final host = parts[0];
      final port = int.parse(parts[1]);

      print('ActivePeer($address): Connecting...');
      final socket = await socketFactory(host, port);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;

      print('ActivePeer($address): TCP Connected. Sending Handshake...');
      _sendHandshake();

      _socket!.listen(
        _handleSocketData,
        onError: (e) {
          print('ActivePeer($address) socket error: $e');
          _shutdown();
        },
        onDone: () {
          print('ActivePeer($address) socket closed');
          _shutdown();
        },
      );
    } catch (e) {
      print('ActivePeer($address) connection failed: $e');
      _shutdown();
    }
  }

  void _shutdown() {
    if (_isDisconnecting) return;
    _isDisconnecting = true;
    _socket?.destroy(); // or close
    _socket = null;
    _handshakeVerified = false;
    onStatusChange(ConnectionStatus.disconnected);
    onDisconnect();
  }

  Future<void> disconnect() async {
    _shutdown();
  }

  void _sendHandshake() {
    final buffer = BytesBuilder();
    buffer.add(_magic.codeUnits);
    buffer.addByte(_protocolVersion);
    buffer.addByte(160); // 160 = isLightClient / Mobile Client
    buffer.add(selfNodeId.bytes);
    final portData = ByteData(4);
    portData.setInt32(0, 0, Endian.big);
    buffer.add(portData.buffer.asUint8List());

    _socket!.add(buffer.toBytes());
    print('ActivePeer($address): Handshake sent (${buffer.length} bytes)');
  }

  void _handleSocketData(Uint8List data) {
    var processData = data;
    if (_encryptionManager.isEncryptionActive) {
      processData = _encryptionManager.decrypt(data);
    }
    _buffer.addAll(processData);
    // print('ActivePeer($address) received: ${data.length} bytes. Buffer: ${_buffer.length}');

    if (!_isProcessingBuffer) {
      _processBuffer();
    }
  }

  Future<void> _processBuffer() async {
    if (_isProcessingBuffer) return;
    _isProcessingBuffer = true;

    try {
      while (true) {
        if (_buffer.isEmpty) break;

        if (!_handshakeVerified) {
          if (_buffer.length >= _handshakeLength) {
            _processHandshake();
            continue;
          } else {
            break;
          }
        } else {
          final command = _buffer[0];

          if (command == _cmdRequestPublicKey) {
            print('ActivePeer($address): Received requestPublicKey');
            _buffer.removeAt(0);
            _sendPublicKey();
          } else if (command == _cmdActivateEncryption) {
            print('ActivePeer($address): Received activateEncryption');
            if (_buffer.length < 1 + 8) {
              break;
            }

            if (_handshakeInitiationFuture != null) {
              await _handshakeInitiationFuture;
            }

            _buffer.removeAt(0);
            final randomFromThem = _buffer.sublist(0, 8);
            _buffer.removeRange(0, 8);

            await _handlePeerEncryptionRandom(
              Uint8List.fromList(randomFromThem),
            );
          } else if (command == _cmdSendPublicKey) {
            print('ActivePeer($address): Received sendPublicKey');
            if (_buffer.length < 1 + 65) {
              break;
            }
            _buffer.removeAt(0);
            final keyBytes = _buffer.sublist(0, 65);
            _buffer.removeRange(0, 65);

            _parsePeerPublicKey(keyBytes);
          } else if (command == _cmdPing) {
            print(
              'ActivePeer($address): Received ping (Encrypted). Sending pong...',
            );
            _buffer.removeAt(0);
            _sendPong();
          } else if (command == _cmdPong) {
            print('ActivePeer($address): Received pong (Encrypted).');
            if (_pingStopwatch != null) {
              _pingStopwatch!.stop();
              final latency = _pingStopwatch!.elapsedMilliseconds;
              _updateLatency(latency);
              _pingStopwatch = null;
            }
            _buffer.removeAt(0);
          } else if (command == _cmdRequestPeerList) {
            print('ActivePeer($address): Received requestPeerList');
            _buffer.removeAt(0);
            if (onPeerListRequested != null) {
              final peers = onPeerListRequested!();
              sendPeerList(peers);
            }
          } else if (command == _cmdSendPeerList) {
            print('ActivePeer($address): Received sendPeerList');
            if (_buffer.length < 1 + 4) {
              break; // wait for length
            }
            // Peek length
            final lengthData = Uint8List.fromList(_buffer.sublist(1, 5));
            final length = ByteData.view(
              lengthData.buffer,
            ).getInt32(0, Endian.big);

            if (_buffer.length < 1 + 4 + length) {
              break; // wait for full payload
            }

            _buffer.removeAt(0); // Remove Command
            _buffer.removeRange(0, 4); // Remove Length

            final payload = _buffer.sublist(0, length);
            _handlePeerList(payload);
            _buffer.removeRange(0, length);
          } else if (command == _cmdUpdateRequestTimestamp ||
              command == _cmdAndroidUpdateRequestTimestamp) {
            // These commands are 1-byte queries (no payload). just consume them.
            // print('ActivePeer($address): Received update timestamp request ($command). Ignoring.');
            _buffer.removeAt(0);
          } else if (command == _cmdKademliaGet ||
              command == _cmdKademliaStore ||
              command == _cmdKademliaGetAnswer ||
              command == _cmdJobAck ||
              command == _cmdFlaschenpostPut) {
            // These commands all follow the pattern: [CMD] [Length: 4 bytes] [Protobuf Data]
            if (_buffer.length < 1 + 4) {
              break; // wait for length
            }
            final lengthData = Uint8List.fromList(_buffer.sublist(1, 5));
            final length =
                ByteData.view(lengthData.buffer).getInt32(0, Endian.big);

            if (_buffer.length < 1 + 4 + length) {
              break; // wait for full payload
            }
            
            // print('ActivePeer($address): Ignored command $command with payload ($length bytes).');
            
            _buffer.removeAt(0); // Remove Command
            _buffer.removeRange(0, 4); // Remove Length
            _buffer.removeRange(0, length); // Remove Payload
          } else {
            print(
              'ActivePeer($address): Unknown command byte: $command. Discarding.',
            );
            _buffer.removeAt(0);
          }
        }
      }
    } catch (e, stack) {
      print('ActivePeer($address): Error processing buffer: $e');
      print(stack);
      _shutdown();
    } finally {
      _isProcessingBuffer = false;
    }
  }

  void _processHandshake() {
    final magicBytes = _buffer.sublist(0, 4);
    final magicVal = String.fromCharCodes(magicBytes);
    if (magicVal != _magic) {
      print('ActivePeer($address): Invalid magic. Disconnecting.');
      _shutdown();
      return;
    }

    print('ActivePeer($address): Handshake Verified.');
    _handshakeVerified = true;
    onStatusChange(ConnectionStatus.connected); // Notify manager
    onHandshakeComplete?.call();

    _buffer.removeRange(0, _handshakeLength);

    print('ActivePeer($address): Requesting Peer Public Key...');
    _socket!.add([_cmdRequestPublicKey]);
  }

  void _sendPublicKey() {
    print('ActivePeer($address): Sending Public Key...');
    final buffer = BytesBuilder();
    buffer.addByte(_cmdSendPublicKey);
    buffer.add(selfKeys.publicKeyBytes);
    _sendData(buffer.toBytes());
  }

  Uint8List? _pendingRandomFromThem;

  void _parsePeerPublicKey(List<int> keyBytes) {
    final ecParams = ECDomainParameters('brainpoolp256r1');
    final curve = ecParams.curve;
    final point = curve.decodePoint(keyBytes);
    _peerPublicKey = ECPublicKey(point, ecParams);
    print('ActivePeer($address): Peer Public Key Parsed.');

    final nodeId = NodeId.fromPublicKeyBytes(Uint8List.fromList(keyBytes));
    onNodeIdDiscovered?.call(nodeId.toHex());

    if (_randomFromUs == null) {
      _handshakeInitiationFuture = _initiateEncryptionHandshake();
    }

    if (_pendingRandomFromThem != null) {
      print(
        'ActivePeer($address): Found pending encryption request. Finalizing now.',
      );
      _finalizeEncryption(_pendingRandomFromThem!);
      _pendingRandomFromThem = null;
    }
  }

  Future<void> _initiateEncryptionHandshake() async {
    if (_randomFromUs != null) return; // Already initiated
    print('ActivePeer($address): Initiating Encryption Handshake...');
    _randomFromUs = _encryptionManager.generateRandomFromUs();
    await Future.delayed(
      const Duration(milliseconds: 100),
    ); // Buffer anti-glitch
    final buffer = BytesBuilder();
    buffer.addByte(_cmdActivateEncryption);
    buffer.add(_randomFromUs!);
    _sendData(buffer.toBytes(), forceUnencrypted: true);
    print('ActivePeer($address): Sent activateEncryption request.');
  }

  Future<void> _handlePeerEncryptionRandom(Uint8List randomFromThem) async {
    if (_randomFromUs == null) {
      _handshakeInitiationFuture = _initiateEncryptionHandshake();
      await _handshakeInitiationFuture;
    }
    _finalizeEncryption(randomFromThem);
  }

  void _finalizeEncryption(Uint8List randomFromThem) {
    try {
      if (_peerPublicKey == null) {
        print(
          'ActivePeer($address): Peer Public Key missing. Deferring encryption finalization.',
        );
        _pendingRandomFromThem = randomFromThem;
        return;
      }
      if (selfKeys.privateKey == null || _randomFromUs == null) {
        print(
          'ActivePeer($address): Cannot activate encryption, missing self state.',
        );
        return;
      }

      print('ActivePeer($address): Finalizing Encryption...');
      _encryptionManager.deriveAndInitialize(
        selfKeys: selfKeys.asAsymmetricKeyPair(),
        peerPublicKey: _peerPublicKey!,
        randomFromUs: _randomFromUs!,
        randomFromThem: randomFromThem,
      );

      print('ActivePeer($address): Encryption Active!');
      print('ActivePeer($address): Sending Initial ping (Encrypted)...');
      _sendData([_cmdPing]);

      // Auto-bootstrap: Request Peer List
      print('ActivePeer($address): Requesting Peer List (Encrypted)...');
      requestPeerList();

      if (_buffer.isNotEmpty) {
        final remaining = Uint8List.fromList(_buffer);
        _buffer.clear();
        final decrypted = _encryptionManager.decrypt(remaining);
        _buffer.addAll(decrypted);
        print('ActivePeer($address): Decrypted residual bytes.');
      }
    } catch (e, stack) {
      print('ActivePeer($address): Error activating encryption: $e');
      print(stack);
      _shutdown();
    }
  }

  void _sendPong() {
    print('ActivePeer($address): Sending pong...');
    _sendData([_cmdPong]);
    _pongSent = true;
  }

  /// Sends a ping to measure latency.
  void ping() {
    if (_pingStopwatch != null) return; // Already pinging
    print('ActivePeer($address): Sending Ping (Latency Check)...');
    _pingStopwatch = Stopwatch()..start();
    _sendData([_cmdPing]);
  }

  void _updateLatency(int latency) {
    if (averageLatencyMs == 9999) {
      averageLatencyMs = latency;
    } else {
      // Exponential moving average (weight new value by 30%)
      averageLatencyMs = (averageLatencyMs * 0.7 + latency * 0.3).round();
    }
    print('ActivePeer($address): Latency updated to ${averageLatencyMs}ms (current: ${latency}ms)');
    onLatencyUpdate?.call(averageLatencyMs);
  }

  void _sendData(List<int> data, {bool forceUnencrypted = false}) {
    if (_socket == null) return;
    Uint8List output;
    if (_encryptionManager.isEncryptionActive && !forceUnencrypted) {
      output = _encryptionManager.encrypt(Uint8List.fromList(data));
    } else {
      output = Uint8List.fromList(data);
    }
    _socket!.add(output);
  }

  void requestPeerList() {
    _sendData([_cmdRequestPeerList]);
  }

  void sendPeerList(List<String> peers) {
    print('ActivePeer($address): Sending Peer List (${peers.length})...');
    final msg = SendPeerList();
    for (final p in peers) {
      try {
        final parts = p.split(':');
        if (parts.length == 2) {
          msg.peers.add(
            PeerInfoProto()
              ..ip = parts[0]
              ..port = int.parse(parts[1]),
          );
        }
      } catch (e) {
        print('ActivePeer($address): Error parsing peer for send: $p');
      }
    }
    final protoBytes = msg.writeToBuffer();
    final buffer = BytesBuilder();
    buffer.addByte(_cmdSendPeerList);
    final lengthData = ByteData(4);
    lengthData.setInt32(0, protoBytes.length, Endian.big);
    buffer.add(lengthData.buffer.asUint8List());
    buffer.add(protoBytes);

    _sendData(buffer.toBytes());
  }

  void _handlePeerList(List<int> payload) {
    try {
      final msg = SendPeerList.fromBuffer(payload);
      final peers = <String>[];
      for (final peerProto in msg.peers) {
        if (peerProto.ip.isNotEmpty && peerProto.port > 0) {
          final peerAddr = '${peerProto.ip}:${peerProto.port}';
          // Filter out our own address if possible, but we might not know it easily.
          // The client will deduplicate anyway.
          peers.add(peerAddr);
        }
      }
      onPeersReceived?.call(peers);
    } catch (e) {
      print('ActivePeer($address): Failed to parse peer list: $e');
    }
  }
}
