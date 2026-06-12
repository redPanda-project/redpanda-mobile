import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';

/// A scripted in-memory Socket: captures client writes and lets the test
/// inject node responses. The exchange stays in plaintext because the
/// encryption handshake is never completed — command framing is identical.
class ScriptedSocket implements Socket {
  final _incoming = StreamController<Uint8List>();
  final List<int> _outBuffer = [];
  bool _handshakeAnswered = false;

  /// Called for every complete [cmd][len][payload] frame the client sends.
  void Function(int command, Uint8List payload)? onCommandFrame;

  /// Node handshake: MAGIC(4) + VER(1) + TYPE(1) + NODEID(20) + PORT(4).
  static Uint8List nodeHandshake() {
    final b = BytesBuilder();
    b.add('k3gV'.codeUnits);
    b.addByte(22);
    b.addByte(0);
    b.add(Uint8List(20));
    b.add(Uint8List(4));
    return b.toBytes();
  }

  /// Injects node → client bytes.
  void reply(List<int> data) {
    if (!_incoming.isClosed) {
      _incoming.add(Uint8List.fromList(data));
    }
  }

  /// Injects a [cmd][len][protobuf] response frame.
  void replyCommand(int command, List<int> protobufBytes) {
    final b = BytesBuilder();
    b.addByte(command);
    final len = ByteData(4)..setInt32(0, protobufBytes.length, Endian.big);
    b.add(len.buffer.asUint8List());
    b.add(protobufBytes);
    reply(b.toBytes());
  }

  @override
  void add(List<int> data) {
    _outBuffer.addAll(data);
    _drainOutBuffer();
  }

  void _drainOutBuffer() {
    // First the 30-byte client handshake, answered with the node handshake.
    if (!_handshakeAnswered) {
      if (_outBuffer.length < 30) return;
      _outBuffer.removeRange(0, 30);
      _handshakeAnswered = true;
      reply(nodeHandshake());
    }
    // Then a plaintext command stream: 1-byte commands (requestPublicKey,
    // ping, ...) are skipped, framed commands are reported to the test.
    while (_outBuffer.isNotEmpty) {
      final command = _outBuffer[0];
      if (command == 141 ||
          command == 150 ||
          command == 152 ||
          command == 156) {
        if (_outBuffer.length < 5) return;
        final len = ByteData.sublistView(
          Uint8List.fromList(_outBuffer.sublist(1, 5)),
        ).getInt32(0, Endian.big);
        if (_outBuffer.length < 5 + len) return;
        final payload = Uint8List.fromList(_outBuffer.sublist(5, 5 + len));
        _outBuffer.removeRange(0, 5 + len);
        onCommandFrame?.call(command, payload);
      } else {
        _outBuffer.removeAt(0);
      }
    }
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

/// Client wired to a [ScriptedSocket]; waits until the peer is verified.
Future<(RedPandaLightClient, ScriptedSocket)> connectedClient({
  Duration depositResponseTimeout = const Duration(seconds: 10),
}) async {
  final socket = ScriptedSocket();
  final keys = KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: ['scripted:1'],
    socketFactory: (h, p) async => socket,
    depositResponseTimeout: depositResponseTimeout,
  );
  await client.connect();
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (client.activePeerAddresses.isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('peer never became handshake-verified');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return (client, socket);
}

void main() {
  group('MS02b protobuf: FlaschenpostPut want_response / hop_count', () {
    test('roundtrips fields 3 and 4 and stays wire-compatible', () {
      final put = FlaschenpostPut()
        ..content = [1, 2, 3]
        ..ohId = List.generate(20, (i) => i)
        ..wantResponse = true
        ..hopCount = 2;

      final decoded = FlaschenpostPut.fromBuffer(put.writeToBuffer());
      expect(decoded.wantResponse, isTrue);
      expect(decoded.hopCount, equals(2));
      expect(decoded.ohId, equals(List.generate(20, (i) => i)));
    });

    test('pre-MS02b buffer (content + oh_id only) parses with defaults', () {
      final legacy = FlaschenpostPut()
        ..content = [9, 9]
        ..ohId = List.generate(20, (i) => 7);

      final decoded = FlaschenpostPut.fromBuffer(legacy.writeToBuffer());
      expect(decoded.wantResponse, isFalse);
      expect(decoded.hopCount, equals(0));
    });

    test('FlaschenpostPutResponse roundtrips status and server time', () {
      final response = FlaschenpostPutResponse()
        ..status = Status.QUOTA_EXCEEDED
        ..serverTimeMs = fixnum.Int64(1234567890);

      final decoded = FlaschenpostPutResponse.fromBuffer(
        response.writeToBuffer(),
      );
      expect(decoded.status, equals(Status.QUOTA_EXCEEDED));
      expect(decoded.serverTimeMs.toInt(), equals(1234567890));
    });
  });

  group('MS02b ActivePeer: command 158 dispatch', () {
    test(
      'forwards FlaschenpostPutResponse payload to onCommandResponse',
      () async {
        final socket = ScriptedSocket();
        final keys = KeyPair.generate();
        final received = <(int, List<int>)>[];

        final peer = ActivePeer(
          address: 'scripted:1',
          selfNodeId: NodeId.fromPublicKey(keys),
          selfKeys: keys,
          socketFactory: (h, p) async => socket,
          onStatusChange: (_) {},
          onDisconnect: () {},
        );
        peer.onCommandResponse = (command, payload) {
          received.add((command, payload));
        };

        await peer.connect();
        await Future.delayed(const Duration(milliseconds: 50));
        expect(peer.isHandshakeVerified, isTrue);

        final response = FlaschenpostPutResponse()..status = Status.OK;
        socket.replyCommand(158, response.writeToBuffer());
        await Future.delayed(const Duration(milliseconds: 50));

        expect(received, hasLength(1));
        expect(received.single.$1, equals(158));
        final decoded = FlaschenpostPutResponse.fromBuffer(received.single.$2);
        expect(decoded.status, equals(Status.OK));
      },
    );
  });

  group('MS02b sendMessage: deposit response handling', () {
    Future<void> respondToDeposit(ScriptedSocket socket, Status status) async {
      socket.onCommandFrame = (command, payload) {
        if (command != 141) return;
        final put = FlaschenpostPut.fromBuffer(payload);
        expect(put.wantResponse, isTrue);
        final response = FlaschenpostPutResponse()..status = status;
        socket.replyCommand(158, response.writeToBuffer());
      };
    }

    test('OK response resolves with the message id', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      await respondToDeposit(socket, Status.OK);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(channel.id, channel.encryptionKey);

      final messageId = await client.sendMessage(channel.id, 'Hello');
      expect(messageId, hasLength(32)); // 16 bytes hex-encoded
    });

    test('QUOTA_EXCEEDED throws DepositException(quotaExceeded)', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      await respondToDeposit(socket, Status.QUOTA_EXCEEDED);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(channel.id, channel.encryptionKey);

      await expectLater(
        client.sendMessage(channel.id, 'Hello'),
        throwsA(
          isA<DepositException>().having(
            (e) => e.isQuotaExceeded,
            'isQuotaExceeded',
            isTrue,
          ),
        ),
      );
    });

    test('BAD_REQUEST throws DepositException(badRequest)', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      await respondToDeposit(socket, Status.BAD_REQUEST);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(channel.id, channel.encryptionKey);

      await expectLater(
        client.sendMessage(channel.id, 'Hello'),
        throwsA(
          isA<DepositException>().having(
            (e) => e.isBadRequest,
            'isBadRequest',
            isTrue,
          ),
        ),
      );
    });

    test('no response falls back to fire-and-forget (legacy node)', () async {
      final (client, _) = await connectedClient(
        depositResponseTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(client.disconnect);
      // The node never answers — pre-MS02b behavior must be preserved.

      final channel = await Channel.generate('Test');
      client.addChannelKeys(channel.id, channel.encryptionKey);

      final messageId = await client.sendMessage(channel.id, 'Hello');
      expect(messageId, hasLength(32));
    });

    test('a response arriving after the timeout is not misattributed to the '
        'next deposit', () async {
      final (client, socket) = await connectedClient(
        depositResponseTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(client.disconnect);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(channel.id, channel.encryptionKey);

      // First deposit: the node answers QUOTA_EXCEEDED, but only after the
      // client already gave up waiting.
      var deposits = 0;
      socket.onCommandFrame = (command, payload) {
        if (command != 141) return;
        deposits++;
        if (deposits == 1) {
          Future.delayed(const Duration(milliseconds: 400), () {
            final late = FlaschenpostPutResponse()
              ..status = Status.QUOTA_EXCEEDED;
            socket.replyCommand(158, late.writeToBuffer());
          });
        } else {
          final response = FlaschenpostPutResponse()..status = Status.OK;
          socket.replyCommand(158, response.writeToBuffer());
        }
      };

      // Times out and falls back to fire-and-forget.
      await client.sendMessage(channel.id, 'First');

      // Let the stale QUOTA_EXCEEDED arrive before the next deposit.
      await Future.delayed(const Duration(milliseconds: 400));

      // The second deposit must see ITS response (OK), not the stale one.
      final messageId = await client.sendMessage(channel.id, 'Second');
      expect(messageId, hasLength(32));
    });
  });

  group('MS02b registerOutboundHandle: RegisterOhResponse handling', () {
    test('RATE_LIMIT throws RateLimitException', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      socket.onCommandFrame = (command, payload) {
        if (command != 150) return;
        final response = RegisterOhResponse()..status = Status.RATE_LIMIT;
        socket.replyCommand(151, response.writeToBuffer());
      };

      await expectLater(
        client.registerOutboundHandle(channelId: 'test'),
        throwsA(isA<RateLimitException>()),
      );
      expect(client.registeredOutboundHandles, isEmpty);
    });

    test('OK response adopts the server-side expiry', () async {
      final serverExpiry = DateTime.now()
          .add(const Duration(days: 3))
          .millisecondsSinceEpoch;
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      socket.onCommandFrame = (command, payload) {
        if (command != 150) return;
        final response = RegisterOhResponse()
          ..status = Status.OK
          ..expiresAtMs = fixnum.Int64(serverExpiry);
        socket.replyCommand(151, response.writeToBuffer());
      };

      final registration = await client.registerOutboundHandle(
        channelId: 'test',
      );
      expect(registration.expiresAtMs, equals(serverExpiry));
    });
  });
}
