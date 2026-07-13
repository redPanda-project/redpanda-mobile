import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

import '../helpers/garlic_test_utils.dart';

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

  static Uint8List nodeHandshake() {
    final b = BytesBuilder();
    b.add('k3gV'.codeUnits);
    b.addByte(22);
    b.addByte(0);
    b.add(Uint8List(20));
    b.add(Uint8List(4));
    return b.toBytes();
  }

  void reply(List<int> data) {
    if (!_incoming.isClosed) {
      _incoming.add(Uint8List.fromList(data));
    }
  }

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
    if (!_handshakeAnswered) {
      if (_outBuffer.length < 30) return;
      _outBuffer.removeRange(0, 30);
      _handshakeAnswered = true;
      reply(nodeHandshake());
    }
    // Plaintext command stream: 1-byte commands are skipped, framed
    // commands (deposit 141, flaschenpost v2 142) are reported to the test.
    while (_outBuffer.isNotEmpty) {
      final command = _outBuffer[0];
      if (command == 141 || command == 142) {
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

void main() {
  final ohId = List<int>.generate(20, (i) => 200 - i);

  /// Builds a connected client whose peer repository already knows
  /// [hopCount] relay candidates (returned with their private keys).
  Future<(RedPandaLightClient, ScriptedSocket, List<TestHop>)> setupClient({
    int hopCount = 3,
    String? peerOhEndpoint,
    TestHop? ohHostHop,
  }) async {
    final hops = <TestHop>[];
    final repo = InMemoryPeerRepository();
    for (var i = 0; i < hopCount; i++) {
      final hop = await TestHop.generate(i + 1);
      hops.add(hop);
      repo.updatePeer(
        '10.1.0.$i:5000',
        nodeId: HEX.encode(hop.nodeId),
        encryptionPublicKey: HEX.encode(hop.keys.publicKey),
      );
    }
    if (ohHostHop != null && peerOhEndpoint != null) {
      repo.updatePeer(
        peerOhEndpoint,
        nodeId: HEX.encode(ohHostHop.nodeId),
        encryptionPublicKey: HEX.encode(ohHostHop.keys.publicKey),
      );
    }

    final socket = ScriptedSocket();
    final keys = await KeyPair.generate();
    final client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: ['scripted:1'],
      // Only the scripted node is reachable; the relay candidates are
      // known peers, not open connections.
      socketFactory: (h, p) async {
        if ('$h:$p' != 'scripted:1') {
          throw const SocketException('unreachable in this test');
        }
        return socket;
      },
      peerRepository: repo,
    );
    await client.connect();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (client.activePeerAddresses.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('peer never became handshake-verified');
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return (client, socket, hops);
  }

  /// Outbound frames travel an async tx chain; poll until [condition] holds.
  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('expected frame was never written to the socket');
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<Channel> channelWithKeys(
    RedPandaLightClient client, {
    String? peerOhEndpoint,
  }) async {
    final channel = await Channel.generate('MS04');
    client.addChannelKeys(
      channel.id,
      channel.encryptionKey,
      peerOhId: ohId,
      peerOhEndpoint: peerOhEndpoint,
      isChannelCreator: true,
    );
    return channel;
  }

  /// Peels all layers of [packet] like the relays would and returns the
  /// deliver payload. Fails if a layer is not addressed to a known hop.
  Future<(Uint8List payload, List<TestHop> path)> peelAll(
    Uint8List packet,
    List<TestHop> hops,
  ) async {
    final path = <TestHop>[];
    while (true) {
      final parsed = ParsedPacket.parse(packet);
      final hop = hops.firstWhere(
        (h) => HEX.encode(h.nodeId) == HEX.encode(parsed.nextHop),
        orElse: () => fail('next_hop is not one of the known relays'),
      );
      path.add(hop);
      final plaintext = await parsed.decryptLayer(hop.keys.privateKey);
      if (plaintext[0] == GarlicBuilder.cmdForward) {
        packet = GarlicBuilder.buildPacket(
          plaintext.sublist(1, 21),
          plaintext.sublist(21),
        );
        continue;
      }
      expect(plaintext[0], GarlicBuilder.cmdDeliver);
      expect(plaintext.sublist(1, 21), equals(ohId));
      final payloadLen = ByteData.sublistView(plaintext).getUint32(21);
      return (Uint8List.fromList(plaintext.sublist(25, 25 + payloadLen)), path);
    }
  }

  group('MS04 sendMessage: garlic routing', () {
    test('emits one 2048-byte FLASCHENPOST_V2 frame over 3 distinct hops; '
        'the deliver payload decrypts with the channel ratchet', () async {
      final (client, socket, hops) = await setupClient();
      addTearDown(client.disconnect);

      final frames = <(int, Uint8List)>[];
      socket.onCommandFrame = (cmd, payload) => frames.add((cmd, payload));

      final channel = await channelWithKeys(client);
      final messageId = await client.sendMessage(channel.id, 'Garlic hello!');
      expect(messageId, hasLength(32));

      await waitFor(() => frames.isNotEmpty);
      expect(frames, hasLength(1));
      expect(frames.single.$1, equals(142), reason: 'no direct deposit');
      expect(client.lastSendHopCount, 3);

      final packet = frames.single.$2;
      expect(packet.length, GarlicBuilder.packetSize);

      final (payload, path) = await peelAll(packet, hops);
      expect(path.map((h) => HEX.encode(h.nodeId)).toSet(), hasLength(3));
      expect(payload[0], MessageCryptoV4.version);

      // Bob's side of the ratchet can decrypt the deliver payload.
      final bobSession = await RatchetSession.create(
        channelKey: channel.encryptionKey,
        isChannelCreator: false,
      );
      final message = await bobSession.decrypt(payload, channel.id);
      expect(message.content, 'Garlic hello!');
      expect(HEX.encode(message.messageId), messageId);
    });

    test('destination OH endpoint is never picked as a hop', () async {
      final ohHost = await TestHop.generate(99);
      final (client, socket, regularHops) = await setupClient(
        hopCount: 3,
        peerOhEndpoint: '10.9.9.9:5000',
        ohHostHop: ohHost,
      );
      addTearDown(client.disconnect);

      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };

      final channel = await channelWithKeys(
        client,
        peerOhEndpoint: '10.9.9.9:5000',
      );

      // The hop pool holds 3 regular relays + the OH host. Across several
      // sends, peeling with the regular relays ALONE must always reach
      // CMD_DELIVER — i.e. the OH host never appears on any layer.
      for (var i = 0; i < 5; i++) {
        await client.sendMessage(channel.id, 'try $i');
        await waitFor(() => frames.length == i + 1);
      }
      expect(frames, hasLength(5));
      for (final packet in frames) {
        final (_, path) = await peelAll(packet, regularHops);
        expect(path, hasLength(3));
        expect(
          path.map((h) => HEX.encode(h.nodeId)),
          isNot(contains(HEX.encode(ohHost.nodeId))),
        );
      }
    });

    test('with fewer than 3 candidates the path degrades gracefully', () async {
      final (client, socket, hops) = await setupClient(hopCount: 2);
      addTearDown(client.disconnect);

      final frames = <(int, Uint8List)>[];
      socket.onCommandFrame = (cmd, payload) => frames.add((cmd, payload));

      final channel = await channelWithKeys(client);
      await client.sendMessage(channel.id, 'Two hops');

      await waitFor(() => frames.isNotEmpty);
      expect(frames.single.$1, 142);
      expect(client.lastSendHopCount, 2);
      final (_, path) = await peelAll(frames.single.$2, hops);
      expect(path, hasLength(2));
    });

    test('without garlic candidates sendMessage falls back to the direct '
        'MS02b deposit', () async {
      final (client, socket, _) = await setupClient(hopCount: 0);
      addTearDown(client.disconnect);

      final frames = <(int, Uint8List)>[];
      socket.onCommandFrame = (cmd, payload) {
        frames.add((cmd, payload));
        if (cmd == 141) {
          final response = FlaschenpostPutResponse()..status = Status.OK;
          socket.replyCommand(158, response.writeToBuffer());
        }
      };

      final channel = await channelWithKeys(client);
      final messageId = await client.sendMessage(channel.id, 'Direct');
      expect(messageId, hasLength(32));

      expect(frames.single.$1, 141);
      expect(client.lastSendHopCount, 0);
      final put = FlaschenpostPut.fromBuffer(frames.single.$2);
      expect(put.ohId, equals(ohId));
      expect(put.wantResponse, isTrue);
    });

    test('content above the garlic payload budget fails permanently '
        '(BAD_REQUEST)', () async {
      final (client, socket, _) = await setupClient();
      addTearDown(client.disconnect);

      final frames = <int>[];
      socket.onCommandFrame = (cmd, _) => frames.add(cmd);

      final channel = await channelWithKeys(client);
      final oversize = 'x' * (GarlicBuilder.maxPayloadLength(3) + 1);

      await expectLater(
        client.sendMessage(channel.id, oversize),
        throwsA(
          isA<DepositException>().having(
            (e) => e.isBadRequest,
            'isBadRequest',
            isTrue,
          ),
        ),
      );
      expect(frames, isEmpty, reason: 'nothing must be sent');
    });

    test('REDPANDAJ-2DR: without a known peer OH, sendMessage refuses the '
        'direct deposit instead of sending an empty oh_id', () async {
      final (client, socket, _) = await setupClient(hopCount: 0);
      addTearDown(client.disconnect);

      final frames = <int>[];
      socket.onCommandFrame = (cmd, _) => frames.add(cmd);

      // No peerOhId passed at all: _channelPeerOhIds[channelId] stays null.
      final channel = await Channel.generate('MS04-no-oh');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
      );

      await expectLater(
        client.sendMessage(channel.id, 'Hello into the void'),
        throwsA(isA<UnknownPeerException>()),
      );
      expect(
        frames,
        isEmpty,
        reason:
            'a FlaschenpostPut with an empty oh_id would be misparsed by '
            'the node as a GMAck frame (REDPANDAJ-2DR) — nothing may be '
            'sent when the peer OH is unknown',
      );
    });

    test('REDPANDAJ-2DR: a malformed (wrong-length) peer OH is treated the '
        'same as unknown — no direct deposit is sent', () async {
      final (client, socket, _) = await setupClient(hopCount: 0);
      addTearDown(client.disconnect);

      final frames = <int>[];
      socket.onCommandFrame = (cmd, _) => frames.add(cmd);

      final channel = await Channel.generate('MS04-bad-oh');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        // Wrong length (nodeIdLength is 20): must not be trusted as a real
        // destination.
        peerOhId: [1, 2, 3],
        isChannelCreator: true,
      );

      await expectLater(
        client.sendMessage(channel.id, 'Hello'),
        throwsA(isA<UnknownPeerException>()),
      );
      expect(frames, isEmpty);
    });
  });
}
