import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// A scripted in-memory Socket: captures client writes and lets the test
/// inject node responses. The exchange stays in plaintext because the
/// encryption handshake is never completed — command framing is identical.
class ScriptedSocket implements Socket {
  @override
  Future<void> get done => Completer<void>().future;

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
Future<(RedPandaLightClient, ScriptedSocket)> connectedClient() async {
  final socket = ScriptedSocket();
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: ['scripted:1'],
    socketFactory: (h, p) async => socket,
  );
  await client.connect();
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (client.activePeerAddresses.isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('peer never became handshake-verified');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return (client, socket);
}

/// Scripted node behavior for the loopback flow: answers OH registrations
/// (150) with OK, deposits (141) with OK while capturing their content, and
/// fetches (152) with every payload deposited so far (delivered once,
/// while [deliverOnFetch] is true).
class LoopbackNodeScript {
  final ScriptedSocket socket;
  bool deliverOnFetch;
  int deposits = 0;
  final _mailbox = <List<int>>[];
  var _cursor = 0;

  LoopbackNodeScript(this.socket, {required this.deliverOnFetch}) {
    socket.onCommandFrame = _handle;
  }

  void _handle(int command, Uint8List payload) {
    if (command == 150) {
      final response = RegisterOhResponse()..status = Status.OK;
      socket.replyCommand(151, response.writeToBuffer());
    } else if (command == 141) {
      final put = FlaschenpostPut.fromBuffer(payload);
      _mailbox.add(put.content);
      deposits++;
      final response = FlaschenpostPutResponse()..status = Status.OK;
      socket.replyCommand(158, response.writeToBuffer());
    } else if (command == 152) {
      final response = FetchResponse()..status = Status.OK;
      if (deliverOnFetch) {
        for (final content in _mailbox) {
          _cursor++;
          response.items.add(
            MailItem()
              ..payload = content
              ..receivedAtMs = fixnum.Int64(
                DateTime.now().millisecondsSinceEpoch,
              ),
          );
        }
        _mailbox.clear();
      }
      response.nextCursor = fixnum.Int64(_cursor);
      socket.replyCommand(153, response.writeToBuffer());
    }
  }
}

void main() {
  group('T20 runLoopbackTest', () {
    test('round trip: deposit comes back via fetch, never surfaces as a '
        'chat message', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      LoopbackNodeScript(socket, deliverOnFetch: true);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: channel.id);

      final incoming = <DecryptedMessage>[];
      final sub = client.incomingMessages.listen(incoming.add);
      addTearDown(sub.cancel);

      final result = await client.runLoopbackTest(channel.id);

      expect(result.success, isTrue, reason: 'error: ${result.error}');
      expect(result.roundtripMs, isNotNull);
      // No other peers are known to the hop selector — direct deposit.
      expect(result.hopCount, equals(0));

      // The test message must have been swallowed by the fetch pipeline.
      await Future.delayed(const Duration(milliseconds: 100));
      expect(incoming, isEmpty);
    });

    test('no own mailbox → failure result, nothing sent', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      final node = LoopbackNodeScript(socket, deliverOnFetch: true);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
      );
      // No registerOutboundHandle — the channel has no own mailbox.

      final result = await client.runLoopbackTest(channel.id);

      expect(result.success, isFalse);
      expect(result.error, contains('no own mailbox'));
      expect(node.deposits, equals(0));
    });

    test('message never comes back → timeout failure; a late arrival is '
        'still swallowed', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);
      // Deposits are accepted but fetches return an empty mailbox.
      final node = LoopbackNodeScript(socket, deliverOnFetch: false);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: channel.id);

      final incoming = <DecryptedMessage>[];
      final sub = client.incomingMessages.listen(incoming.add);
      addTearDown(sub.cancel);

      final result = await client.runLoopbackTest(
        channel.id,
        timeout: const Duration(milliseconds: 500),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('not received within'));

      // The node starts delivering only after the test already timed out:
      // the late test message must be swallowed, not shown as a chat
      // message. The second loopback run triggers the poll that flushes
      // both the stale and the fresh test message.
      node.deliverOnFetch = true;
      final missed = await client.runLoopbackTest(
        channel.id,
        timeout: const Duration(seconds: 10),
      );
      expect(missed.success, isTrue);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(incoming, isEmpty);
    });
  });
}
