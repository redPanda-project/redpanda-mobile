import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/reverse_garlic_block.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

import '../helpers/garlic_test_utils.dart';
import '../helpers/wait_for.dart';
import 'ms05_reverse_garlic_test.dart' show ScriptedSocket;

/// T162: paths that end in our OWN mailbox — the Reverse Garlic Block we hand
/// the partner and the return path of every requested R-ACK — are closed by
/// the node hosting that mailbox. The relays stay the same three non-host
/// hops; the host is appended, so the innermost deliver layer is decrypted
/// (and deposited locally) by the host instead of a relay that would have to
/// resolve the OH host through the DHT (MS02b). On the testnet that lookup
/// was rejected by the nodes' search blacklist and the reply dropped.
void main() {
  setUpAll(() => ActivePeer.plaintextTransportForTesting = true);
  tearDownAll(() => ActivePeer.plaintextTransportForTesting = false);

  final counterpartOhId = List<int>.generate(20, (i) => 200 - i);
  final ownOhId = List<int>.generate(20, (i) => 50 + i);

  /// The node behind the scripted socket, i.e. the host of our own OH:
  /// identity from a 64-byte public export, X25519 key for its garlic layer.
  Future<(TestHop, Uint8List)> makeHost() async {
    final keys = await CryptoUtils.generateEncryptionKeypair();
    final verifyKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 7));
    final export = Uint8List.fromList([...verifyKey, ...keys.publicKey]);
    final nodeId = NodeId.fromPublicKeyBytes(export);
    return (
      TestHop(Uint8List.fromList(HEX.decode(nodeId.toHex())), keys),
      export,
    );
  }

  /// Connected client with three relay candidates; with [hostExport] the
  /// scripted node announces its public key (like a real node after the
  /// handshake), so the client knows its mailbox host as a garlic hop.
  ///
  /// [relayCount] relay candidates; [hostAlias] additionally lists the host
  /// under a second address (as a peer list can); [hostInRepoOnly] puts the
  /// host's identity into the peer list without the node ever announcing it
  /// on the live connection.
  Future<(RedPandaLightClient, ScriptedSocket, List<TestHop>)> setupClient({
    Uint8List? hostExport,
    int relayCount = 3,
    TestHop? hostAlias,
    TestHop? hostInRepoOnly,
  }) async {
    final relays = <TestHop>[];
    final repo = InMemoryPeerRepository();
    if (hostAlias != null) {
      repo.updatePeer(
        '10.9.0.9:5000',
        nodeId: HEX.encode(hostAlias.nodeId),
        encryptionPublicKey: HEX.encode(hostAlias.keys.publicKey),
      );
    }
    if (hostInRepoOnly != null) {
      repo.updatePeer(
        'scripted:1',
        nodeId: HEX.encode(hostInRepoOnly.nodeId),
        encryptionPublicKey: HEX.encode(hostInRepoOnly.keys.publicKey),
      );
    }
    for (var i = 0; i < relayCount; i++) {
      final hop = await TestHop.generate(i + 1);
      relays.add(hop);
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
    if (hostExport != null) {
      socket.reply([2, ...hostExport]); // node -> client: sendPublicKey
      await waitFor(
        () => repo.getPeer('scripted:1')?.encryptionPublicKey != null,
        description: 'mailbox host identity learned',
      );
    }
    return (client, socket, relays);
  }

  Future<Channel> channelWithOwnOh(RedPandaLightClient client) async {
    final channel = await Channel.generate('T162');
    client.addChannelKeys(
      channel.id,
      channel.encryptionKey,
      counterpartOhId: counterpartOhId,
      isChannelCreator: true,
    );
    await client.restoreOutboundHandle(
      OHRegistration(
        ohId: ownOhId,
        keypair: await OHKeypair.generate(),
        expiresAtMs: DateTime.now()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch,
        channelId: channel.id,
        serverEndpoint: 'scripted:1',
      ),
    );
    return channel;
  }

  /// The RGB carried by the message in a peeled payload.
  Future<ReverseGarlicBlock?> rgbIn(Uint8List payload, Channel channel) async {
    final session = await RatchetSession.create(
      channelKey: channel.encryptionKey,
      isChannelCreator: false,
    );
    final message = await session.decrypt(payload, channel.id);
    final path = message.replyPath;
    return path == null ? null : ReverseGarlicBlock.deserialize(path);
  }

  /// Peels the forward packet down to its CMD_DELIVER_ACKED layer and returns
  /// (relay path, return-path hop node ids, payload).
  Future<(List<TestHop>, List<String>, Uint8List)> peel(
    Uint8List packet,
    List<TestHop> relays,
  ) async {
    final path = <TestHop>[];
    while (true) {
      final parsed = ParsedPacket.parse(packet);
      final hop = relays.firstWhere(
        (h) => HEX.encode(h.nodeId) == HEX.encode(parsed.nextHop),
        orElse: () => fail('forward path left the relay set'),
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
      expect(plaintext[0], GarlicBuilder.cmdDeliverAcked);
      var offset = 22 + plaintext[21]; // cmd, oh_id, tag_len, tag
      final returnHopCount = plaintext[offset + 36];
      final returnHops = [
        for (var i = 0; i < returnHopCount; i++)
          HEX.encode(
            plaintext.sublist(offset + 37 + i * 52, offset + 37 + i * 52 + 20),
          ),
      ];
      offset += 37 + returnHopCount * 52;
      final len = ByteData.sublistView(plaintext).getUint32(offset);
      return (
        path,
        returnHops,
        Uint8List.fromList(plaintext.sublist(offset + 4, offset + 4 + len)),
      );
    }
  }

  group('T162: own-mailbox paths end at the mailbox host', () {
    test('the RGB and the R-ACK return path are 3 relays + the host', () async {
      final (host, export) = await makeHost();
      final (client, socket, relays) = await setupClient(hostExport: export);
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      final channel = await channelWithOwnOh(client);

      await client.sendMessage(channel.id, 'reply to me');
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');

      final relayIds = relays.map((h) => HEX.encode(h.nodeId)).toSet();
      final hostId = HEX.encode(host.nodeId);
      final (path, returnHops, payload) = await peel(frames.single, relays);

      // The forward path to the counterpart is unchanged: relays only.
      expect(path, hasLength(3));

      // R-ACK return path: three relays, closed by our mailbox host.
      expect(returnHops, hasLength(4));
      expect(returnHops.last, hostId);
      expect(relayIds.containsAll(returnHops.take(3)), isTrue);

      // RGB inside the message: three relays, closed by our mailbox host.
      final session = await RatchetSession.create(
        channelKey: channel.encryptionKey,
        isChannelCreator: false,
      );
      final message = await session.decrypt(payload, channel.id);
      final rgb = ReverseGarlicBlock.deserialize(message.replyPath!);
      final rgbIds = rgb.hops.map((h) => HEX.encode(h.nodeId)).toList();
      expect(rgbIds, hasLength(4));
      expect(rgbIds.last, hostId);
      expect(relayIds.containsAll(rgbIds.take(3)), isTrue);
      expect(rgbIds.take(3), isNot(contains(hostId)));
      expect(
        HEX.encode(rgb.hops.last.encryptionPublicKey),
        HEX.encode(host.keys.publicKey),
      );

      // A reply built on this RGB is decrypted to its deliver layer by the
      // HOST — no relay ever sees the oh_id.
      final reply = await GarlicBuilder.build(
        hops: rgb.hops,
        ohId: rgb.ohId,
        payload: Uint8List.fromList([1, 2, 3]),
        sessionTag: rgb.sessionTag,
      );
      var packet = reply;
      for (var i = 0; i < 4; i++) {
        final parsed = ParsedPacket.parse(packet);
        final atHost = HEX.encode(parsed.nextHop) == hostId;
        expect(atHost, i == 3, reason: 'layer $i');
        final key = atHost
            ? host.keys.privateKey
            : relays
                  .firstWhere(
                    (h) => HEX.encode(h.nodeId) == HEX.encode(parsed.nextHop),
                  )
                  .keys
                  .privateKey;
        final plaintext = await parsed.decryptLayer(key);
        if (i < 3) {
          expect(plaintext[0], GarlicBuilder.cmdForward);
          packet = GarlicBuilder.buildPacket(
            plaintext.sublist(1, 21),
            plaintext.sublist(21),
          );
        } else {
          expect(plaintext[0], GarlicBuilder.cmdDeliverTagged);
          expect(plaintext.sublist(1, 21), equals(ownOhId));
        }
      }
    });

    test('without a known host identity the paths end at the last relay '
        '(pre-T162 shape)', () async {
      final (client, socket, relays) = await setupClient();
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      final channel = await channelWithOwnOh(client);

      await client.sendMessage(channel.id, 'no host key');
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');

      final (_, returnHops, payload) = await peel(frames.single, relays);
      expect(returnHops, hasLength(3));
      final session = await RatchetSession.create(
        channelKey: channel.encryptionKey,
        isChannelCreator: false,
      );
      final message = await session.decrypt(payload, channel.id);
      expect(
        ReverseGarlicBlock.deserialize(message.replyPath!).hops,
        hasLength(3),
      );
    });
  });

  group('T162 review round 1', () {
    test('C1: without relays the return path stays empty (0-hop), never '
        '[host] — single-node network, self-hop route', () async {
      final (host, export) = await makeHost();
      final (client, socket, _) = await setupClient(
        hostExport: export,
        relayCount: 0,
      );
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      final channel = await channelWithOwnOh(client);

      await client.sendMessage(channel.id, 'single node');
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');

      // Self-hop through the connected node (= our host); the R-ACK must
      // be answered by the depositing node itself (hop_count 0).
      final (path, returnHops, payload) = await peel(frames.single, [host]);
      expect(path.single.nodeId, equals(host.nodeId));
      expect(client.lastSendAckRequested, isTrue);
      expect(returnHops, isEmpty);
      expect(await rgbIn(payload, channel), isNull);
    });

    test('C2: a host known under a second address is never a relay and '
        'closes the RGB exactly once', () async {
      // Identity via the peer list only: announcing it on the scripted
      // connection would start a key exchange the plaintext test socket
      // cannot complete, and the connection would die mid-test.
      final (host, _) = await makeHost();
      final (client, socket, relays) = await setupClient(
        hostInRepoOnly: host,
        hostAlias: host,
      );
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      final channel = await channelWithOwnOh(client);
      final hostId = HEX.encode(host.nodeId);

      for (var i = 0; i < 6; i++) {
        await client.sendMessage(channel.id, 'alias $i');
        await waitFor(() => frames.length == i + 1, description: 'frame $i');
        // The forward path is not under test here (without a handshake the
        // submit node's own id is unknown, so its alias may relay).
        final (_, returnHops, payload) = await peel(frames[i], [
          ...relays,
          host,
        ]);
        final rgb = (await rgbIn(payload, channel))!;
        final ids = rgb.hops.map((h) => HEX.encode(h.nodeId)).toList();
        expect(ids.where((id) => id == hostId), hasLength(1), reason: '$ids');
        expect(ids.last, hostId);
        expect(returnHops.where((id) => id == hostId), hasLength(1));
        expect(returnHops.last, hostId);
      }
    });

    test('C4: the host identity is taken from the peer list when the live '
        'connection has not announced it', () async {
      final (host, _) = await makeHost();
      final (client, socket, relays) = await setupClient(hostInRepoOnly: host);
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      final channel = await channelWithOwnOh(client);

      await client.sendMessage(channel.id, 'repo only');
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
      final (_, returnHops, payload) = await peel(frames.single, relays);
      final rgb = (await rgbIn(payload, channel))!;
      expect(HEX.encode(rgb.hops.last.nodeId), HEX.encode(host.nodeId));
      expect(rgb.hops, hasLength(4));
      expect(returnHops.last, HEX.encode(host.nodeId));
    });

    group('C5: content near the payload limit', () {
      /// v4 payload length of a message with [content] and an RGB of
      /// [rgbHops] hops (null: none) — same layout the client encrypts.
      int payloadLength(int contentLength, int? rgbHops, List<TestHop> pool) {
        final rgb = rgbHops == null
            ? null
            : ReverseGarlicBlock(
                expiryTs: DateTime.now()
                    .add(const Duration(hours: 24))
                    .millisecondsSinceEpoch,
                sessionTag: Uint8List(16),
                ohId: ownOhId,
                hops: [for (final h in pool.take(rgbHops)) h.asGarlicHop],
              );
        return MessageCryptoV4.minPayloadLength +
            ChannelMessage(
              messageId: Uint8List(16),
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              content: 'x' * contentLength,
              replyPath: rgb?.serialize(),
            ).encode().length;
      }

      Future<ReverseGarlicBlock?> sentRgb(int contentLength) async {
        final (host, _) = await makeHost();
        final (client, socket, relays) = await setupClient(
          hostInRepoOnly: host,
        );
        addTearDown(client.disconnect);
        final frames = <Uint8List>[];
        socket.onCommandFrame = (cmd, payload) {
          if (cmd == 142) frames.add(payload);
        };
        final channel = await channelWithOwnOh(client);
        await client.sendMessage(channel.id, 'x' * contentLength);
        await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
        final packet = frames.single;
        // Peel without return-path parsing assumptions: the acked budget
        // may have been exceeded, so accept DELIVER and DELIVER_ACKED.
        var p = packet;
        while (true) {
          final parsed = ParsedPacket.parse(p);
          final hop = relays.firstWhere(
            (h) => HEX.encode(h.nodeId) == HEX.encode(parsed.nextHop),
          );
          final plain = await parsed.decryptLayer(hop.keys.privateKey);
          if (plain[0] == GarlicBuilder.cmdForward) {
            p = GarlicBuilder.buildPacket(
              plain.sublist(1, 21),
              plain.sublist(21),
            );
            continue;
          }
          int offset;
          if (plain[0] == GarlicBuilder.cmdDeliverAcked) {
            offset = 22 + plain[21];
            offset += 37 + plain[offset + 36] * 52;
          } else {
            expect(plain[0], GarlicBuilder.cmdDeliver);
            offset = 21;
          }
          final len = ByteData.sublistView(plain).getUint32(offset);
          final payload = Uint8List.fromList(
            plain.sublist(offset + 4, offset + 4 + len),
          );
          expect(host.nodeId, isNotEmpty);
          return rgbIn(payload, channel);
        }
      }

      test(
        'a message that only fits with the 3-hop RGB gets the 3-hop RGB',
        () async {
          final pool = [
            for (var i = 0; i < 4; i++) await TestHop.generate(i + 1),
          ];
          final budget = GarlicBuilder.maxPayloadLength(3);
          var n = 1000;
          while (payloadLength(n, 4, pool) <= budget) {
            n++;
          }
          expect(payloadLength(n, 3, pool), lessThanOrEqualTo(budget));
          final rgb = await sentRgb(n);
          expect(rgb, isNotNull);
          expect(rgb!.hops, hasLength(3));
        },
      );

      test('a message too large for any RGB is sent without one instead of '
          'failing', () async {
        final pool = [
          for (var i = 0; i < 4; i++) await TestHop.generate(i + 1),
        ];
        final budget = GarlicBuilder.maxPayloadLength(3);
        var n = 1000;
        while (payloadLength(n, 3, pool) <= budget) {
          n++;
        }
        expect(payloadLength(n, null, pool), lessThanOrEqualTo(budget));
        expect(await sentRgb(n), isNull);
      });
    });
  });
}
