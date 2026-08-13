@Tags(['e2e'])
@Retry(2)
@Timeout(Duration(minutes: 8))
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// MS04 acceptance, end to end against the reference JAR:
///
/// Alice builds a 3-layer Flaschenpost v2 garlic packet and submits it to her
/// connected node. Three local relay nodes peel exactly their own layer and
/// forward the rebuilt 2048-byte packet; the last relay deposits the payload
/// into Bob's OH mailbox (MS02b fallback forwarding, since the OH lives on
/// Alice's/Bob's entry node). Bob fetches and decrypts the message.
///
/// Topology (T30): suite-private ports — the isolated entry node plus three
/// relays that are explicitly seeded with the entry address, so they connect
/// to it at boot and inter-connect through the periodic peer list exchange.
/// No suite shares ports anymore, so there is no topology lock.
void main() async {
  final jarAvailable = e2eJarAvailable();

  const entryPort = 50570;
  const relayPorts = [50571, 50572, 50573];
  const entryAddress = '127.0.0.1:$entryPort';
  final relayAddresses = relayPorts.map((p) => '127.0.0.1:$p').toSet();

  group('E2E MS04: multi-hop garlic delivery across 4 real nodes', () {
    final launchers = <RedPandaNodeLauncher>[];
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;
    setUp(() async {
      // Entry node first, isolated (T29 'none'); the relays are seeded
      // explicitly with the entry address (T30) — no dependency on the
      // JAR's built-in 127.0.0.1:59558 seed, so a foreign node on that
      // port can no longer contaminate the topology.
      for (final port in [entryPort, ...relayPorts]) {
        final launcher = RedPandaNodeLauncher(
          port: port,
          seeds: [if (port != entryPort) entryAddress],
        );
        launchers.add(launcher);
        await launcher.start();
      }

      // Both clients talk only to the entry node: Alice's relay candidates
      // must stay *known peers*, not connections (deterministic submission
      // path), and the hop candidate filter pins the three local relays so
      // discovered public-internet nodes never become hops in this test.
      Future<Socket> entryOnly(String host, int port) {
        if ('$host:$port' != entryAddress) {
          throw const SocketException('test client only dials the entry node');
        }
        return Socket.connect(host, port);
      }

      final aliceKeys = await KeyPair.generate();
      alice = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(aliceKeys),
        selfKeys: aliceKeys,
        seeds: [entryAddress],
        socketFactory: entryOnly,
        hopCandidateFilter: (peer) => relayAddresses.contains(peer.address),
      );

      final bobKeys = await KeyPair.generate();
      bob = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(bobKeys),
        selfKeys: bobKeys,
        seeds: [entryAddress],
        socketFactory: entryOnly,
      );
    });

    tearDown(() async {
      await alice.disconnect();
      await bob.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      for (final launcher in launchers) {
        await launcher.stop();
      }
      launchers.clear();
    });

    /// Polls until Alice knows all three relays incl. their X25519 keys
    /// (the entry node learns the relay identities during their handshakes
    /// and shares them in the peer list).
    Future<void> waitForRelayCandidates() async {
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (true) {
        final known = alice
            .getDebugPeerStats()
            .where(
              (p) =>
                  relayAddresses.contains(p.address) &&
                  p.encryptionPublicKey != null &&
                  p.nodeId != null,
            )
            .length;
        if (known >= relayAddresses.length) return;
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'Alice discovered only $known of ${relayAddresses.length} relay '
            'candidates with encryption keys',
          );
        }
        alice.requestPeerLists();
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    test(
      'Alice sends over 3 garlic hops; Bob receives the message',
      () async {
        await alice.connect();
        expect(await waitForEncryption(alice), isTrue);
        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);

        final channel = await Channel.generate('MS04 Garlic');
        final bobOH = await bob.registerOutboundHandle(channelId: channel.id);
        alice.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          peerOhId: bobOH.ohId,
          peerOhEndpoint: entryAddress,
          isChannelCreator: true,
        );
        bob.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          isChannelCreator: false,
        );

        await waitForRelayCandidates();
        // Give the OH announce and the relay interconnections a moment —
        // the relays exchange peer lists on a 30-second cycle.
        await Future.delayed(const Duration(seconds: 5));

        // Garlic delivery is fire-and-forget (no R-ACK before MS06), so the
        // test mirrors the MS02 retry queue: re-send the SAME logical
        // message id until Bob's poll (Connection-Notify auto-fetch) sees it.
        // Every attempt picks fresh hops, so a single struggling relay cannot
        // fail the test.
        const content = 'Multi-hop garlic hello!';
        String? messageId;
        final received = DeliveryCollector(bob);
        addTearDown(received.cancel);

        for (var attempt = 0; attempt < 6; attempt++) {
          messageId = await alice.sendMessage(
            channel.id,
            content,
            messageId: messageId,
          );
          expect(
            alice.lastSendHopCount,
            equals(3),
            reason: 'the message must travel the full 3-hop garlic path',
          );
          await received.waitUntil(
            (m) => m.any((x) => x.content == content),
            timeout: const Duration(seconds: 12),
          );
          if (received.messages.any((x) => x.content == content)) break;
        }

        expect(
          received.messages.map((m) => m.content),
          contains(content),
          reason: 'the garlic-routed message must reach Bob\'s OH mailbox',
        );
        expect(
          received.messages.firstWhere((m) => m.content == content).id,
          equals(messageId),
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
