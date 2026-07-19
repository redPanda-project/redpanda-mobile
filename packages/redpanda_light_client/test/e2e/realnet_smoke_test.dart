@Tags(['e2e'])
library;

// Smoke test against the REAL testnet (2026-07-11): Alice on node A,
// Bob on node B, message exchange in both directions across the network.
// Local-only tool — not part of CI (needs the live testnet).

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'test_helpers.dart';

const nodeA = '5.75.137.166:59558';
const nodeB = '46.224.156.238:59558';

/// Mirrors the app's SendRetryQueue: re-send periodically until the
/// receiver's fetch shows the content (fresh DHT announces race the first
/// deposits on a young network — best-effort drops are expected).
Future<bool> sendUntilDelivered(
  RedPandaLightClient sender,
  String channelId,
  String content,
  RedPandaLightClient receiver,
  dynamic receiverOh, {
  Duration timeout = const Duration(seconds: 150),
}) async {
  final deadline = DateTime.now().add(timeout);
  var attempt = 0;
  while (DateTime.now().isBefore(deadline)) {
    attempt++;
    try {
      await sender.sendMessage(channelId, content);
    } catch (e) {
      print('  send attempt $attempt failed: $e');
    }
    for (var i = 0; i < 4; i++) {
      await Future.delayed(const Duration(seconds: 3));
      final batch = await receiver.fetchMessages(receiverOh);
      if (batch.any((m) => m.content == content)) {
        print('  delivered after $attempt send attempt(s)');
        return true;
      }
    }
  }
  return false;
}

void main() {
  late RedPandaLightClient alice;
  late RedPandaLightClient bob;

  setUp(() async {
    final aliceKeys = await KeyPair.generate();
    alice = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(aliceKeys),
      selfKeys: aliceKeys,
      seeds: [nodeA],
    );
    final bobKeys = await KeyPair.generate();
    bob = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(bobKeys),
      selfKeys: bobKeys,
      seeds: [nodeB],
    );
  });

  tearDown(() async {
    await alice.disconnect();
    await bob.disconnect();
  });

  test(
    'real-net: Alice (node A) <-> Bob (node B) both directions',
    () async {
      await alice.connect();
      expect(
        await waitForEncryption(alice),
        isTrue,
        reason: 'Alice: encrypted session to $nodeA',
      );
      await bob.connect();
      expect(
        await waitForEncryption(bob),
        isTrue,
        reason: 'Bob: encrypted session to $nodeB',
      );

      // Bob creates the channel, registers his OH on node B.
      final channel = await Channel.generate('realnet-smoke');
      final bobOH = await bob.registerOutboundHandle(channelId: channel.id);
      bob.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
      );

      // Alice joins with Bob's OH descriptor (as if scanned from QR).
      final bobDescriptor = OHDescriptor(
        serverEndpoint: nodeB,
        handleId: bobOH.ohId,
        authPublicKey: bobOH.keypair.publicKeyBytes.toList(),
      );
      alice.addChannelKeys(
        channel.copyWith(peerOhDescriptor: bobDescriptor).id,
        channel.encryptionKey,
        peerOhId: bobOH.ohId,
        isChannelCreator: false,
      );

      // Alice -> Bob across the network (node A -> node B).
      expect(
        await sendUntilDelivered(
          alice,
          channel.id,
          'Hallo Bob — echtes Netz!',
          bob,
          bobOH,
        ),
        isTrue,
        reason: 'Alice->Bob across nodes',
      );
      print('OK  Alice -> Bob zugestellt');

      // Reply direction: Alice registers her own OH on node A.
      final aliceOH = await alice.registerOutboundHandle(channelId: channel.id);
      final aliceDescriptor = OHDescriptor(
        serverEndpoint: nodeA,
        handleId: aliceOH.ohId,
        authPublicKey: aliceOH.keypair.publicKeyBytes.toList(),
      );
      bob.addChannelKeys(
        channel.copyWith(peerOhDescriptor: aliceDescriptor).id,
        channel.encryptionKey,
        peerOhId: aliceOH.ohId,
        isChannelCreator: true,
      );

      expect(
        await sendUntilDelivered(
          bob,
          channel.id,
          'Hallo Alice — Antwort!',
          alice,
          aliceOH,
        ),
        isTrue,
        reason: 'Bob->Alice across nodes',
      );
      print('OK  Bob -> Alice zugestellt');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
