import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:redpanda_light_client/src/security/gcm_framed_codec.dart';
import 'package:test/test.dart';

/// In-memory socket that emulates a v23 full node: magic handshake,
/// 64-byte public key exchange, ephemeral X25519 + HKDF key schedule and
/// framed AES-256-GCM transport. Lets tests observe the client's encrypted
/// frames and inject (optionally tampered) server frames.
class ScriptedV23Server implements Socket {
  @override
  Future<void> get done => Completer<void>().future;

  final _incoming = StreamController<Uint8List>();
  final List<int> _outBuffer = [];

  late final KeyPair serverKeys;
  late final X25519KeyPairBytes _serverEphemeral;
  Uint8List? clientVerifyKey;
  Uint8List? clientEphemeral;

  /// Server-side transport codec (set once the key exchange completed).
  GcmFramedCodec? codec;

  bool _handshakeAnswered = false;
  bool _publicKeySent = false;
  bool _activateSent = false;

  /// Decrypted plaintext commands received from the client after encryption.
  final List<int> decryptedFromClient = [];

  /// Raw bytes of the first encrypted frame sent to the client (the PING
  /// with counter nonce 0) — kept for replay tests.
  Uint8List? firstSentFrame;

  /// Completes when the server has decrypted the client's first encrypted
  /// command (must be PING = 5).
  final firstEncryptedCommand = Completer<int>();

  /// Async chain so decryption keeps frame order.
  Future<void> _chain = Future.value();

  static Future<ScriptedV23Server> create() async {
    final server = ScriptedV23Server._();
    server.serverKeys = await KeyPair.generate();
    server._serverEphemeral = await CryptoUtils.generateEncryptionKeypair();
    return server;
  }

  ScriptedV23Server._();

  void _reply(List<int> data) {
    if (!_incoming.isClosed) {
      _incoming.add(Uint8List.fromList(data));
    }
  }

  /// Encrypts [plaintext] with the server codec and injects it.
  Future<void> replyEncrypted(List<int> plaintext) async {
    final frame = await codec!.encrypt(plaintext);
    firstSentFrame ??= frame;
    _reply(frame);
  }

  @override
  void add(List<int> data) {
    _chain = _chain.then((_) => _consume(data));
  }

  Future<void> _consume(List<int> data) async {
    _outBuffer.addAll(data);

    if (!_handshakeAnswered) {
      if (_outBuffer.length < 30) return;
      // client magic handshake: 4 magic, 1 version, 1 type, 20 id, 4 port
      expect(String.fromCharCodes(_outBuffer.sublist(0, 4)), equals('k3gV'));
      expect(_outBuffer[4], equals(23), reason: 'protocol version must be 23');
      expect(_outBuffer[5], equals(160), reason: 'light client marker');
      _outBuffer.removeRange(0, 30);
      _handshakeAnswered = true;

      // Server's own 30-byte handshake.
      final b = BytesBuilder();
      b.add('k3gV'.codeUnits);
      b.addByte(23);
      b.addByte(0);
      b.add(NodeId.fromPublicKey(serverKeys).bytes);
      b.add(Uint8List(4));
      _reply(b.toBytes());
    }

    while (_outBuffer.isNotEmpty) {
      if (codec != null) {
        // Everything from now on are GCM frames.
        final plaintext = await codec!.decrypt(Uint8List.fromList(_outBuffer));
        _outBuffer.clear();
        if (plaintext.isNotEmpty && !firstEncryptedCommand.isCompleted) {
          firstEncryptedCommand.complete(plaintext.first);
        }
        decryptedFromClient.addAll(plaintext);
        return;
      }

      final command = _outBuffer[0];
      if (command == 1) {
        // REQUEST_PUBLIC_KEY → send ours, and ask for the client's key
        // (the node does not know light-client identities).
        _outBuffer.removeAt(0);
        if (!_publicKeySent) {
          _publicKeySent = true;
          _reply([2, ...serverKeys.publicKeyBytes]);
          _reply([1]);
        }
      } else if (command == 2) {
        // SEND_PUBLIC_KEY + 64-byte export from the client
        if (_outBuffer.length < 1 + 64) return;
        clientVerifyKey = Uint8List.fromList(_outBuffer.sublist(1, 33));
        _outBuffer.removeRange(0, 65);
        await _maybeActivate();
      } else if (command == 3) {
        // ACTIVATE_ENCRYPTION + 32-byte ephemeral X25519 key
        if (_outBuffer.length < 1 + 32) return;
        clientEphemeral = Uint8List.fromList(_outBuffer.sublist(1, 33));
        _outBuffer.removeRange(0, 33);
        await _maybeActivate();
      } else {
        _outBuffer.removeAt(0);
      }
    }
  }

  Future<void> _maybeActivate() async {
    if (clientVerifyKey == null || clientEphemeral == null) return;
    if (!_activateSent) {
      _activateSent = true;
      _reply([3, ..._serverEphemeral.publicKey]);
    }

    // Derive the server-side key schedule.
    final shared = await CryptoUtils.x25519(
      _serverEphemeral.privateKey,
      clientEphemeral!,
    );
    final serverVerify = serverKeys.verifyKeyBytes;
    final ourIsMin =
        CryptoUtils.compareUnsigned(clientVerifyKey!, serverVerify) <= 0;
    final minKey = ourIsMin ? clientVerifyKey! : serverVerify;
    final maxKey = ourIsMin ? serverVerify : clientVerifyKey!;
    final clientKey = await CryptoUtils.hkdfSha256(
      shared,
      minKey,
      'tcp-client',
      32,
    );
    final serverKey = await CryptoUtils.hkdfSha256(
      shared,
      maxKey,
      'tcp-server',
      32,
    );
    codec = GcmFramedCodec(sendKey: serverKey, receiveKey: clientKey);

    // Like the real node: send the first encrypted PING.
    await replyEncrypted([5]);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _incoming.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  void destroy() {
    _incoming.close();
  }

  @override
  Future<void> close() async {
    _incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(ActivePeer, ScriptedV23Server, List<ConnectionStatus>)> connect({
  void Function()? onDisconnect,
}) async {
  final server = await ScriptedV23Server.create();
  final keys = await KeyPair.generate();
  final statuses = <ConnectionStatus>[];
  final peer = ActivePeer(
    address: 'scripted:23',
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    socketFactory: (h, p) async => server,
    onStatusChange: statuses.add,
    onDisconnect: onDisconnect ?? () {},
  );
  await peer.connect();
  return (peer, server, statuses);
}

Future<void> waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('TCP handshake v23 (framed AES-256-GCM)', () {
    test('completes the key exchange and activates encryption', () async {
      final (peer, server, _) = await connect();

      await waitFor(() => peer.isEncryptionActive);
      expect(server.codec, isNotNull);
      expect(server.clientVerifyKey, hasLength(32));
      expect(server.clientEphemeral, hasLength(32));
    });

    test('first encrypted client command is PING', () async {
      final (_, server, _) = await connect();

      final first = await server.firstEncryptedCommand.future.timeout(
        const Duration(seconds: 5),
      );
      expect(first, equals(5));
    });

    test('encrypted ping/pong roundtrip works', () async {
      final (peer, server, _) = await connect();
      await waitFor(() => peer.isEncryptionActive);

      // Wait until the server saw the client's initial PING, then check the
      // client answers an encrypted server PING with an encrypted PONG.
      await server.firstEncryptedCommand.future;
      final before = server.decryptedFromClient.length;
      await server.replyEncrypted([5]);
      await waitFor(() => server.decryptedFromClient.length > before);
      expect(server.decryptedFromClient.sublist(before), contains(6));
    });

    test('a tampered GCM frame disconnects the client', () async {
      var disconnected = false;
      final (peer, server, _) = await connect(
        onDisconnect: () => disconnected = true,
      );
      await waitFor(() => peer.isEncryptionActive);
      await server.firstEncryptedCommand.future;

      // Encrypt a valid frame, then flip one ciphertext bit.
      final frame = await server.codec!.encrypt([5]);
      frame[frame.length - 1] ^= 0x01;
      server._reply(frame);

      await waitFor(() => disconnected);
      expect(peer.isDisconnected, isTrue);
    });

    test('a replayed server frame disconnects the client', () async {
      var disconnected = false;
      final (peer, server, _) = await connect(
        onDisconnect: () => disconnected = true,
      );
      await waitFor(() => peer.isEncryptionActive);
      await server.firstEncryptedCommand.future;

      // Replay the *exact* bytes of the server's first frame (valid GCM tag
      // for counter nonce 0). The client already consumed counter 0, so only
      // the receiver-enforced counter check can reject this — if the counter
      // enforcement were removed, the frame would decrypt successfully.
      final replayedFrame = server.firstSentFrame!;
      server._reply(replayedFrame);

      await waitFor(() => disconnected);
      expect(peer.isDisconnected, isTrue);
    });
  });
}
