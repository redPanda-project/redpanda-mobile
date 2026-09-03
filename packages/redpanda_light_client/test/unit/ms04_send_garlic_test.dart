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
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

import '../helpers/garlic_test_utils.dart';
import '../helpers/wait_for.dart';

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
    String? counterpartOhEndpoint,
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
    if (ohHostHop != null && counterpartOhEndpoint != null) {
      repo.updatePeer(
        counterpartOhEndpoint,
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
    await waitFor(
      () => client.activePeerAddresses.isNotEmpty,
      timeout: const Duration(seconds: 15),
      description: 'peer handshake verification',
    );
    return (client, socket, hops);
  }

  Future<Channel> channelWithKeys(
    RedPandaLightClient client, {
    String? counterpartOhEndpoint,
  }) async {
    final channel = await Channel.generate('MS04');
    client.addChannelKeys(
      channel.id,
      channel.encryptionKey,
      counterpartOhId: ohId,
      counterpartOhEndpoint: counterpartOhEndpoint,
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

      // Outbound frames travel an async tx chain, so poll rather than assert
      // straight away.
      await waitFor(
        () => frames.isNotEmpty,
        description: 'garlic frame written to the socket',
      );
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
        counterpartOhEndpoint: '10.9.9.9:5000',
        ohHostHop: ohHost,
      );
      addTearDown(client.disconnect);

      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };

      final channel = await channelWithKeys(
        client,
        counterpartOhEndpoint: '10.9.9.9:5000',
      );

      // The hop pool holds 3 regular relays + the OH host. Across several
      // sends, peeling with the regular relays ALONE must always reach
      // CMD_DELIVER — i.e. the OH host never appears on any layer.
      for (var i = 0; i < 5; i++) {
        await client.sendMessage(channel.id, 'try $i');
        await waitFor(
          () => frames.length == i + 1,
          description: 'frame ${i + 1} written to the socket',
        );
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

      await waitFor(
        () => frames.isNotEmpty,
        description: 'garlic frame written to the socket',
      );
      expect(frames.single.$1, 142);
      expect(client.lastSendHopCount, 2);
      final (_, path) = await peelAll(frames.single.$2, hops);
      expect(path, hasLength(2));
    });

    test('without garlic candidates and no self-hop identity, sendMessage '
        'never falls back to a direct deposit (T45)', () async {
      // T45: a deposit is NEVER a direct FlaschenpostPut. With no relay
      // candidate AND the connected node's identity unknown (the scripted
      // handshake sends no 64-byte export, so its KademliaId/X25519 key stay
      // unknown here), no garlic route can be built — the message stays
      // pending (throws) and nothing goes out as command 141. In the real
      // single-node case the connected node's identity IS known after the full
      // handshake, so a self-hop garlic route (command 142) is built instead;
      // that degenerate path is covered by the single-node emulator gate.
      final (client, socket, _) = await setupClient(hopCount: 0);
      addTearDown(client.disconnect);

      final frames = <int>[];
      socket.onCommandFrame = (cmd, _) => frames.add(cmd);

      final channel = await channelWithKeys(client);
      await expectLater(
        client.sendMessage(channel.id, 'no direct'),
        throwsA(isA<DepositException>()),
      );
      expect(
        frames,
        isEmpty,
        reason: 'no direct command-141 deposit may ever be sent',
      );
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

    test('REDPANDAJ-2DR: without a known counterpart OH, sendMessage refuses the '
        'direct deposit instead of sending an empty oh_id', () async {
      final (client, socket, _) = await setupClient(hopCount: 0);
      addTearDown(client.disconnect);

      final frames = <int>[];
      socket.onCommandFrame = (cmd, _) => frames.add(cmd);

      // No counterpartOhId passed at all: _channelCounterpartOhIds[channelId] stays null.
      final channel = await Channel.generate('MS04-no-oh');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
      );

      await expectLater(
        client.sendMessage(channel.id, 'Hello into the void'),
        throwsA(isA<UnknownCounterpartException>()),
      );
      expect(
        frames,
        isEmpty,
        reason:
            'a FlaschenpostPut with an empty oh_id would be misparsed by '
            'the node as a GMAck frame (REDPANDAJ-2DR) — nothing may be '
            'sent when the counterpart OH is unknown',
      );
    });

    test(
      'REDPANDAJ-2DR: a malformed (wrong-length) counterpart OH is treated the '
      'same as unknown — no direct deposit is sent',
      () async {
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
          counterpartOhId: [1, 2, 3],
          isChannelCreator: true,
        );

        await expectLater(
          client.sendMessage(channel.id, 'Hello'),
          throwsA(isA<UnknownCounterpartException>()),
        );
        expect(frames, isEmpty);
      },
    );
  });
}
