import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
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
  Future<(RedPandaLightClient, ScriptedSocket, List<TestHop>)> setupClient({
    Uint8List? hostExport,
  }) async {
    final relays = <TestHop>[];
    final repo = InMemoryPeerRepository();
    for (var i = 0; i < 3; i++) {
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
}
