import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/reverse_garlic_block.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import '../helpers/garlic_test_utils.dart';
import '../helpers/wait_for.dart';

/// A scripted in-memory Socket (see ms04_send_garlic_test.dart): captures
/// client writes and lets the test inject node responses. Extended for MS05
/// with the OH fetch/ack frames so fetchMessages can be scripted.
class ScriptedSocket implements Socket {
  @override
  Future<void> get done => Completer<void>().future;

  final _incoming = StreamController<Uint8List>();
  final List<int> _outBuffer = [];
  bool _handshakeAnswered = false;

  /// Framed payload commands the client can send:
  /// deposit 141, flaschenpost v2 142, register OH 150, fetch 152, ack 156.
  static const Set<int> _framedCommands = {141, 142, 150, 152, 156, 159};

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
    // commands are reported to the test.
    while (_outBuffer.isNotEmpty) {
      final command = _outBuffer[0];
      if (_framedCommands.contains(command)) {
        if (_outBuffer.length < 5) return;
        final len = ByteData.sublistView(
          Uint8List.fromList(_outBuffer.sublist(1, 5)),
        ).getInt32(0, Endian.big);
        if (_outBuffer.length < 5 + len) return;
        final payload = Uint8List.fromList(_outBuffer.sublist(5, 5 + len));
        _outBuffer.removeRange(0, 5 + len);
        if (command == 159) {
          // T38: accept the subscribe (node → OK) so the mock's plaintext
          // parser stays aligned; these flows don't exercise Notify.
          replyCommand(
            160,
            (SubscribeResponse()..status = Status.OK).writeToBuffer(),
          );
        } else {
          onCommandFrame?.call(command, payload);
        }
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
  final counterpartOhId = List<int>.generate(20, (i) => 200 - i);
  final ownOhId = List<int>.generate(20, (i) => 50 + i);

  /// Builds a connected client whose peer repository knows [hopCount] relay
  /// candidates (returned with their private keys).
  Future<(RedPandaLightClient, ScriptedSocket, List<TestHop>)> setupClient({
    int hopCount = 3,
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

    final socket = ScriptedSocket();
    final keys = await KeyPair.generate();
    final client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: ['scripted:1'],
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

  /// Registers an own OH for [channelId] without contacting the network.
  Future<OHRegistration> restoreOwnOh(
    RedPandaLightClient client,
    String channelId,
  ) async {
    final oh = OHRegistration(
      ohId: ownOhId,
      keypair: await OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      channelId: channelId,
      // Must be the connected scripted peer: fetches go only to the node
      // hosting the handle's mailbox.
      serverEndpoint: 'scripted:1',
    );
    await client.restoreOutboundHandle(oh);
    return oh;
  }

  /// Peels all layers of [packet] and returns (command, oh_id, session_tag,
  /// payload, path).
  Future<(int, Uint8List, Uint8List?, Uint8List, List<TestHop>)> peelAll(
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
      final cmd = plaintext[0];
      final ohId = Uint8List.fromList(plaintext.sublist(1, 21));
      Uint8List? tag;
      int lenOffset;
      if (cmd == GarlicBuilder.cmdDeliverTagged) {
        tag = Uint8List.fromList(plaintext.sublist(21, 37));
        lenOffset = 37;
      } else if (cmd == GarlicBuilder.cmdDeliverAcked) {
        // [1 cmd][20 oh_id][1 tag_len][tag][return_path][4 payload_len]...
        final tagLen = plaintext[21];
        var offset = 22;
        if (tagLen != 0) {
          tag = Uint8List.fromList(plaintext.sublist(offset, offset + tagLen));
          offset += tagLen;
        }
        // The return-path block: [20 ackOh][16 tag][1 hopCount][hops×52].
        final returnHopCount = plaintext[offset + 36];
        offset += 37 + returnHopCount * 52;
        lenOffset = offset;
      } else {
        lenOffset = 21;
      }
      final payloadLen = ByteData.sublistView(plaintext).getUint32(lenOffset);
      final payload = Uint8List.fromList(
        plaintext.sublist(lenOffset + 4, lenOffset + 4 + payloadLen),
      );
      return (cmd, ohId, tag, payload, path);
    }
  }

  group('MS05 sendMessage: RGB attachment (issuer side)', () {
    test('a message from a channel with an own OH carries a fresh 3-hop RGB '
        'and registers its session tag', () async {
      final (client, socket, hops) = await setupClient();
      addTearDown(client.disconnect);

      final updates = <GarlicSessionUpdate>[];
      client.stateUpdates.of<GarlicSessionUpdate>().listen(updates.add);

      final frames = <(int, Uint8List)>[];
      socket.onCommandFrame = (cmd, payload) => frames.add((cmd, payload));

      final channel = await Channel.generate('MS05 RGB out');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        counterpartOhId: counterpartOhId,
        isChannelCreator: true,
      );
      await restoreOwnOh(client, channel.id);

      await client.sendMessage(channel.id, 'Hello with reply path!');
      await waitFor(
        () => frames.isNotEmpty,
        description: 'garlic frame written to the socket',
      );

      // Forward path: a garlic packet whose innermost layer is an acked
      // deliver (MS06 — the channel has an own OH, so an R-ACK is requested)
      // with no session tag on the forward direction.
      expect(frames.single.$1, 142);
      expect(client.lastSendViaRgb, isFalse);
      expect(client.lastSendAckRequested, isTrue);
      final (cmd, ohId, tag, payload, _) = await peelAll(
        frames.single.$2,
        hops,
      );
      expect(cmd, GarlicBuilder.cmdDeliverAcked);
      expect(ohId, equals(counterpartOhId));
      expect(tag, isNull);

      // The partner's ratchet decrypts the payload; the inner ChannelMessage
      // carries the serialized RGB.
      final bobSession = await RatchetSession.create(
        channelKey: channel.encryptionKey,
        isChannelCreator: false,
      );
      final message = await bobSession.decrypt(payload, channel.id);
      expect(message.content, 'Hello with reply path!');
      expect(message.replyPath, isNotNull);

      final rgb = ReverseGarlicBlock.deserialize(message.replyPath!);
      expect(rgb.ohId, equals(ownOhId));
      expect(rgb.hops, hasLength(3));
      expect(rgb.isExpired(), isFalse);
      final hopIds = hops.map((h) => HEX.encode(h.nodeId)).toSet();
      for (final hop in rgb.hops) {
        expect(hopIds, contains(HEX.encode(hop.nodeId)));
      }

      // The issued session tag is registered for the channel (persistence
      // snapshot emitted for the app layer).
      await waitFor(
        () => updates.isNotEmpty,
        description: 'persistence update emitted',
      );
      expect(updates.last.channelId, channel.id);
      expect(updates.last.sessionTags.keys, contains(rgb.sessionTagHex));
    });

    test('without an own OH for the channel no RGB is attached', () async {
      final (client, socket, hops) = await setupClient();
      addTearDown(client.disconnect);

      final frames = <(int, Uint8List)>[];
      socket.onCommandFrame = (cmd, payload) => frames.add((cmd, payload));

      final channel = await Channel.generate('MS05 no own OH');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        counterpartOhId: counterpartOhId,
        isChannelCreator: true,
      );

      await client.sendMessage(channel.id, 'No reply path');
      await waitFor(
        () => frames.isNotEmpty,
        description: 'garlic frame written to the socket',
      );

      final (_, _, _, payload, _) = await peelAll(frames.single.$2, hops);
      final bobSession = await RatchetSession.create(
        channelKey: channel.encryptionKey,
        isChannelCreator: false,
      );
      final message = await bobSession.decrypt(payload, channel.id);
      expect(message.replyPath, isNull);
    });
  });

  group('MS05 sendMessage: reply via RGB (responder side)', () {
    test('a pending RGB routes the reply as CMD_DELIVER_TAGGED over the '
        'issuer-chosen hops and is consumed (single-use)', () async {
      final (client, socket, hops) = await setupClient();
      addTearDown(client.disconnect);

      final updates = <GarlicSessionUpdate>[];
      client.stateUpdates.of<GarlicSessionUpdate>().listen(updates.add);

      final frames = <(int, Uint8List)>[];
      socket.onCommandFrame = (cmd, payload) {
        frames.add((cmd, payload));
        if (cmd == 141) {
          final response = FlaschenpostPutResponse()..status = Status.OK;
          socket.replyCommand(158, response.writeToBuffer());
        }
      };

      final sessionTag = List<int>.generate(16, (i) => 0xA0 + i);
      final rgb = ReverseGarlicBlock(
        expiryTs: DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        sessionTag: sessionTag,
        ohId: ownOhId,
        hops: hops.map((h) => h.asGarlicHop).toList(),
      );

      // Bob's view: channel WITHOUT the counterpart's OH id — the RGB is his only
      // route back to Alice.
      final channel = await Channel.generate('MS05 reply');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: false,
        pendingRgbHex: HEX.encode(rgb.serialize()),
      );

      await client.sendMessage(channel.id, 'Reply through your hops!');
      await waitFor(
        () => frames.isNotEmpty,
        description: 'garlic frame written to the socket',
      );

      expect(frames.single.$1, 142);
      expect(client.lastSendViaRgb, isTrue);
      expect(client.lastSendHopCount, 3);

      final (cmd, ohId, tag, payload, path) = await peelAll(
        frames.single.$2,
        hops,
      );
      expect(cmd, GarlicBuilder.cmdDeliverTagged);
      expect(ohId, equals(ownOhId));
      expect(tag, equals(sessionTag));
      expect(
        path.map((h) => HEX.encode(h.nodeId)).toList(),
        equals(hops.map((h) => HEX.encode(h.nodeId)).toList()),
        reason: 'the reply must traverse exactly the issuer-chosen hops',
      );

      // The issuer's ratchet (channel creator) decrypts the reply.
      final aliceSession = await RatchetSession.create(
        channelKey: channel.encryptionKey,
        isChannelCreator: true,
      );
      final message = await aliceSession.decrypt(payload, channel.id);
      expect(message.content, 'Reply through your hops!');

      // Consumed: the persistence snapshot clears the pending RGB, and the
      // next send has no route left at all — no RGB, no known counterpart OH, no
      // garlic hops for this channel. REDPANDAJ-2DR: sendMessage must refuse
      // rather than deposit with an empty oh_id.
      await waitFor(
        () => updates.isNotEmpty,
        description: 'persistence update emitted',
      );
      expect(updates.last.pendingRgbHex, isNull);

      await expectLater(
        client.sendMessage(channel.id, 'Second message'),
        throwsA(isA<UnknownCounterpartException>()),
      );
      expect(
        frames,
        hasLength(1),
        reason:
            'RGB is single-use and no other route is known; nothing '
            'more may be sent',
      );
    });

    test('an expired RGB is discarded and the reply falls back to the '
        'forward garlic path (OQ 3)', () async {
      final (client, socket, hops) = await setupClient();
      addTearDown(client.disconnect);

      final frames = <(int, Uint8List)>[];
      socket.onCommandFrame = (cmd, payload) => frames.add((cmd, payload));

      final expired = ReverseGarlicBlock(
        expiryTs: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        sessionTag: List<int>.filled(16, 7),
        ohId: ownOhId,
        hops: hops.map((h) => h.asGarlicHop).toList(),
      );

      final channel = await Channel.generate('MS05 expired RGB');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        counterpartOhId: counterpartOhId,
        isChannelCreator: false,
        pendingRgbHex: HEX.encode(expired.serialize()),
      );

      await client.sendMessage(channel.id, 'Falls back');
      await waitFor(
        () => frames.isNotEmpty,
        description: 'garlic frame written to the socket',
      );

      expect(frames.single.$1, 142);
      expect(client.lastSendViaRgb, isFalse);
      final (cmd, ohId, tag, _, _) = await peelAll(frames.single.$2, hops);
      expect(cmd, GarlicBuilder.cmdDeliver, reason: 'untagged forward path');
      expect(ohId, equals(counterpartOhId));
      expect(tag, isNull);
    });
  });

  group('MS05 fetchMessages: tag correlation (issuer side)', () {
    test('a tagged mail item is correlated, consumed and the contained RGB '
        'stored; unknown tags are dropped', () async {
      final (client, socket, _) = await setupClient(hopCount: 0);
      addTearDown(client.disconnect);

      final updates = <GarlicSessionUpdate>[];
      client.stateUpdates.of<GarlicSessionUpdate>().listen(updates.add);

      final channel = await Channel.generate('MS05 fetch');
      const knownTagHex = 'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf'; // 16 bytes hex

      // Bob's reply: encrypted with his ratchet side, carrying his own RGB.
      final bobSession = await RatchetSession.create(
        channelKey: channel.encryptionKey,
        isChannelCreator: false,
      );
      final bobHop = await TestHop.generate(9);
      final bobsRgb = ReverseGarlicBlock(
        expiryTs: DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        sessionTag: List<int>.filled(16, 0x42),
        ohId: counterpartOhId,
        hops: [bobHop.asGarlicHop],
      );
      final replyPayload = await bobSession.encrypt(
        ChannelMessage(
          messageId: Uint8List.fromList(List<int>.filled(16, 1)),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          content: 'Tagged reply',
          replyPath: bobsRgb.serialize(),
        ),
        channel.id,
      );
      final strayPayload = await bobSession.encrypt(
        ChannelMessage(
          messageId: Uint8List.fromList(List<int>.filled(16, 2)),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          content: 'Stray tagged item',
        ),
        channel.id,
      );

      // Alice's view: outstanding tag restored from persistence.
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
        sessionTags: {knownTagHex: DateTime.now().millisecondsSinceEpoch},
      );
      final oh = await restoreOwnOh(client, channel.id);

      MailItem item(int seq, List<int> payload, String tagHex) => MailItem(
        receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
        payload: payload,
        sequenceId: fixnum.Int64(seq),
        sessionTag: HEX.decode(tagHex),
      );

      var fetchCount = 0;
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 152) {
          fetchCount++;
          final response = FetchResponse()
            ..status = Status.OK
            ..nextCursor = fixnum.Int64(fetchCount * 10);
          if (fetchCount == 1) {
            // One legitimate tagged reply + one item with an unknown tag.
            response.items.add(item(1, replyPayload, knownTagHex));
            response.items.add(item(2, strayPayload, 'ff' * 16));
          } else {
            // Re-delivery of the already consumed tag (replay).
            response.items.add(item(3, strayPayload, knownTagHex));
          }
          socket.replyCommand(153, response.writeToBuffer());
        } else if (cmd == 156) {
          final ack = AckFetchResponse()..status = Status.OK;
          socket.replyCommand(157, ack.writeToBuffer());
        }
      };

      final messages = await client.fetchMessages(oh);

      expect(messages, hasLength(1), reason: 'unknown tags are dropped');
      expect(messages.single.content, 'Tagged reply');
      expect(messages.single.viaSessionTag, isTrue);
      expect(messages.single.channelId, channel.id);

      // The consumed tag is gone and Bob's RGB is pending now.
      await waitFor(
        () => updates.isNotEmpty,
        description: 'persistence update emitted',
      );
      expect(updates.last.sessionTags, isEmpty);
      expect(updates.last.pendingRgbHex, HEX.encode(bobsRgb.serialize()));

      // Replay with the consumed tag yields nothing (single-use).
      final replayed = await client.fetchMessages(oh);
      expect(replayed, isEmpty);
    });
  });
}
