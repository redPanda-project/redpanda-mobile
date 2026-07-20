@Tags(['e2e'])
@Retry(2)
@Timeout(Duration(minutes: 10))
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

/// T45 + T41 acceptance, end to end against the reference JAR.
///
/// T45: a deposit is NEVER sent as a direct FlaschenpostPut anymore — every
/// send travels over garlic (command 142). T41: a garlic one-shot over a DEAD
/// relay hop is silently dropped, so the send path must survive it by
/// re-sending over FRESH hops until the message lands.
///
/// Topology (suite-private ports, T30): one isolated entry node that both
/// clients talk to, four relay candidates seeded with the entry address. THREE
/// relays stay alive; the FOURTH is started (so Alice learns it as a hop
/// candidate with its X25519 key over the peer exchange) and then STOPPED — a
/// provably dead hop, exactly the realnet 2026-07-18 situation. Alice's hop
/// selector picks 3 of the 4 candidates per attempt, so many attempts route
/// through the dead hop and are lost; the retry over fresh hops eventually
/// picks three live relays and Bob receives the message. Bob's OH lives on the
/// entry node; the final live relay forwards the deposit to it (MS02b).
void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  const entryPort = 50590;
  const liveRelayPorts = [50591, 50592, 50593];
  const deadRelayPort = 50594;
  const entryAddress = '127.0.0.1:$entryPort';
  final liveRelayAddresses = liveRelayPorts.map((p) => '127.0.0.1:$p').toSet();
  const deadRelayAddress = '127.0.0.1:$deadRelayPort';
  // Alice may pick ANY of the four candidates (three live + one dead).
  final allRelayAddresses = {...liveRelayAddresses, deadRelayAddress};

  group('E2E T45/T41: garlic-only delivery survives a dead relay hop', () {
    final launchers = <RedPandaNodeLauncher>[];
    RedPandaNodeLauncher? deadRelay;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;

    setUp(() async {
      // Entry node first, isolated (T29 'none'); the relays are seeded with
      // the entry address (T30) so they connect at boot and inter-connect via
      // the periodic peer-list exchange.
      for (final port in [entryPort, ...liveRelayPorts]) {
        final launcher = RedPandaNodeLauncher(
          port: port,
          seeds: [if (port != entryPort) entryAddress],
        );
        launchers.add(launcher);
        await launcher.start();
      }
      // The soon-to-be-dead relay: start it so its identity + X25519 key reach
      // Alice through the peer exchange, then stop it mid-test.
      deadRelay = RedPandaNodeLauncher(
        port: deadRelayPort,
        seeds: [entryAddress],
      );
      await deadRelay!.start();

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
        // Pin hop candidates to the four local relays so discovered
        // public-internet nodes never become hops in this test.
        hopCandidateFilter: (peer) => allRelayAddresses.contains(peer.address),
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
      // deadRelay is normally stopped mid-test; stop again is a no-op safety.
      await deadRelay?.stop();
      deadRelay = null;
    });

    /// Polls until Alice knows all FOUR relay candidates incl. their X25519
    /// keys (learned from the entry node's peer list).
    Future<void> waitForAllRelayCandidates() async {
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (true) {
        final known = alice
            .getDebugPeerStats()
            .where(
              (p) =>
                  allRelayAddresses.contains(p.address) &&
                  p.encryptionPublicKey != null &&
                  p.nodeId != null,
            )
            .length;
        if (known >= allRelayAddresses.length) return;
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'Alice discovered only $known of ${allRelayAddresses.length} '
            'relay candidates with encryption keys',
          );
        }
        alice.requestPeerLists();
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    test(
      'a dead garlic hop is survived by re-sending over fresh hops',
      () async {
        await alice.connect();
        expect(await waitForEncryption(alice), isTrue);
        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);

        final channel = await Channel.generate('T45 Garlic-only');
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

        await waitForAllRelayCandidates();
        // Let the relay interconnections settle (30-second peer-list cycle).
        await Future.delayed(const Duration(seconds: 5));

        // Kill one relay AFTER Alice learned it: from now on it is a dead hop
        // that the selector may still pick.
        await deadRelay!.stop();
        deadRelay = null;
        await Future.delayed(const Duration(seconds: 2));

        // Garlic delivery is fire-and-forget: re-send the SAME logical message
        // id until Bob's poll sees it. Every attempt picks fresh hops, so an
        // attempt that routed through the now-dead relay is repaired by a later
        // attempt that happens to pick three live relays (T41).
        const content = 'garlic-only survives a dead hop';
        String? messageId;
        final received = DeliveryCollector(bob);
        addTearDown(received.cancel);

        for (var attempt = 0; attempt < 12; attempt++) {
          messageId = await alice.sendMessage(
            channel.id,
            content,
            messageId: messageId,
          );
          expect(
            alice.lastSendHopCount,
            greaterThan(0),
            reason:
                'the send must travel a garlic path, never a direct deposit',
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
          reason:
              'the garlic-routed message must reach Bob despite the dead hop',
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
