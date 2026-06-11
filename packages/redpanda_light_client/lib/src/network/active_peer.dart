import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/ecc/api.dart'; // Needed for ECPublicKey field

import 'package:redpanda_light_client/src/security/encryption_manager.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';

/// Factory for creating sockets (allows mocking).
typedef SocketFactory = Future<Socket> Function(String host, int port);

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
  static const int _cmdOutboundRegisterOhReq = 150;
  static const int _cmdOutboundRegisterOhRes = 151;
  static const int _cmdOutboundFetchReq = 152;
  static const int _cmdOutboundFetchRes = 153;
  static const int _cmdOutboundAckFetchRes = 157;

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

  /// Callback for OH response commands (151, 153, 157).
  void Function(int command, List<int> payload)? onCommandResponse;

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
              command == _cmdFlaschenpostPut ||
              command == _cmdOutboundRegisterOhReq ||
              command == _cmdOutboundFetchReq) {
            // These commands all follow the pattern: [CMD] [Length: 4 bytes] [Protobuf Data]
            if (_buffer.length < 1 + 4) {
              break; // wait for length
            }
            final lengthData = Uint8List.fromList(_buffer.sublist(1, 5));
            final length = ByteData.view(
              lengthData.buffer,
            ).getInt32(0, Endian.big);

            if (_buffer.length < 1 + 4 + length) {
              break; // wait for full payload
            }

            // print('ActivePeer($address): Ignored command $command with payload ($length bytes).');

            _buffer.removeAt(0); // Remove Command
            _buffer.removeRange(0, 4); // Remove Length
            _buffer.removeRange(0, length); // Remove Payload
          } else if (command == _cmdOutboundRegisterOhRes ||
              command == _cmdOutboundFetchRes ||
              command == _cmdOutboundAckFetchRes) {
            if (_buffer.length < 1 + 4) break;
            final lengthData = Uint8List.fromList(_buffer.sublist(1, 5));
            final length = ByteData.view(
              lengthData.buffer,
            ).getInt32(0, Endian.big);
            if (_buffer.length < 1 + 4 + length) break;
            _buffer.removeAt(0);
            _buffer.removeRange(0, 4);
            final payload = _buffer.sublist(0, length);
            _buffer.removeRange(0, length);
            onCommandResponse?.call(command, payload);
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
    print(
      'ActivePeer($address): Latency updated to ${averageLatencyMs}ms (current: ${latency}ms)',
    );
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

  /// Sends a command with [CMD][4 length big-endian][protobuf bytes].
  void sendCommand(int command, Uint8List protobufBytes) {
    final buffer = BytesBuilder();
    buffer.addByte(command);
    final lengthData = ByteData(4);
    lengthData.setInt32(0, protobufBytes.length, Endian.big);
    buffer.add(lengthData.buffer.asUint8List());
    buffer.add(protobufBytes);
    _sendData(buffer.toBytes());
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
