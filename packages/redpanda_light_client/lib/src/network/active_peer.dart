import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/security/gcm_framed_codec.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/discovered_peer.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';

/// Factory for creating sockets (allows mocking).
typedef SocketFactory = Future<Socket> Function(String host, int port);

/// Represents a single active connection attempt or established connection.
///
/// Speaks protocol v23 (MS03): 30-byte magic handshake, 64-byte
/// Ed25519/X25519 public-key exchange, ephemeral X25519 key agreement and
/// framed AES-256-GCM transport encryption ([GcmFramedCodec]).
class ActivePeer {
  static const String _magic = "k3gV";
  static const int _protocolVersion = 23;
  static const int _handshakeLength = 30;

  /// How long a TCP-connected peer may stay unverified before it is dropped.
  ///
  /// A node sends its 30-byte handshake header the moment it accepts the
  /// socket, so on a healthy connection this is a matter of milliseconds. When
  /// it does not arrive there was nothing to time it out before (T89b): the
  /// dial has a timeout, the handshake had none, and a connected-but-unverified
  /// peer is not `isDisconnected` (that needs `_socket == null` *and*
  /// `_isDisconnecting`), so `RedPandaLightClient._runConnectionCheck` neither
  /// reaped it nor re-dialled its address — the address already had an entry in
  /// `_peers`. With a single known peer, which is what the emulator gate runs
  /// with, that is a permanent wedge at `connecting`: the client sat on one
  /// silent socket forever and the gate reported `client never connected to the
  /// node` three minutes later. The node's own reaper (`PeerJobs`,
  /// `HANDSHAKE_TIMEOUT_MS` = 10 s) normally closes such a socket and the close
  /// unwedges us, so this only bites when that close never arrives: a node
  /// whose selector is wedged still completes the TCP handshake in the kernel
  /// backlog, and a link that dies mid-handshake swallows the FIN.
  ///
  /// 20 s is deliberately looser than the node's 10 s: the node should be the
  /// one to end a handshake it cannot finish, and this is the backstop for when
  /// it does not.
  ///
  /// The deadline covers the whole handshake including the key exchange: it
  /// only stops once transport encryption is active (TD274). A peer that is
  /// verified but stuck before its codec cannot carry commands, so it must not
  /// hold its slot forever either.
  static const Duration handshakeTimeout = Duration(seconds: 20);

  /// TEST SEAM (T156) — never set in production code.
  ///
  /// Unit suites drive the wire exchange in plaintext over a scripted socket
  /// and never complete the key exchange. With this flag the handshake ends at
  /// the magic again (as before T156): the peer counts as connected and
  /// [canSendCommands] right after it, and the handshake deadline stops there.
  /// A real node drops every plaintext command, so this must stay `false`
  /// outside tests. Each test file runs in its own isolate, so setting it in
  /// one suite does not leak into another.
  static bool plaintextTransportForTesting = false;

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
  static const int _cmdFlaschenpostV2 = 142;
  static const int _cmdOutboundRegisterOhReq = 150;
  static const int _cmdOutboundRegisterOhRes = 151;
  static const int _cmdOutboundFetchReq = 152;
  static const int _cmdOutboundFetchRes = 153;
  static const int _cmdOutboundAckFetchRes = 157;
  static const int _cmdFlaschenpostPutRes = 158;
  // Connection-Notify (T38): 159 (SubscribeReq) is outbound only. 160
  // (SubscribeRes) and 161 (Notify, one-way node → client) are inbound and
  // framed like every other outbound response: [CMD][len:4][protobuf].
  static const int _cmdOutboundSubscribeRes = 160;
  static const int _cmdOutboundNotify = 161;

  final String address;
  final NodeId selfNodeId;
  final KeyPair selfKeys;
  final SocketFactory socketFactory;
  final void Function(ConnectionStatus) onStatusChange;
  final void Function() onDisconnect;
  final void Function(List<DiscoveredPeer>)? onPeersReceived;
  final void Function(int latencyMs)? onLatencyUpdate;
  final void Function()? onHandshakeComplete;
  final List<String> Function()? onPeerListRequested;

  /// Called once the peer's identity is known: the KademliaId and the
  /// X25519 encryption public key (both hex) from the 64-byte public export.
  final void Function(String nodeId, String encryptionPublicKey)?
  onNodeIdDiscovered;

  /// KademliaId (hex) of this peer, set once its public key was received.
  String? discoveredNodeId;

  /// Consecutive fetch timeouts on THIS connection (T33), maintained by the
  /// client: incremented per fetch timeout, reset on any fetch response. A
  /// fresh connection starts at 0 by construction — the counter must never
  /// survive a reconnect.
  int consecutiveFetchTimeouts = 0;

  /// Callback for OH response commands (151, 153, 157, 158) and the
  /// Connection-Notify inbound commands (160 SubscribeRes, 161 Notify).
  void Function(int command, List<int> payload)? onCommandResponse;

  Socket? _socket;
  final List<int> _buffer = [];

  // State
  bool _handshakeVerified = false;
  Future<void>? _handshakeInitiationFuture;

  /// Active transport encryption (set after the v23 key exchange).
  GcmFramedCodec? _codec;

  /// Serializes inbound decryption + processing (frame counters and the
  /// parse buffer must be handled strictly in arrival order).
  Future<void> _rxChain = Future.value();

  /// Serializes outbound encryption + socket writes (frame counter order).
  Future<void> _txChain = Future.value();

  // Stats
  final DateTime connectedSince = DateTime.now();
  int averageLatencyMs = 9999;
  Stopwatch? _pingStopwatch;

  bool get isEncryptionActive => _codec != null;

  /// Whether payload commands ([sendCommand]) may be sent over this peer:
  /// connected AND transport encryption active (T156/TD273).
  ///
  /// [isHandshakeVerified] flips at the plaintext magic, before the key
  /// exchange has produced the codec. A command written in that window goes
  /// out in plaintext; the node reads its first bytes as a GCM frame length
  /// (e.g. 0x96… for REGISTER_OH) and drops the connection. Every caller that
  /// picks a peer to send a command over must gate on this, not on
  /// [isHandshakeVerified]. (A real node also requires the first encrypted
  /// command to be the PING sent from the key-exchange finalization, which
  /// is queued before this flips.)
  bool get canSendCommands =>
      _handshakeVerified && (_codec != null || plaintextTransportForTesting);
  bool get isPongSent => _pongSent;
  bool get isHandshakeVerified => _handshakeVerified;
  bool get isDisconnected => _socket == null && _isDisconnecting;
  bool _isDisconnecting = false; // Flag if we are logically disconnected

  /// The peer's 64-byte public export `[32 verifyKey][32 encPubKey]`.
  Uint8List? _peerPublicExport;

  /// Our ephemeral X25519 keypair for this connection's key exchange.
  X25519KeyPairBytes? _ephemeralFromUs;
  bool _pongSent = false;
  bool _isProcessingBuffer = false;

  /// Armed on a successful dial, cancelled once encryption is active
  /// ([_finalizeEncryption]) and by [_shutdown]. See [handshakeTimeout].
  Timer? _handshakeTimer;

  ActivePeer({
    required this.address,
    required this.selfNodeId,
    required this.selfKeys,
    required this.socketFactory,
    required this.onStatusChange,
    required this.onDisconnect,
    Duration? handshakeDeadline,
    this.onPeersReceived,
    this.onPeerListRequested,
    this.onLatencyUpdate,
    this.onHandshakeComplete,
    this.onNodeIdDiscovered,
  }) : _handshakeDeadline = handshakeDeadline ?? handshakeTimeout;

  /// [handshakeTimeout] unless overridden (tests only).
  final Duration _handshakeDeadline;

  Future<void> connect() async {
    try {
      final parts = address.split(':');
      final host = parts[0];
      final port = int.parse(parts[1]);

      RpLog.debug('ActivePeer($address): Connecting...');
      final socket = await socketFactory(host, port);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      // Armed before the handshake goes out: from here on the peer occupies a
      // slot in RedPandaLightClient._peers, and nothing else would ever give it
      // back if the node stays silent (see [handshakeTimeout]).
      _handshakeTimer = Timer(_handshakeDeadline, () {
        if (_codec != null || _isDisconnecting) return;
        RpLog.info(
          'ActivePeer($address): handshake/key exchange not complete within '
          '${_handshakeDeadline.inSeconds}s '
          '(verified=$_handshakeVerified) — dropping the connection',
        );
        _shutdown();
      });

      // Write failures (e.g. "connection reset by peer" during a send)
      // surface on socket.done, not on the read stream's onError handler.
      // Without a listener they become unhandled async errors that are
      // fatal for the surrounding isolate.
      unawaited(
        socket.done.catchError((Object e) {
          RpLog.debug('ActivePeer($address) socket write error: $e');
          _shutdown();
        }),
      );

      RpLog.debug('ActivePeer($address): TCP Connected. Sending Handshake...');
      _sendHandshake();

      _socket!.listen(
        _handleSocketData,
        onError: (e) {
          RpLog.debug('ActivePeer($address) socket error: $e');
          _shutdown();
        },
        onDone: () {
          RpLog.debug('ActivePeer($address) socket closed');
          _shutdown();
        },
      );
    } catch (e) {
      RpLog.debug('ActivePeer($address) connection failed: $e');
      _shutdown();
    }
  }

  void _shutdown() {
    if (_isDisconnecting) return;
    _isDisconnecting = true;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
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
    RpLog.debug(
      'ActivePeer($address): Handshake sent (${buffer.length} bytes)',
    );
  }

  void _handleSocketData(Uint8List data) {
    // Chain inbound chunks so async GCM frame decryption keeps the receive
    // counter and the parse buffer in strict arrival order.
    _rxChain = _rxChain
        .then((_) async {
          var processData = data;
          final codec = _codec;
          if (codec != null) {
            // Returns only the plaintext of complete frames; partial frames
            // stay buffered inside the codec.
            processData = await codec.decrypt(data);
          }
          _buffer.addAll(processData);

          if (!_isProcessingBuffer) {
            await _processBuffer();
          }
        })
        .catchError((Object e) {
          // Auth/framing failures must drop the connection (never deliver
          // silently corrupted plaintext).
          RpLog.debug('ActivePeer($address): inbound processing failed: $e');
          _shutdown();
        });
  }

  Future<void> _processBuffer() async {
    if (_isProcessingBuffer) return;
    _isProcessingBuffer = true;

    try {
      while (true) {
        // A shut-down peer parses nothing more. Without this, bytes still
        // queued on the rx chain at shutdown (>= 30 of them) went back
        // through the magic check — `_handshakeVerified` is reset by
        // [_shutdown] — whose failure path consumes nothing: a busy loop
        // that froze the isolate (found by the T156 shutdown test).
        if (_buffer.isEmpty || _isDisconnecting) break;

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
            RpLog.debug('ActivePeer($address): Received requestPublicKey');
            _buffer.removeAt(0);
            _sendPublicKey();
          } else if (command == _cmdActivateEncryption) {
            RpLog.debug('ActivePeer($address): Received activateEncryption');
            // v23: payload is the peer's 32-byte ephemeral X25519 key.
            if (_buffer.length < 1 + 32) {
              break;
            }

            if (_handshakeInitiationFuture != null) {
              await _handshakeInitiationFuture;
            }

            _buffer.removeAt(0);
            final ephemeralFromThem = _buffer.sublist(0, 32);
            _buffer.removeRange(0, 32);

            await _handlePeerEphemeralKey(
              Uint8List.fromList(ephemeralFromThem),
            );
          } else if (command == _cmdSendPublicKey) {
            RpLog.debug('ActivePeer($address): Received sendPublicKey');
            // v23: 64-byte export [32 verifyKey][32 encryptionPubKey].
            if (_buffer.length < 1 + KeyPair.publicKeyLength) {
              break;
            }
            _buffer.removeAt(0);
            final keyBytes = _buffer.sublist(0, KeyPair.publicKeyLength);
            _buffer.removeRange(0, KeyPair.publicKeyLength);

            await _parsePeerPublicKey(keyBytes);
          } else if (command == _cmdPing) {
            RpLog.debug(
              'ActivePeer($address): Received ping (Encrypted). Sending pong...',
            );
            _buffer.removeAt(0);
            _sendPong();
          } else if (command == _cmdPong) {
            RpLog.debug('ActivePeer($address): Received pong (Encrypted).');
            if (_pingStopwatch != null) {
              _pingStopwatch!.stop();
              final latency = _pingStopwatch!.elapsedMilliseconds;
              _updateLatency(latency);
              _pingStopwatch = null;
            }
            _buffer.removeAt(0);
          } else if (command == _cmdRequestPeerList) {
            RpLog.debug('ActivePeer($address): Received requestPeerList');
            _buffer.removeAt(0);
            if (onPeerListRequested != null) {
              final peers = onPeerListRequested!();
              sendPeerList(peers);
            }
          } else if (command == _cmdSendPeerList) {
            RpLog.debug('ActivePeer($address): Received sendPeerList');
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
              command == _cmdFlaschenpostV2 ||
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
              command == _cmdOutboundAckFetchRes ||
              command == _cmdFlaschenpostPutRes ||
              command == _cmdOutboundSubscribeRes ||
              command == _cmdOutboundNotify) {
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
            RpLog.debug(
              'ActivePeer($address): Unknown command byte: $command. Discarding.',
            );
            _buffer.removeAt(0);
          }
        }
      }
    } catch (e, stack) {
      RpLog.debug('ActivePeer($address): Error processing buffer: $e');
      RpLog.debug(stack.toString());
      _shutdown();
    } finally {
      _isProcessingBuffer = false;
    }
  }

  void _processHandshake() {
    final magicBytes = _buffer.sublist(0, 4);
    final magicVal = String.fromCharCodes(magicBytes);
    if (magicVal != _magic) {
      RpLog.debug('ActivePeer($address): Invalid magic. Disconnecting.');
      _shutdown();
      return;
    }

    RpLog.debug('ActivePeer($address): Handshake Verified.');
    _handshakeVerified = true;
    if (plaintextTransportForTesting) _reportConnected();
    // Otherwise the handshake timer keeps running and "connected" is only
    // reported once encryption is active (see [_finalizeEncryption]): the
    // client's connect edge immediately sends payload commands (subscribe,
    // catch-up poll), which must not go out before the codec exists (T156).

    _buffer.removeRange(0, _handshakeLength);

    RpLog.debug('ActivePeer($address): Requesting Peer Public Key...');
    _socket!.add([_cmdRequestPublicKey]);
  }

  void _sendPublicKey() {
    RpLog.debug('ActivePeer($address): Sending Public Key...');
    final buffer = BytesBuilder();
    buffer.addByte(_cmdSendPublicKey);
    buffer.add(selfKeys.publicKeyBytes);
    // Part of the plaintext handshake: must never be encrypted, even if the
    // codec got activated while this write was still queued on the tx chain.
    _sendData(buffer.toBytes(), forceUnencrypted: true);
  }

  Uint8List? _pendingEphemeralFromThem;

  Future<void> _parsePeerPublicKey(List<int> keyBytes) async {
    _peerPublicExport = Uint8List.fromList(keyBytes);
    RpLog.debug('ActivePeer($address): Peer Public Key Parsed.');

    // KademliaId = SHA256(verifyKey)[0..20] (master spec Decision 2); the
    // export's bytes 32..63 are the node's X25519 encryption public key
    // (needed for garlic hop selection, MS04).
    final nodeId = NodeId.fromPublicKeyBytes(Uint8List.fromList(keyBytes));
    discoveredNodeId = nodeId.toHex();
    onNodeIdDiscovered?.call(
      nodeId.toHex(),
      HEX.encode(keyBytes.sublist(32, 64)),
    );

    if (_ephemeralFromUs == null) {
      _handshakeInitiationFuture = _initiateEncryptionHandshake();
    }

    if (_pendingEphemeralFromThem != null) {
      RpLog.debug(
        'ActivePeer($address): Found pending encryption request. Finalizing now.',
      );
      final pending = _pendingEphemeralFromThem!;
      _pendingEphemeralFromThem = null;
      await _finalizeEncryption(pending);
    }
  }

  Future<void> _initiateEncryptionHandshake() async {
    if (_ephemeralFromUs != null) return; // Already initiated
    RpLog.debug('ActivePeer($address): Initiating Encryption Handshake...');
    _ephemeralFromUs = await CryptoUtils.generateEncryptionKeypair();
    // Small delay so this command does not coalesce into the same TCP
    // segment as the previous one (the node parses one handshake command
    // per read).
    await Future.delayed(const Duration(milliseconds: 100));
    final buffer = BytesBuilder();
    buffer.addByte(_cmdActivateEncryption);
    buffer.add(_ephemeralFromUs!.publicKey);
    _sendData(buffer.toBytes(), forceUnencrypted: true);
    RpLog.debug('ActivePeer($address): Sent activateEncryption request.');
  }

  Future<void> _handlePeerEphemeralKey(Uint8List ephemeralFromThem) async {
    if (_ephemeralFromUs == null) {
      _handshakeInitiationFuture = _initiateEncryptionHandshake();
      await _handshakeInitiationFuture;
    }
    await _finalizeEncryption(ephemeralFromThem);
  }

  Future<void> _finalizeEncryption(Uint8List ephemeralFromThem) async {
    try {
      if (_peerPublicExport == null) {
        RpLog.debug(
          'ActivePeer($address): Peer Public Key missing. Deferring encryption finalization.',
        );
        _pendingEphemeralFromThem = ephemeralFromThem;
        return;
      }
      if (_ephemeralFromUs == null) {
        RpLog.debug(
          'ActivePeer($address): Cannot activate encryption, missing self state.',
        );
        return;
      }

      RpLog.debug('ActivePeer($address): Finalizing Encryption...');
      // shared = X25519(our ephemeral, their ephemeral); per-direction keys
      // via HKDF with the sorted verify keys as salt. We initiated the TCP
      // connection, so we are the "client" of the v23 key schedule.
      final shared = await CryptoUtils.x25519(
        _ephemeralFromUs!.privateKey,
        ephemeralFromThem,
      );
      final codec = await GcmFramedCodec.deriveForInitiator(
        sharedSecret: shared,
        ourVerifyKey: selfKeys.verifyKeyBytes,
        theirVerifyKey: _peerPublicExport!.sublist(0, 32),
      );
      // Shut down while the key exchange was in flight (node closed, timer,
      // rotation, client disconnect): "disconnected" was already reported —
      // a late "connected" would wedge the client's aggregate status (T156).
      if (_isDisconnecting) return;
      _codec = codec;

      RpLog.debug('ActivePeer($address): Encryption Active!');
      // The server requires the first encrypted client command to be PING.
      RpLog.debug('ActivePeer($address): Sending Initial ping (Encrypted)...');
      _sendData([_cmdPing]);

      // Auto-bootstrap: Request Peer List
      RpLog.debug('ActivePeer($address): Requesting Peer List (Encrypted)...');
      requestPeerList();

      // Handshake complete: stop the deadline (TD274) and report the peer as
      // connected. Only now may payload commands be sent ([canSendCommands]);
      // the PING above is already queued first on the tx chain.
      _reportConnected();

      if (_buffer.isNotEmpty) {
        // Bytes after ACTIVATE_ENCRYPTION in the same segment are already
        // GCM frames — run them through the codec.
        final remaining = Uint8List.fromList(_buffer);
        _buffer.clear();
        final decrypted = await _codec!.decrypt(remaining);
        _buffer.addAll(decrypted);
        RpLog.debug('ActivePeer($address): Decrypted residual bytes.');
      }
    } catch (e, stack) {
      RpLog.debug('ActivePeer($address): Error activating encryption: $e');
      RpLog.debug(stack.toString());
      _shutdown();
    }
  }

  bool _connectedReported = false;

  /// Ends the handshake: stops the deadline (TD274), scores the peer as a
  /// success and reports "connected" — once per connection.
  void _reportConnected() {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    if (_connectedReported || _isDisconnecting) return;
    _connectedReported = true;
    onHandshakeComplete?.call();
    onStatusChange(ConnectionStatus.connected);
  }

  void _sendPong() {
    RpLog.debug('ActivePeer($address): Sending pong...');
    _sendData([_cmdPong]);
    _pongSent = true;
  }

  /// Sends a ping to measure latency.
  ///
  /// No-op until transport encryption is active. Callers (the 3 s connection
  /// check) gate on [isHandshakeVerified], which flips right after the
  /// plaintext magic — long before the key exchange has produced [_codec].
  /// A PING written in that window would go out in plaintext; the node reads
  /// it as the first GCM frame (`invalid GCM frame length: 83886080` =
  /// 0x05000000) and drops the connection (T153). Guarding here rather than
  /// in the connection check covers every caller of the latency ping.
  /// [sendCommand] callers gate on [canSendCommands] instead (T156). The codec
  /// is checked at call time: once it is set, [_sendData] encrypts everything
  /// queued after it.
  void ping() {
    if (_codec == null) return; // Encryption not active yet (T153)
    if (_pingStopwatch != null) return; // Already pinging
    RpLog.debug('ActivePeer($address): Sending Ping (Latency Check)...');
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
    RpLog.debug(
      'ActivePeer($address): Latency updated to ${averageLatencyMs}ms (current: ${latency}ms)',
    );
    onLatencyUpdate?.call(averageLatencyMs);
  }

  void _sendData(List<int> data, {bool forceUnencrypted = false}) {
    if (_socket == null) return;
    // Chain writes so async GCM frame encryption keeps the send counter and
    // the byte order on the socket consistent.
    _txChain = _txChain
        .then((_) async {
          final socket = _socket;
          if (socket == null) return;
          Uint8List output;
          final codec = _codec;
          if (codec != null && !forceUnencrypted) {
            output = await codec.encrypt(data);
          } else {
            output = Uint8List.fromList(data);
          }
          socket.add(output);
        })
        .catchError((Object e) {
          RpLog.debug('ActivePeer($address): outbound processing failed: $e');
          _shutdown();
        });
  }

  void requestPeerList() {
    _sendData([_cmdRequestPeerList]);
  }

  /// Sends a command with [CMD][4 length big-endian][protobuf bytes].
  ///
  /// Callers must only pick peers with [canSendCommands] (T156). There is no
  /// pre-encryption queue here: deferring or dropping writes on a live peer
  /// would desync the client's FIFO response matching. (A write to a peer
  /// that has meanwhile shut down is still lost, as before.)
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
    RpLog.debug('ActivePeer($address): Sending Peer List (${peers.length})...');
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
        RpLog.debug('ActivePeer($address): Error parsing peer for send: $p');
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
      final peers = <DiscoveredPeer>[];
      for (final peerProto in msg.peers) {
        if (peerProto.ip.isEmpty || peerProto.port <= 0) continue;
        final peerAddr = '${peerProto.ip}:${peerProto.port}';

        // MS04: extract the peer's identity if included. The KademliaId is
        // derived from the 64-byte public export; the encryption key comes
        // from the explicit field 4 with a fallback to bytes 32..63 of the
        // export (Decision 10: the two are redundant).
        String? nodeId;
        String? encryptionKey;
        final export = peerProto.hasNodeId()
            ? peerProto.nodeId.publicKeyBytes
            : const <int>[];
        if (export.length == KeyPair.publicKeyLength) {
          nodeId = NodeId.fromPublicKeyBytes(
            Uint8List.fromList(export),
          ).toHex();
          encryptionKey = HEX.encode(export.sublist(32, 64));
        }
        if (peerProto.encryptionPublicKey.length == CryptoUtils.keyLength) {
          encryptionKey = HEX.encode(peerProto.encryptionPublicKey);
        }

        peers.add(
          DiscoveredPeer(
            address: peerAddr,
            nodeId: nodeId,
            encryptionPublicKey: encryptionKey,
          ),
        );
      }
      onPeersReceived?.call(peers);
    } catch (e) {
      RpLog.debug('ActivePeer($address): Failed to parse peer list: $e');
    }
  }
}
