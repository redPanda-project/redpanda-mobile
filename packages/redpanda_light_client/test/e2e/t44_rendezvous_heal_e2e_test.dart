@Tags(['e2e'])
@Retry(2)
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// T44 acceptance, end to end against the reference JAR: a channel heals purely
/// over the DHT rendezvous record when there is NO in-band path between the
/// peers.
///
/// Bob shares a v4 QR (only the channel secret) with Alice. Neither side is
/// ever told the other's OH in band — the only way Bob can learn where to
/// deposit for Alice is the rendezvous record Alice publishes into the DHT.
///
/// Topology: three local nodes A/B/C seeded together (isolated from the public
/// testnet). Alice's mailbox is on node A; she publishes the rendezvous record
/// on registration (`record_store`, garlic-wrapped to a remote node). Bob is on
/// node C, holds the same channel secret but no peer OH. His first send finds
/// no peer mailbox and triggers a rendezvous recovery (`record_lookup`,
/// garlic-wrapped; the answer returns via reverse garlic into Bob's own OH
/// mailbox). Bob adopts Alice's OH from the decrypted record and his next send
/// is delivered — the channel bootstrapped itself over the DHT alone.
void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  const portA = 50631; // Alice's mailbox host
  const portB = 50632; // relay / DHT replica
  const portC = 50633; // Bob's mailbox host
  const nodeA = '127.0.0.1:$portA';
  const nodeB = '127.0.0.1:$portB';
  const nodeC = '127.0.0.1:$portC';

  group('E2E T44: channel heals over the DHT rendezvous record', () {
    late RedPandaNodeLauncher launcherA;
    late RedPandaNodeLauncher launcherB;
    late RedPandaNodeLauncher launcherC;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;

    setUp(() async {
      launcherA = RedPandaNodeLauncher(port: portA, seeds: [nodeB, nodeC]);
      launcherB = RedPandaNodeLauncher(port: portB, seeds: [nodeA, nodeC]);
      launcherC = RedPandaNodeLauncher(port: portC, seeds: [nodeA, nodeB]);
      await launcherA.start();
      await launcherB.start();
      await launcherC.start();

      // Garlic hops are REQUIRED here: record_store/record_lookup travel
      // garlic-wrapped to a remote node, so (unlike the T42 direct-deposit
      // test) hop candidates must stay enabled.
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
        seeds: [nodeC],
      );
    });

    tearDown(() async {
      await alice.disconnect();
      await bob.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      await launcherA.stop();
      await launcherB.stop();
      await launcherC.stop();
    });

    Future<void> waitConnected(RedPandaLightClient c, String endpoint) async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!c.activePeerAddresses.contains(endpoint)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('client never connected to $endpoint');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    test(
      'Bob discovers Alice\'s OH purely from the DHT record and delivers',
      () async {
        await alice.connect();
        expect(await waitForEncryption(alice), isTrue);
        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);

        // Both hold the SAME channel secret (v4 QR); Alice is the creator.
        final channel = await Channel.generate('T44 Rendezvous Heal');
        final joiner = await Channel.fromJson(channel.toJson());
        expect(joiner.channelSecret, channel.channelSecret);

        // Give both clients the full node set so garlic routing has hops.
        await alice.addPeer(nodeB);
        await alice.addPeer(nodeC);
        await bob.addPeer(nodeA);
        await bob.addPeer(nodeB);
        await waitConnected(alice, nodeB);
        await waitConnected(alice, nodeC);
        await waitConnected(bob, nodeA);
        await waitConnected(bob, nodeB);

        // Alice registers her mailbox (on node A) and publishes the rendezvous
        // record. Crucially, addChannelKeys carries the channel secret so the
        // publish path is armed before the OH registration fires it.
        alice.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          channelSecret: channel.channelSecret,
          ownDisplayName: 'Alice',
          isChannelCreator: true,
        );
        final aliceOH = await alice.registerOutboundHandle(
          channelId: channel.id,
        );
        expect(aliceOH.serverEndpoint, nodeA);

        // Bob knows the secret but NOT Alice's OH — no in-band path exists.
        bob.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          channelSecret: channel.channelSecret,
          ownDisplayName: 'Bob',
          isChannelCreator: false,
        );
        // Bob needs his own mailbox to receive the record_lookup answer.
        await bob.registerOutboundHandle(channelId: channel.id);

        // Let Alice's record_store propagate through the DHT.
        await Future.delayed(const Duration(seconds: 8));

        final peerOhMoves = <PeerOhUpdate>[];
        final sub = bob.peerOhUpdates.listen(peerOhMoves.add);
        addTearDown(sub.cancel);

        // Bob's first send finds no peer OH and triggers a rendezvous recovery.
        // Retry: the lookup + reverse-garlic answer + fetch cycle takes a few
        // poll intervals, and each failed send re-arms the recovery.
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (peerOhMoves.isEmpty) {
          try {
            await bob.sendMessage(channel.id, 'heal me over the DHT');
          } catch (_) {
            // Expected until the peer OH is recovered from the DHT record.
          }
          if (DateTime.now().isAfter(deadline)) {
            fail('Bob never recovered Alice\'s OH from the rendezvous record');
          }
          await Future.delayed(const Duration(seconds: 5));
        }

        // Bob adopted Alice's mailbox purely from the decrypted DHT record.
        expect(
          peerOhMoves.last.descriptors.map((d) => d.serverEndpoint),
          contains(nodeA),
          reason: 'Bob must learn Alice\'s node-A mailbox from the DHT record',
        );

        // And the channel now works: Bob's send reaches Alice.
        final aliceInbox = DeliveryCollector(alice);
        addTearDown(aliceInbox.cancel);
        const hello = 'hello over the healed channel';
        String? id;
        for (var attempt = 0; attempt < 8; attempt++) {
          id = await bob.sendMessage(channel.id, hello, messageId: id);
          await aliceInbox.waitUntil(
            (m) => m.any((x) => x.content == hello),
            timeout: const Duration(seconds: 12),
          );
          if (aliceInbox.messages.any((x) => x.content == hello)) break;
        }
        expect(
          aliceInbox.messages.map((m) => m.content),
          contains(hello),
          reason: 'delivery must succeed over the DHT-discovered mailbox',
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
