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
  final Set<String> _knownAddresses = {};
  final Map<String, ActivePeer> _peers = {};
  Timer? _connectionTimer;
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  // Backoff state
  final Map<String, DateTime> _nextRetryTime = {};
  final Map<String, int> _retryCounts = {};
  static const Duration _initialBackoff = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(minutes: 5);

  bool get isEncryptionActive => _peers.values.any((p) => p.isEncryptionActive);
  bool get isPongSent => _peers.values.any((p) => p.isPongSent);

  RedPandaLightClient({
    required this.selfNodeId,
    required this.selfKeys,
    List<String> seeds = defaultSeeds,
    SocketFactory? socketFactory,
  }) : _socketFactory = socketFactory ?? ((h, p) => Socket.connect(h, p)) {
    _knownAddresses.addAll(seeds);
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
    print(
      'RedPandaLightClient: Running connection check on ${_knownAddresses.length} addresses.',
    );

    // Resolve all connected peers to their IPs for deduplication
    final connectedIps = <String>{};
    for (final peer in _peers.values) {
      if (!peer.isDisconnected) {
        // We can't easily get the resolved IP of an active socket exposed via ActivePeer if strict encapsulation.
        // But we can try to resolve the *configured* address of the peer.
        try {
          final parts = peer.address.split(':');
          final host = parts[0];
          // For simplicity, we re-resolve. Optimized way would be to store resolved IP on peer.
          // NOTE: 'localhost' might resolve to multiple (ipv4/ipv6). We check if ANY match.
          final lookup = await InternetAddress.lookup(host);
          for (final addr in lookup) {
            connectedIps.add('${addr.address}:${parts[1]}');
          }
        } catch (e) {
          // ignore
        }
      }
    }

    for (final address in _knownAddresses) {
      // Check backoff first
      if (_nextRetryTime.containsKey(address)) {
        if (DateTime.now().isBefore(_nextRetryTime[address]!)) {
          // print('RedPandaLightClient: In backoff for $address. Skipping.');
          continue;
        }
      }

      if (_peers.containsKey(address)) {
        final peer = _peers[address]!;
        if (peer.isDisconnected) {
          print(
            'RedPandaLightClient: Peer $address is disconnected. Retrying...',
          );
          _peers.remove(address);
        } else {
          continue; // Already connected or connecting
        }
      }

      // Check if we are already connected to this target via another alias
      try {
        final parts = address.split(':');
        final host = parts[0];
        final port = parts[1];
        final lookup = await InternetAddress.lookup(host);

        bool alreadyConnected = false;
        for (final addr in lookup) {
          if (connectedIps.contains('${addr.address}:$port')) {
            alreadyConnected = true;
            break;
          }
        }

        if (alreadyConnected) {
          print(
            'RedPandaLightClient: Skipping $address (Already connected via alias).',
          );
          continue;
        }
      } catch (e) {
        print('RedPandaLightClient: DNS resolution failed for $address: $e');
        // Fallthrough: Try to connect anyway? Or skip?
        // If we can't resolve, connect call will likely fail too.
      }

      // Start new connection
      try {
        final peer = ActivePeer(
          address: address,
          selfNodeId: selfNodeId,
          selfKeys: selfKeys,
          socketFactory: _socketFactory,
          onStatusChange: _updateStatus,
          onDisconnect: () {
            // Handle Backoff on disconnect
            // We increment retry count here.
            // Note: success clears it in _updateStatus.

            final attempts = (_retryCounts[address] ?? 0) + 1;
            _retryCounts[address] = attempts;

            final delaySeconds =
                _initialBackoff.inSeconds * (1 << (attempts - 1)); // 2^n
            // Clamp to max
            final delay = Duration(seconds: delaySeconds);
            final clampedDelay = delay > _maxBackoff ? _maxBackoff : delay;

            _nextRetryTime[address] = DateTime.now().add(clampedDelay);
            print(
              'RedPandaLightClient: Disconnected $address. Backoff set to $clampedDelay',
            );
          },
          onPeersReceived: (peers) {
            print(
              'RedPandaLightClient: Received ${peers.length} peers from $address',
            );
            for (final p in peers) {
              addPeer(p);
            }
          },
          onPeerListRequested: () {
            // Return known addresses to share
            // We filter out the requestor's address if possible (ActivePeer knows it)
            return _knownAddresses.toList();
          },
        );
        _peers[address] = peer;
        peer.connect(); // Fire and forget (it is async inside)
      } catch (e) {
        print('RedPandaLightClient: Failed to initiate peer $address: $e');
      }
    }
  }

  @override
  Future<void> addPeer(String address) async {
    if (_knownAddresses.contains(address)) {
      return;
    }

    // Strict deduplication: Check if we are already connected to this peer via an alias
    try {
      final parts = address.split(':');
      if (parts.length != 2) return; // Invalid format

      final host = parts[0];
      final port = parts[1];

      final newPeerIps = await InternetAddress.lookup(host);

      // Check active peers
      for (final peer in _peers.values) {
        if (peer.isDisconnected) continue;

        try {
          final peerParts = peer.address.split(':');
          final peerHost = peerParts[0];
          // Check port match first
          if (peerParts[1] != port) continue;

          // Resolve peer host
          final peerIps = await InternetAddress.lookup(peerHost);

          // Intersection check
          for (final newIp in newPeerIps) {
            for (final peerIp in peerIps) {
              if (newIp.address == peerIp.address) {
                print(
                  'RedPandaLightClient: duplicate addPeer denied: $address resolves to same IP (${newIp.address}) as connected peer ${peer.address}',
                );
                return; // Duplicate found, reject
              }
            }
          }
        } catch (e) {
          // Ignore resolution errors for peers
        }
      }
    } catch (e) {
      print('RedPandaLightClient: Error resolving $address during addPeer: $e');
      // On error, maybe we allow it? or reject?
      // If we can't resolve it, we can't connect anyway likely. But safe to add?
      // Let's add it if resolution fails, logic below handles connecting.
    }

    print('RedPandaLightClient: Adding new peer $address');
    _knownAddresses.add(address);
    // Trigger immediate check or let the timer handle it?
    // Timer handles it.
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

  final String address;
  final NodeId selfNodeId;
  final KeyPair selfKeys;
  final SocketFactory socketFactory;
  final void Function(ConnectionStatus) onStatusChange;
  final void Function() onDisconnect;
  final void Function(List<String>)? onPeersReceived;
  final List<String> Function()? onPeerListRequested;

  Socket? _socket;
  final List<int> _buffer = [];

  // State
  bool _handshakeVerified = false;
  Future<void>? _handshakeInitiationFuture;

  final EncryptionManager _encryptionManager = EncryptionManager();

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
    buffer.addByte(1); // 1 = isLightClient
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
