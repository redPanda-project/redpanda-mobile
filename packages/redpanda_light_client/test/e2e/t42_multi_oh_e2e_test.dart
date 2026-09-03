@Tags(['e2e'])
@Retry(2)
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// T42 acceptance, end to end against the reference JAR: with TWO of Bob's own
/// mailboxes on disjoint nodes, a dead OH-host node no longer stalls delivery —
/// Alice's send fans out to both mailboxes and the copy on the surviving node
/// arrives WITHOUT waiting for a T21 failover cycle.
///
/// Topology: three local nodes seeded with each other (isolated from the
/// public testnet via REDPANDA_KNOWN_NODES). Bob's first mailbox lives on
/// node A, his redundant one (via [RedPandaLightClient.ensureOhRedundancy]) on
/// node B, the third of the k=3 set on node C; Alice's mailbox is on node C. Bob announces the whole set to Alice as an
/// in-band `oh_update` JSON array. Node A is then stopped:
///
///  1. Alice already knows BOTH of Bob's mailboxes, so her next send deposits
///     into both in parallel — the copy for node B lands immediately.
///  2. Bob receives it over his production poll loop from the node-B mailbox.
///
/// No failover, no oh_update round-trip, no multi-cycle wait is needed for the
/// message to get through.
void main() async {
  final jarAvailable = e2eJarAvailable();

  const portA = 50621; // Bob's first mailbox host — stopped mid-test
  const portB = 50622; // Bob's redundant mailbox host — stays alive
  const portC = 50623; // Alice's mailbox host
  const nodeA = '127.0.0.1:$portA';
  const nodeB = '127.0.0.1:$portB';
  const nodeC = '127.0.0.1:$portC';

  group('E2E T42: multi-OH redundancy survives a dead OH host', () {
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

      // Sends go direct (no garlic): the redundancy set is exercised exactly
      // when a host may be dead, and a garlic one-shot over a possibly-dead
      // hop can silently drop the message (T41). The multi-deposit path is
      // direct anyway; disabling hops keeps the single-OH warm-up direct too.
      final aliceKeys = await KeyPair.generate();
      alice = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(aliceKeys),
        selfKeys: aliceKeys,
        seeds: [nodeC],
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

    test('delivery over the second OH when the first OH host dies', () async {
      await bob.connect();
      expect(await waitForEncryption(bob), isTrue);
      await alice.connect();
      expect(await waitForEncryption(alice), isTrue);

      // Bob's FIRST mailbox pins to node A (his only verified peer here).
      final channel = await Channel.generate('T42 Multi-OH');
      final bobOH1 = await bob.registerOutboundHandle(channelId: channel.id);
      expect(bobOH1.serverEndpoint, nodeA);
      // Alice's mailbox pins to node C.
      final aliceOH = await alice.registerOutboundHandle(channelId: channel.id);
      expect(aliceOH.serverEndpoint, nodeC);

      alice.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        peerOhId: bobOH1.ohId,
        peerOhEndpoint: nodeA,
        isChannelCreator: true,
      );
      bob.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        peerOhId: aliceOH.ohId,
        peerOhEndpoint: nodeC,
        isChannelCreator: false,
      );

      // Bob connects to node B — where his redundant mailbox will live — and
      // Alice connects to A and B so her fan-out can reach both of Bob's
      // mailboxes (through the node hosting each).
      await bob.addPeer(nodeB);
      await waitConnected(bob, nodeB);
      await alice.addPeer(nodeA);
      await alice.addPeer(nodeB);
      await waitConnected(alice, nodeA);
      await waitConnected(alice, nodeB);

      // Alice learns Bob's full mailbox set in-band.
      final peerOhMoves = <PeerOhUpdate>[];
      final peerOhSub = alice.stateUpdates.of<PeerOhUpdate>().listen(
        peerOhMoves.add,
      );
      addTearDown(peerOhSub.cancel);

      // Bob tops up to the full k=3 target and announces the set. All three
      // nodes are seeded with each other, so Bob reaches every one of them
      // and the top-up finds a disjoint host for each mailbox.
      await bob.ensureOhRedundancy(channel.id);
      final bobOwnOhs = bob.registeredOutboundHandles
          .where((oh) => oh.channelId == channel.id)
          .toList();
      expect(
        bobOwnOhs.length,
        RedPandaLightClient.ohRedundancy,
        reason: 'Bob must hold the full k=3 set of own mailboxes',
      );
      final bobEndpoints = bobOwnOhs.map((oh) => oh.serverEndpoint).toSet();
      expect(
        bobEndpoints.length,
        bobOwnOhs.length,
        reason: 'no two of Bob\'s mailboxes may share a host node',
      );
      // The scenario below kills node A, so the set must span A and B — the
      // third mailbox lands on C and is incidental to the failover check.
      expect(bobEndpoints, containsAll(<String>{nodeA, nodeB}));

      final announceDeadline = DateTime.now().add(const Duration(seconds: 90));
      while (peerOhMoves.isEmpty || peerOhMoves.last.descriptors.length < 2) {
        if (DateTime.now().isAfter(announceDeadline)) {
          fail('Alice never received the two-mailbox oh_update');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      expect(
        peerOhMoves.last.descriptors.map((d) => d.serverEndpoint).toSet(),
        containsAll(<String>{nodeA, nodeB}),
      );

      final bobInbox = DeliveryCollector(bob);
      addTearDown(bobInbox.cancel);

      // Sanity: the channel works while all nodes are alive.
      const before = 'before the node dies';
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

      // ── Node A dies (Bob's FIRST mailbox host). ──────────────────────
      await launcherA.stop();
      await Future.delayed(const Duration(seconds: 3));

      // Alice's next send fans out to BOTH of Bob's mailboxes. The copy for
      // node A is lost, the copy for node B lands immediately — Bob receives
      // it over his poll loop from the node-B mailbox. This must succeed
      // WITHOUT a failover: Bob still holds exactly the two original OHs.
      const after = 'after the node dies';
      String? afterId;
      for (var attempt = 0; attempt < 6; attempt++) {
        afterId = await alice.sendMessage(
          channel.id,
          after,
          messageId: afterId,
        );
        await bobInbox.waitUntil(
          (m) => m.any((x) => x.content == after),
          timeout: const Duration(seconds: 10),
        );
        if (bobInbox.messages.any((x) => x.content == after)) break;
      }
      expect(
        bobInbox.messages.map((m) => m.content),
        contains(after),
        reason: 'the message must arrive over the surviving second OH',
      );
    }, skip: jarAvailable ? null : 'RedPanda JAR not found');
  });
}
