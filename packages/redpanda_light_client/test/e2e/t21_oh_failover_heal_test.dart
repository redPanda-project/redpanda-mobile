@Tags(['e2e'])
@Retry(2)
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// T21 acceptance, end to end against the reference JAR: a channel heals
/// itself over a second node when its own-mailbox host dies.
///
/// Topology: two local nodes seeded with each other (isolated from the
/// public testnet via REDPANDA_KNOWN_NODES). Bob's mailbox lives on node A,
/// Alice's on node B. Node A is then stopped:
///
///  1. Bob's fetches fail host-unreachable while node B stays verified —
///     after the threshold his client registers a REPLACEMENT mailbox on
///     node B and publishes it via [RedPandaLightClient.ohRegistrationUpdates].
///  2. The replacement descriptor travels IN-BAND to Alice as a
///     ratchet-encrypted `oh_update` into her (still healthy) mailbox on
///     node B; her [RedPandaLightClient.peerOhUpdates] fires.
///  3. Alice's next send deposits into Bob's NEW mailbox on node B and Bob
///     receives it over his production poll loop.
///
/// Ports are private to this suite (no 59558 dependency), so no topology
/// lock is needed.
void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  const portA = 50611; // Bob's mailbox host — stopped mid-test
  const portB = 50612; // stays alive; the channel heals over it
  const nodeA = '127.0.0.1:$portA';
  const nodeB = '127.0.0.1:$portB';

  group('E2E T21: OH failover over a second node', () {
    late RedPandaNodeLauncher launcherA;
    late RedPandaNodeLauncher launcherB;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;

    setUp(() async {
      launcherA = RedPandaNodeLauncher(port: portA, seeds: [nodeB]);
      launcherB = RedPandaNodeLauncher(port: portB, seeds: [nodeA]);
      await launcherA.start();
      await launcherB.start();

      // Garlic hops are disabled for both clients: after node A dies it is
      // guaranteed to be among the hop candidates, and a garlic one-shot
      // over a dead hop is silently lost (T41 — sender-side hop resilience
      // is its own task; in the app the R-ACK-timeout requeue papers over
      // it). This suite proves the T21 healing chain, so sends go direct.
      final aliceKeys = await KeyPair.generate();
      alice = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(aliceKeys),
        selfKeys: aliceKeys,
        seeds: [nodeB],
        hopCandidateFilter: (_) => false,
      );
      final bobKeys = await KeyPair.generate();
      bob = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(bobKeys),
        selfKeys: bobKeys,
        seeds: [nodeA],
        hopCandidateFilter: (_) => false,
      );
    });

    tearDown(() async {
      await alice.disconnect();
      await bob.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      await launcherA.stop();
      await launcherB.stop();
    });

    test(
      'channel heals itself when the mailbox host node dies',
      () async {
        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);
        await alice.connect();
        expect(await waitForEncryption(alice), isTrue);

        // Bob registers while node A is his only verified peer, Alice while
        // node B is hers — this pins the mailbox hosts deterministically.
        final channel = await Channel.generate('T21 Failover');
        final bobOH = await bob.registerOutboundHandle(channelId: channel.id);
        expect(bobOH.serverEndpoint, nodeA);
        final aliceOH = await alice.registerOutboundHandle(
          channelId: channel.id,
        );
        expect(aliceOH.serverEndpoint, nodeB);

        alice.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          peerOhId: bobOH.ohId,
          peerOhEndpoint: nodeA,
          isChannelCreator: true,
        );
        bob.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          peerOhId: aliceOH.ohId,
          peerOhEndpoint: nodeB,
          isChannelCreator: false,
        );

        // Bob additionally connects to node B — the reachable alternative his
        // failover will use.
        await bob.addPeer(nodeB);
        final altDeadline = DateTime.now().add(const Duration(seconds: 60));
        while (!bob.activePeerAddresses.contains(nodeB)) {
          if (DateTime.now().isAfter(altDeadline)) {
            fail('Bob never connected to the alternative node $nodeB');
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }

        final bobInbox = DeliveryCollector(bob);
        addTearDown(bobInbox.cancel);

        // Sanity: the channel works while node A is alive.
        const before = 'before failover';
        String? beforeId;
        for (var attempt = 0; attempt < 6; attempt++) {
          beforeId = await alice.sendMessage(
            channel.id,
            before,
            messageId: beforeId,
          );
          await bobInbox.waitUntil(
            (m) => m.any((x) => x.content == before),
            timeout: const Duration(seconds: 12),
          );
          if (bobInbox.messages.any((x) => x.content == before)) break;
        }
        expect(bobInbox.messages.map((m) => m.content), contains(before));

        // ── Node A dies. ─────────────────────────────────────────────────
        final replacements = <OHRegistration>[];
        final replacementSub = bob.ohRegistrationUpdates.listen(
          replacements.addAll,
        );
        addTearDown(replacementSub.cancel);
        final peerOhMoves = <PeerOhUpdate>[];
        final peerOhSub = alice.peerOhUpdates.listen(peerOhMoves.add);
        addTearDown(peerOhSub.cancel);

        await launcherA.stop();
        // Let Bob's connection to A actually die so fetches fail fast
        // (host-not-connected) instead of first riding a 10 s timeout each.
        await Future.delayed(const Duration(seconds: 3));

        // Drive fetch cycles explicitly (the production poll does the same,
        // just on its 5–30 s cadence — the E2E should not wait minutes).
        final failoverDeadline = DateTime.now().add(
          const Duration(seconds: 90),
        );
        while (replacements.isEmpty) {
          if (DateTime.now().isAfter(failoverDeadline)) {
            fail('Bob never failed over to the alternative node');
          }
          await bob.fetchMessages(bobOH);
          await Future.delayed(const Duration(seconds: 1));
        }

        final replacement = replacements.first;
        expect(
          replacement.serverEndpoint,
          nodeB,
          reason: 'the replacement mailbox must live on the surviving node',
        );
        expect(replacement.channelId, channel.id);

        // Alice learns the new mailbox in-band over her healthy mailbox.
        final moveDeadline = DateTime.now().add(const Duration(seconds: 90));
        while (peerOhMoves.isEmpty) {
          if (DateTime.now().isAfter(moveDeadline)) {
            fail('Alice never received the in-band oh_update');
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
        expect(peerOhMoves.first.channelId, channel.id);
        expect(
          peerOhMoves.first.descriptors.any((d) => d.serverEndpoint == nodeB),
          isTrue,
        );

        // Alice's next send reaches Bob via his NEW mailbox on node B.
        const after = 'after failover';
        String? afterId;
        for (var attempt = 0; attempt < 6; attempt++) {
          afterId = await alice.sendMessage(
            channel.id,
            after,
            messageId: afterId,
          );
          await bobInbox.waitUntil(
            (m) => m.any((x) => x.content == after),
            timeout: const Duration(seconds: 15),
          );
          if (bobInbox.messages.any((x) => x.content == after)) break;
        }
        expect(
          bobInbox.messages.map((m) => m.content),
          contains(after),
          reason: 'the channel must heal over the surviving node',
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
