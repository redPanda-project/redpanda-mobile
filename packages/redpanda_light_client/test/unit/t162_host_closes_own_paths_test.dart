import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/hop_selector.dart';
import 'package:redpanda_light_client/src/garlic/rgb_builder.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart'
    hide RoutingAck;

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/diagnostics/diag_catalogue.dart';
import 'package:redpanda_light_client/src/diagnostics/rp_diag.dart';
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
  Future<(TestHop, Uint8List)> makeHost({int seed = 7}) async {
    final keys = await CryptoUtils.generateEncryptionKeypair();
    final verifyKey = Uint8List.fromList(
      List<int>.generate(32, (i) => i + seed),
    );
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
    TestHop? poisonHostEntry,
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
    if (poisonHostEntry != null) {
      // Another node's peer list overwrites the host's entry (F1).
      repo.updatePeer(
        'scripted:1',
        nodeId: HEX.encode(poisonHostEntry.nodeId),
        encryptionPublicKey: HEX.encode(poisonHostEntry.keys.publicKey),
      );
    }
    return (client, socket, relays);
  }

  Future<Channel> channelWithOwnOh(
    RedPandaLightClient client, {
    bool withCounterpart = true,
    String? pendingRgbHex,
    void Function(OHRegistration oh)? onOh,
  }) async {
    final channel = await Channel.generate('T162');
    client.addChannelKeys(
      channel.id,
      channel.encryptionKey,
      channelSecret: channel.channelSecret,
      counterpartOhId: withCounterpart ? counterpartOhId : null,
      isChannelCreator: true,
      pendingRgbHex: pendingRgbHex,
    );
    final oh = OHRegistration(
      ohId: ownOhId,
      keypair: await OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      channelId: channel.id,
      serverEndpoint: 'scripted:1',
    );
    onOh?.call(oh);
    await client.restoreOutboundHandle(oh);
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

  /// Peels [packet] with the keys in [keyring] down to its innermost layer:
  /// the command, the return-path hop ids/keys and ack tag (acked deliver
  /// and record lookup), and the deliver payload.
  Future<
    ({
      int cmd,
      List<String>? returnHops,
      List<String>? returnHopKeys,
      Uint8List? ackTag,
      Uint8List payload,
    })
  >
  peelAny(Uint8List packet, List<TestHop> keyring) async {
    var p = packet;
    while (true) {
      final parsed = ParsedPacket.parse(p);
      final hop = keyring.firstWhere(
        (h) => HEX.encode(h.nodeId) == HEX.encode(parsed.nextHop),
        orElse: () => fail('next hop outside the keyring'),
      );
      final plain = await parsed.decryptLayer(hop.keys.privateKey);
      if (plain[0] == GarlicBuilder.cmdForward) {
        p = GarlicBuilder.buildPacket(plain.sublist(1, 21), plain.sublist(21));
        continue;
      }
      final cmd = plain[0];
      int? rpOffset;
      int payloadOffset;
      if (cmd == GarlicBuilder.cmdDeliverAcked) {
        rpOffset = 22 + plain[21];
        payloadOffset = rpOffset + 37 + plain[rpOffset + 36] * 52;
      } else if (cmd == GarlicBuilder.cmdRecordLookup) {
        rpOffset = 21;
        payloadOffset = -1;
      } else if (cmd == GarlicBuilder.cmdDeliverTagged) {
        payloadOffset = 37;
      } else {
        expect(cmd, GarlicBuilder.cmdDeliver);
        payloadOffset = 21;
      }
      List<String>? ids;
      List<String>? keys;
      Uint8List? tag;
      if (rpOffset != null) {
        final count = plain[rpOffset + 36];
        tag = Uint8List.fromList(plain.sublist(rpOffset + 20, rpOffset + 36));
        ids = [];
        keys = [];
        for (var i = 0; i < count; i++) {
          final at = rpOffset + 37 + i * 52;
          ids.add(HEX.encode(plain.sublist(at, at + 20)));
          keys.add(HEX.encode(plain.sublist(at + 20, at + 52)));
        }
      }
      final payload = payloadOffset < 0
          ? Uint8List(0)
          : Uint8List.fromList(
              plain.sublist(
                payloadOffset + 4,
                payloadOffset +
                    4 +
                    ByteData.sublistView(plain).getUint32(payloadOffset),
              ),
            );
      return (
        cmd: cmd,
        returnHops: ids,
        returnHopKeys: keys,
        ackTag: tag,
        payload: payload,
      );
    }
  }

  Future<List<TestHop>> hopPool() async => [
    for (var i = 0; i < 4; i++) await TestHop.generate(i + 1),
  ];

  /// v4 payload length of a message with [contentLength] characters and an
  /// RGB of [rgbHops] hops (null: none) — the layout the client encrypts.
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

  int smallestContent(bool Function(int n) over) {
    var n = 1000;
    while (!over(n)) {
      n++;
    }
    return n;
  }

  /// One forward send of [contentLength] characters with a handshake-known
  /// host; returns what left the client.
  Future<
    ({
      int cmd,
      List<String>? returnHops,
      ReverseGarlicBlock? rgb,
      OwnReplyPathShape shape,
      String hostId,
    })
  >
  sendOnce(int contentLength) async {
    final (host, export) = await makeHost();
    final (client, socket, relays) = await setupClient(hostExport: export);
    addTearDown(client.disconnect);
    final frames = <Uint8List>[];
    socket.onCommandFrame = (cmd, payload) {
      if (cmd == 142) frames.add(payload);
    };
    final channel = await channelWithOwnOh(client);
    await client.sendMessage(channel.id, 'x' * contentLength);
    await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
    final peeled = await peelAny(frames.single, [...relays, host]);
    return (
      cmd: peeled.cmd,
      returnHops: peeled.returnHops,
      rgb: await rgbIn(peeled.payload, channel),
      shape: client.lastOwnRgbShape,
      hostId: HEX.encode(host.nodeId),
    );
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
      // One send per client: the plaintext test socket cannot complete the
      // key exchange the announced public key starts, so a connection lives
      // only for a short while after the handshake.
      for (var round = 0; round < 3; round++) {
        final (host, export) = await makeHost();
        final (client, socket, relays) = await setupClient(
          hostExport: export,
          hostAlias: host,
        );
        final frames = <Uint8List>[];
        socket.onCommandFrame = (cmd, payload) {
          if (cmd == 142) frames.add(payload);
        };
        final channel = await channelWithOwnOh(client);
        final hostId = HEX.encode(host.nodeId);

        await client.sendMessage(channel.id, 'alias $round');
        await waitFor(() => frames.isNotEmpty, description: 'frame $round');
        final peeled = await peelAny(frames.single, [...relays, host]);
        final rgb = (await rgbIn(peeled.payload, channel))!;
        final ids = rgb.hops.map((h) => HEX.encode(h.nodeId)).toList();
        expect(ids.where((id) => id == hostId), hasLength(1), reason: '$ids');
        expect(ids.last, hostId);
        expect(peeled.returnHops!.where((id) => id == hostId), hasLength(1));
        expect(peeled.returnHops!.last, hostId);
        await client.disconnect();
      }
    });

    group('C5: content near the payload limit', () {
      test(
        'a message that only fits with the 3-hop RGB gets the 3-hop RGB',
        () async {
          final pool = await hopPool();
          final budget = GarlicBuilder.maxPayloadLength(3);
          final n = smallestContent((n) => payloadLength(n, 4, pool) > budget);
          expect(payloadLength(n, 3, pool), lessThanOrEqualTo(budget));
          final sent = await sendOnce(n);
          expect(sent.rgb, isNotNull);
          expect(sent.rgb!.hops, hasLength(3));
          expect(sent.shape, OwnReplyPathShape.open);
        },
      );

      test('a message too large for any RGB is sent without one instead of '
          'failing', () async {
        final pool = await hopPool();
        final budget = GarlicBuilder.maxPayloadLength(3);
        final n = smallestContent((n) => payloadLength(n, 3, pool) > budget);
        expect(payloadLength(n, null, pool), lessThanOrEqualTo(budget));
        final sent = await sendOnce(n);
        expect(sent.rgb, isNull);
        expect(sent.shape, OwnReplyPathShape.none);
      });
    });
  });

  group('T162 review round 2', () {
    test('F1: without an own handshake with the host (identity only in the '
        'peer list) no path is host-closed', () async {
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
      final peeled = await peelAny(frames.single, [...relays, host]);
      final rgb = (await rgbIn(peeled.payload, channel))!;
      final hostId = HEX.encode(host.nodeId);
      expect(rgb.hops, hasLength(3));
      expect(
        rgb.hops.map((h) => HEX.encode(h.nodeId)),
        isNot(contains(hostId)),
      );
      expect(peeled.returnHops, hasLength(3));
      expect(peeled.returnHops, isNot(contains(hostId)));
      expect(client.lastOwnRgbShape, OwnReplyPathShape.open);
    });

    test(
      'F1: a peer list overwriting the host entry after the handshake '
      'does not change the closing hop (id AND key from the handshake)',
      () async {
        final (host, export) = await makeHost();
        final foreign = await TestHop.generate(0x66);
        final (client, socket, relays) = await setupClient(
          hostExport: export,
          poisonHostEntry: foreign,
        );
        addTearDown(client.disconnect);
        final frames = <Uint8List>[];
        socket.onCommandFrame = (cmd, payload) {
          if (cmd == 142) frames.add(payload);
        };
        final channel = await channelWithOwnOh(client);

        await client.sendMessage(channel.id, 'poisoned peer list');
        await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
        final peeled = await peelAny(frames.single, [...relays, host]);
        final rgb = (await rgbIn(peeled.payload, channel))!;
        expect(HEX.encode(rgb.hops.last.nodeId), HEX.encode(host.nodeId));
        expect(
          HEX.encode(rgb.hops.last.encryptionPublicKey),
          HEX.encode(host.keys.publicKey),
          reason: 'the key the host can decrypt with, not the overwritten one',
        );
        expect(peeled.returnHops!.last, HEX.encode(host.nodeId));
        expect(peeled.returnHopKeys!.last, HEX.encode(host.keys.publicKey));
        expect(client.lastOwnRgbShape, OwnReplyPathShape.hostClosed);
      },
    );

    group('F2: the R-ACK is kept before the closing host', () {
      test(
        'payload that fits the acked budget only with a 3-hop return '
        'path: host-closed RGB, R-ACK over the return path without host',
        () async {
          final pool = await hopPool();
          final withHostRp = GarlicBuilder.maxAckedPayloadLength(
            3,
            tagged: false,
            returnHopCount: 4,
          );
          final withoutHostRp = GarlicBuilder.maxAckedPayloadLength(
            3,
            tagged: false,
            returnHopCount: 3,
          );
          final n = smallestContent(
            (n) => payloadLength(n, 4, pool) > withHostRp,
          );
          expect(payloadLength(n, 4, pool), lessThanOrEqualTo(withoutHostRp));
          final sent = await sendOnce(n);
          expect(sent.cmd, GarlicBuilder.cmdDeliverAcked, reason: 'R-ACK kept');
          expect(sent.returnHops, hasLength(3));
          expect(sent.returnHops, isNot(contains(sent.hostId)));
          expect(sent.rgb!.hops, hasLength(4));
          expect(sent.shape, OwnReplyPathShape.hostClosed);
        },
      );

      test('payload that keeps its R-ACK only with the pre-T162 RGB gets '
          'that RGB', () async {
        final pool = await hopPool();
        final withoutHostRp = GarlicBuilder.maxAckedPayloadLength(
          3,
          tagged: false,
          returnHopCount: 3,
        );
        final n = smallestContent(
          (n) => payloadLength(n, 4, pool) > withoutHostRp,
        );
        expect(payloadLength(n, 3, pool), lessThanOrEqualTo(withoutHostRp));
        final sent = await sendOnce(n);
        expect(sent.cmd, GarlicBuilder.cmdDeliverAcked, reason: 'R-ACK kept');
        expect(sent.rgb!.hops, hasLength(3));
        expect(sent.shape, OwnReplyPathShape.open);
      });
    });

    test('budget over a pending RGB (no counterpart mailbox known): the RGB '
        'falls back when it only fits the forward budget', () async {
      final pool = await hopPool();
      final rgbBudget = GarlicBuilder.maxPayloadLength(3, tagged: true);
      final forwardBudget = GarlicBuilder.maxPayloadLength(3);
      final n = smallestContent((n) => payloadLength(n, 4, pool) > rgbBudget);
      expect(payloadLength(n, 4, pool), lessThanOrEqualTo(forwardBudget));
      expect(payloadLength(n, 3, pool), lessThanOrEqualTo(rgbBudget));

      final (host, export) = await makeHost();
      final (client, socket, relays) = await setupClient(hostExport: export);
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      // The partner's RGB over our three relays; no counterpart OH known,
      // so the only path is the pending RGB (tagged budget).
      final partnerRgb = ReverseGarlicBlock(
        expiryTs: DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        sessionTag: Uint8List(16),
        ohId: counterpartOhId,
        hops: [for (final h in relays) h.asGarlicHop],
      );
      final channel = await channelWithOwnOh(
        client,
        withCounterpart: false,
        pendingRgbHex: HEX.encode(partnerRgb.serialize()),
      );
      await client.sendMessage(channel.id, 'x' * n);
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
      expect(client.lastSendViaRgb, isTrue);
      final peeled = await peelAny(frames.single, [...relays, host]);
      final rgb = (await rgbIn(peeled.payload, channel))!;
      expect(rgb.hops, hasLength(3));
      expect(client.lastOwnRgbShape, OwnReplyPathShape.open);
    });

    test(
      'C3: the rendezvous lookup return path is closed by the host',
      () async {
        final (host, export) = await makeHost();
        final (client, socket, relays) = await setupClient(hostExport: export);
        addTearDown(client.disconnect);
        final frames = <Uint8List>[];
        socket.onCommandFrame = (cmd, payload) {
          if (cmd == 142) frames.add(payload);
        };
        final channel = await channelWithOwnOh(client, withCounterpart: false);
        // No counterpart mailbox known → the send fails and kicks off the
        // rendezvous recovery (record lookups over garlic).
        await expectLater(
          client.sendMessage(channel.id, 'who is there?'),
          throwsA(isA<UnknownCounterpartException>()),
        );
        await waitFor(
          () => frames.isNotEmpty,
          timeout: const Duration(seconds: 20),
          description: 'record lookup frame',
        );
        final peeled = await peelAny(frames.first, [...relays, host]);
        expect(peeled.cmd, GarlicBuilder.cmdRecordLookup);
        expect(peeled.returnHops, hasLength(4));
        expect(peeled.returnHops!.last, HEX.encode(host.nodeId));
      },
    );

    test('C7: the closing host is not fed to the node scorer', () async {
      final (host, export) = await makeHost();
      final (client, socket, relays) = await setupClient(hostExport: export);
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      final scores = <NodeScoreUpdate>[];
      client.stateUpdates.of<NodeScoreUpdate>().listen(scores.add);
      late OHRegistration oh;
      final channel = await channelWithOwnOh(client, onOh: (o) => oh = o);
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      await client.sendMessage(channel.id, 'please ack');
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
      final peeled = await peelAny(frames.single, [...relays, host]);
      expect(peeled.returnHops!.last, HEX.encode(host.nodeId));

      // Deliver the R-ACK into our mailbox and let the client fetch it.
      final rAck = RoutingAck(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        status: RoutingAck.statusStored,
      ).encode();
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 152) {
          final response = FetchResponse()
            ..status = Status.OK
            ..nextCursor = fixnum.Int64(1);
          response.items.add(
            MailItem(
              receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
              payload: rAck,
              sequenceId: fixnum.Int64(1),
              sessionTag: peeled.ackTag,
            ),
          );
          socket.replyCommand(153, response.writeToBuffer());
        } else if (cmd == 156) {
          socket.replyCommand(
            157,
            (AckFetchResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };
      await client.fetchMessages(oh);
      await waitFor(() => scores.isNotEmpty, description: 'node scores');
      final scored = scores.last.scores.map((s) => s.nodeIdHex).toSet();
      expect(scored, isNot(contains(HEX.encode(host.nodeId))));
      expect(
        scored,
        containsAll(peeled.returnHops!.take(3)),
        reason: 'the relays are scored',
      );
    });

    test('RgbBuilder: a selector that returns the closing host never makes it '
        'a relay', () async {
      final (host, _) = await makeHost();
      final repo = InMemoryPeerRepository();
      final relays = [
        for (var i = 0; i < 3; i++) await TestHop.generate(i + 1),
      ];
      for (final (i, hop) in [...relays, host].indexed) {
        repo.updatePeer(
          '10.3.0.$i:5000',
          nodeId: HEX.encode(hop.nodeId),
          encryptionPublicKey: HEX.encode(hop.keys.publicKey),
        );
      }
      final builder = RgbBuilder(HopSelector(repo));
      final hostId = HEX.encode(host.nodeId);
      var sawFilter = false;
      for (var i = 0; i < 40; i++) {
        final rgb = builder.build(ohId: ownOhId, closingHop: host.asGarlicHop)!;
        final ids = rgb.hops.map((h) => HEX.encode(h.nodeId)).toList();
        expect(ids.where((id) => id == hostId), hasLength(1), reason: '$ids');
        expect(ids.last, hostId);
        if (ids.length < 4) sawFilter = true;
      }
      expect(sawFilter, isTrue, reason: 'the selector did return the host');

      // Only the host as candidate: no relay left → no RGB at all.
      final onlyHost = InMemoryPeerRepository()
        ..updatePeer(
          '10.4.0.1:5000',
          nodeId: hostId,
          encryptionPublicKey: HEX.encode(host.keys.publicKey),
        );
      expect(
        RgbBuilder(
          HopSelector(onlyHost),
        ).build(ohId: ownOhId, closingHop: host.asGarlicHop),
        isNull,
      );
    });
  });

  group('T162 review round 3', () {
    test('G1: over a pending partner RGB the R-ACK no longer fits, on the '
        'forward path it does → forward path with R-ACK; the RGB stays '
        'pending for the next, shorter message', () async {
      final pool = await hopPool();
      // partner RGB with 4 stations (host-closed on the partner side)
      final rgbAcked = GarlicBuilder.maxAckedPayloadLength(
        4,
        tagged: true,
        returnHopCount: 3,
      );
      final forwardAcked = GarlicBuilder.maxAckedPayloadLength(
        3,
        tagged: false,
        returnHopCount: 3,
      );
      expect(rgbAcked, 1469);
      expect(forwardAcked, 1570);
      final n = smallestContent((n) => payloadLength(n, 4, pool) > rgbAcked);
      expect(payloadLength(n, 4, pool), lessThanOrEqualTo(forwardAcked));

      final (host, export) = await makeHost();
      final (client, socket, relays) = await setupClient(hostExport: export);
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      final partnerHost = await TestHop.generate(0x77);
      final partnerRgb = ReverseGarlicBlock(
        expiryTs: DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        sessionTag: Uint8List(16),
        ohId: counterpartOhId,
        hops: [for (final h in relays) h.asGarlicHop, partnerHost.asGarlicHop],
      );
      final channel = await channelWithOwnOh(
        client,
        pendingRgbHex: HEX.encode(partnerRgb.serialize()),
      );

      await client.sendMessage(channel.id, 'x' * n);
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
      expect(client.lastSendViaRgb, isFalse, reason: 'forward path');
      expect(client.lastSendAckRequested, isTrue, reason: 'R-ACK kept');
      final peeled = await peelAny(frames.first, [...relays, host]);
      expect(peeled.cmd, GarlicBuilder.cmdDeliverAcked);
      expect(peeled.payload.length, greaterThan(rgbAcked));

      // the unused partner RGB is still pending: a short message takes it
      final before = frames.length;
      await client.sendMessage(channel.id, 'short');
      await waitFor(
        () => frames.length > before,
        description: 'second garlic frame',
      );
      expect(client.lastSendViaRgb, isTrue);
      expect(client.lastSendAckRequested, isTrue);
    });

    test(
      'G2: a second public key on an established connection is ignored',
      () async {
        final (host, export) = await makeHost();
        final (impostor, impostorExport) = await makeHost(seed: 0x55);
        final (client, socket, relays) = await setupClient(hostExport: export);
        addTearDown(client.disconnect);
        socket.reply([2, ...impostorExport]); // node -> client again
        // let the frame be processed (short: the plaintext test connection
        // dies a while after the handshake it cannot complete)
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final frames = <Uint8List>[];
        socket.onCommandFrame = (cmd, payload) {
          if (cmd == 142) frames.add(payload);
        };
        final channel = await channelWithOwnOh(client);

        await client.sendMessage(channel.id, 'who closes?');
        await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
        final peeled = await peelAny(frames.single, [...relays, host]);
        final rgb = (await rgbIn(peeled.payload, channel))!;
        expect(HEX.encode(rgb.hops.last.nodeId), HEX.encode(host.nodeId));
        expect(
          HEX.encode(rgb.hops.last.encryptionPublicKey),
          HEX.encode(host.keys.publicKey),
        );
        expect(
          HEX.encode(rgb.hops.last.nodeId),
          isNot(HEX.encode(impostor.nodeId)),
        );
      },
    );

    test('self-hop route (no relays) uses the handshake key even with an '
        'overwritten peer-list entry', () async {
      final (host, export) = await makeHost();
      final foreign = await TestHop.generate(0x66);
      final (client, socket, _) = await setupClient(
        hostExport: export,
        relayCount: 0,
        poisonHostEntry: foreign,
      );
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      final channel = await channelWithOwnOh(client);

      await client.sendMessage(channel.id, 'single node');
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
      // peeling with the host's real private key only works if the layer
      // was encrypted to the handshake key, not to the overwritten one
      final peeled = await peelAny(frames.single, [host]);
      expect(peeled.cmd, GarlicBuilder.cmdDeliverAcked);
      expect(peeled.returnHops, isEmpty);
    });

    test('G4: a send that stops early resets lastOwnRgbShape', () async {
      final (_, export) = await makeHost();
      final (client, socket, _) = await setupClient(hostExport: export);
      addTearDown(client.disconnect);
      socket.onCommandFrame = (cmd, payload) {};
      final channel = await channelWithOwnOh(client);
      await client.sendMessage(channel.id, 'first');
      expect(client.lastOwnRgbShape, OwnReplyPathShape.hostClosed);
      await expectLater(
        client.sendMessage('unknown-channel', 'no keys'),
        throwsA(isA<StateError>()),
      );
      expect(client.lastOwnRgbShape, OwnReplyPathShape.none);
    });
  });

  group('T180 diagnostics: send.attempt and ack.*', () {
    final events = <DiagEvent>[];
    setUp(() {
      RpDiag.resetForTesting();
      events.clear();
      RpDiag.sink = events.add;
      RpDiag.setEnabled(true);
    });
    tearDown(RpDiag.resetForTesting);

    List<DiagEvent> named(String name) =>
        events.where((e) => e.name == name).toList();

    /// Answers the next fetch (152) with [items] and every batch ack (156).
    void serveMailbox(ScriptedSocket socket, List<MailItem> items) {
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 152) {
          final response = FetchResponse()
            ..status = Status.OK
            ..nextCursor = fixnum.Int64(items.length);
          response.items.addAll(items);
          socket.replyCommand(153, response.writeToBuffer());
        } else if (cmd == 156) {
          socket.replyCommand(
            157,
            (AckFetchResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };
    }

    test(
      'a forward send names every station, the packet hash, the ack tag '
      'and the return path; R-ACK, Channel-ACK and timeout follow it',
      () async {
        final (host, export) = await makeHost();
        final (client, socket, relays) = await setupClient(hostExport: export);
        addTearDown(client.disconnect);
        final frames = <Uint8List>[];
        socket.onCommandFrame = (cmd, payload) {
          if (cmd == 142) frames.add(payload);
        };
        late OHRegistration oh;
        final channel = await channelWithOwnOh(client, onOh: (o) => oh = o);

        final messageId = await client.sendMessage(channel.id, 'trace me');
        await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
        final peeled = await peelAny(frames.single, [...relays, host]);
        final (path, _, _) = await peel(frames.single, relays);

        final attempt = named(DiagEvt.sendAttempt).single.attrs;
        expect(attempt[DiagKey.kind], 'forward');
        expect(attempt[DiagKey.msg], messageId);
        expect(attempt[DiagKey.channel], channel.id);
        expect(attempt[DiagKey.target], HEX.encode(counterpartOhId));
        expect(attempt[DiagKey.route], 0);
        expect(
          attempt[DiagKey.hops],
          path.map((h) => HEX.encode(h.nodeId)).join(','),
        );
        expect(attempt[DiagKey.submit], 'scripted:1');
        expect(attempt[DiagKey.submitNode], HEX.encode(host.nodeId));
        expect(attempt[DiagKey.pktHash], RpDiag.hash16(frames.single));
        expect(attempt[DiagKey.ackRequested], isTrue);
        expect(attempt[DiagKey.ackTag], HEX.encode(peeled.ackTag!));
        expect(attempt[DiagKey.retHops], peeled.returnHops!.join(','));
        expect(attempt[DiagKey.selfHop], isFalse);

        // The R-ACK lands in our mailbox.
        final rAck = RoutingAck(
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          status: RoutingAck.statusStored,
        ).encode();
        serveMailbox(socket, [
          MailItem(
            receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
            payload: rAck,
            sequenceId: fixnum.Int64(1),
            sessionTag: peeled.ackTag,
          ),
        ]);
        await client.fetchMessages(oh);
        final routed = named(DiagEvt.ackRouted).single.attrs;
        expect(routed[DiagKey.msg], messageId);
        expect(routed[DiagKey.ackTag], HEX.encode(peeled.ackTag!));
        expect(routed[DiagKey.status], RoutingAck.statusStored);
        expect(routed[DiagKey.latencyMs], isA<int>());
        final rAckItem = named(DiagEvt.fetchItem).single.attrs;
        expect(rAckItem[DiagKey.kind], 'r-ack');
        expect(rAckItem[DiagKey.outcome], 'accepted');
        expect(rAckItem[DiagKey.mailbox], HEX.encode(ownOhId));
        expect(rAckItem[DiagKey.itemHash], RpDiag.hash16(rAck));
        expect(rAckItem[DiagKey.sessionTag], HEX.encode(peeled.ackTag!));

        // The partner confirms with a Channel-ACK.
        final partner = await RatchetSession.create(
          channelKey: channel.encryptionKey,
          isChannelCreator: false,
        );
        final channelAck = await partner.encrypt(
          ChannelMessage(
            messageId: Uint8List(16),
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            content: '',
            ackMessageId: Uint8List.fromList(HEX.decode(messageId)),
          ),
          channel.id,
        );
        serveMailbox(socket, [
          MailItem(
            receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
            payload: channelAck,
            sequenceId: fixnum.Int64(2),
          ),
        ]);
        await client.fetchMessages(oh);
        final delivered = named(DiagEvt.ackDelivered).single.attrs;
        expect(delivered[DiagKey.msg], messageId);
        expect(delivered[DiagKey.mailbox], HEX.encode(ownOhId));
        expect(delivered[DiagKey.latencyMs], isA<int>());
        expect(
          named(DiagEvt.fetchItem).last.attrs[DiagKey.kind],
          'channel-ack',
        );

        // A second message whose R-ACK never comes.
        frames.clear();
        socket.onCommandFrame = (cmd, payload) {
          if (cmd == 142) frames.add(payload);
        };
        final lost = await client.sendMessage(channel.id, 'lost');
        client.reapExpiredAcksForTesting(
          DateTime.now()
              .add(RedPandaLightClient.ackTimeout)
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        );
        final timeout = named(DiagEvt.ackTimeout).single.attrs;
        expect(timeout[DiagKey.msg], lost);
        expect(timeout[DiagKey.channel], channel.id);
        expect(
          timeout[DiagKey.waitedMs] as int,
          greaterThan(RedPandaLightClient.ackTimeout.inMilliseconds),
        );

        for (final e in events) {
          expect(
            DiagCatalogue.events[e.name],
            containsAll(e.attrs.keys),
            reason: '${e.name} carries a key outside the catalogue',
          );
        }
      },
    );

    test('exactly one fetch.item per item: a malformed R-ACK and an '
        'undecryptable item are reported once each, as dropped', () async {
      final (host, export) = await makeHost();
      final (client, socket, relays) = await setupClient(hostExport: export);
      addTearDown(client.disconnect);
      final frames = <Uint8List>[];
      socket.onCommandFrame = (cmd, payload) {
        if (cmd == 142) frames.add(payload);
      };
      late OHRegistration oh;
      final channel = await channelWithOwnOh(client, onOh: (o) => oh = o);
      await client.sendMessage(channel.id, 'needs an ack tag');
      await waitFor(() => frames.isNotEmpty, description: 'garlic frame');
      final peeled = await peelAny(frames.single, [...relays, host]);
      events.clear();

      final badAck = Uint8List.fromList([0xff, 0xff, 0xff]);
      final garbage = Uint8List.fromList(List<int>.filled(64, 3));
      serveMailbox(socket, [
        MailItem(
          receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
          payload: badAck,
          sequenceId: fixnum.Int64(1),
          sessionTag: peeled.ackTag,
        ),
        MailItem(
          receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
          payload: garbage,
          sequenceId: fixnum.Int64(2),
        ),
      ]);
      await client.fetchMessages(oh);
      final items = named(DiagEvt.fetchItem);
      expect(items, hasLength(2));
      final ack = items.singleWhere(
        (e) => e.attrs[DiagKey.itemHash] == RpDiag.hash16(badAck),
      );
      expect(ack.attrs[DiagKey.kind], 'r-ack');
      expect(ack.attrs[DiagKey.outcome], 'dropped');
      expect(ack.attrs[DiagKey.reason], 'malformed_r_ack');
      final bad = items.singleWhere(
        (e) => e.attrs[DiagKey.itemHash] == RpDiag.hash16(garbage),
      );
      expect(bad.attrs[DiagKey.outcome], 'dropped');
      expect(bad.attrs[DiagKey.reason], startsWith('processing_failed'));
      expect(named(DiagEvt.ackRouted), isEmpty);
    });

    test(
      'a mailbox without channel keys reports every item as no_key',
      () async {
        final (_, export) = await makeHost();
        final (client, socket, _) = await setupClient(hostExport: export);
        addTearDown(client.disconnect);
        final oh = OHRegistration(
          ohId: ownOhId,
          keypair: await OHKeypair.generate(),
          expiresAtMs: DateTime.now()
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          channelId: 'unknown-channel',
          serverEndpoint: 'scripted:1',
        );
        await client.restoreOutboundHandle(oh);
        serveMailbox(socket, [
          for (var i = 0; i < 2; i++)
            MailItem(
              receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
              payload: List<int>.filled(30, i),
              sequenceId: fixnum.Int64(i + 1),
            ),
        ]);
        await client.fetchMessages(oh);
        final items = named(DiagEvt.fetchItem);
        expect(items, hasLength(2));
        for (final e in items) {
          expect(e.attrs[DiagKey.outcome], 'dropped');
          expect(e.attrs[DiagKey.reason], 'no_key');
        }
      },
    );

    test('a tagged item with an unknown session tag is reported as dropped '
        'with its reason', () async {
      final (_, export) = await makeHost();
      final (client, socket, _) = await setupClient(hostExport: export);
      addTearDown(client.disconnect);
      late OHRegistration oh;
      await channelWithOwnOh(client, onOh: (o) => oh = o);
      final payload = Uint8List.fromList(List<int>.filled(40, 9));
      serveMailbox(socket, [
        MailItem(
          receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
          payload: payload,
          sequenceId: fixnum.Int64(1),
          sessionTag: List<int>.filled(16, 0xab),
        ),
      ]);
      await client.fetchMessages(oh);
      final item = named(DiagEvt.fetchItem).single.attrs;
      expect(item[DiagKey.outcome], 'dropped');
      expect(item[DiagKey.reason], 'session_tag_unknown_or_consumed');
      expect(item[DiagKey.itemHash], RpDiag.hash16(payload));
      expect(item[DiagKey.sessionTag], 'ab' * 16);
    });
  });
}
