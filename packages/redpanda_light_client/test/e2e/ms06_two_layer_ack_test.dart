@Tags(['e2e'])
@Retry(2)
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// MS06 acceptance, end to end against the reference JAR:
///
/// Alice sends to Bob's OH over 3 garlic hops with a CMD_DELIVER_ACKED
/// innermost layer carrying a return-path block (her own OH + a fresh ack
/// session tag + 3 return hops). The node that makes the final deposit
/// decision builds a RoutingAck onion over those return hops and deposits it
/// — tagged with the ack session tag — into Alice's own OH mailbox. Alice
/// polls her mailbox, correlates the R-ACK by its tag, and her
/// [RedPandaLightClient.routingAckUpdates] fires with status stored. Bob,
/// having received and decrypted the message, auto-sends a Channel-ACK back
/// over Alice's RGB, which flips her message to delivered.
///
/// Same topology as the MS04/MS05 E2E: entry node on 59558 (the JAR's
/// built-in local seed) + three local relays; the shared entry port is why
/// all garlic suites take the topology lock.
void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  const entryPort = 59558;
  const relayPorts = [50574, 50575, 50576];
  const entryAddress = '127.0.0.1:$entryPort';
  final relayAddresses = relayPorts.map((p) => '127.0.0.1:$p').toSet();

  group('E2E MS06: routing ack across 4 real nodes', () {
    final launchers = <RedPandaNodeLauncher>[];
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;
    ServerSocket? topologyLock;

    setUp(() async {
      topologyLock = await acquireTopologyLock();
      for (final port in [entryPort, ...relayPorts]) {
        final launcher = RedPandaNodeLauncher(port: port);
        launchers.add(launcher);
        await launcher.start();
      }

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
        hopCandidateFilter: (peer) => relayAddresses.contains(peer.address),
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
      await topologyLock?.close();
      topologyLock = null;
    });

    Future<void> waitForRelayCandidates(
      RedPandaLightClient client,
      String who,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (true) {
        final known = client
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
            '$who discovered only $known of ${relayAddresses.length} relay '
            'candidates with encryption keys',
          );
        }
        client.requestPeerLists();
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    test('Alice gets an R-ACK for her acked send and a Channel-ACK once Bob '
        'reads it', () async {
      await alice.connect();
      expect(await waitForEncryption(alice), isTrue);
      await bob.connect();
      expect(await waitForEncryption(bob), isTrue);

      final channel = await Channel.generate('MS06 Two-Layer ACK');
      final bobOH = await bob.registerOutboundHandle(channelId: channel.id);
      final aliceOH = await alice.registerOutboundHandle(channelId: channel.id);

      // Alice knows Bob's OH id (forward path) AND has her own OH for the
      // R-ACK return path — both preconditions for CMD_DELIVER_ACKED.
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
        peerOhId: aliceOH.ohId,
        peerOhEndpoint: entryAddress,
        isChannelCreator: false,
      );

      await Future.wait([
        waitForRelayCandidates(alice, 'Alice'),
        waitForRelayCandidates(bob, 'Bob'),
      ]);
      await Future.delayed(const Duration(seconds: 5));

      // Collect Alice's routing-ack feedback for the message she sends.
      final routingAcks = <RoutingAckUpdate>[];
      final ackSub = alice.routingAckUpdates.listen(routingAcks.add);

      // ── Step 1: Alice → Bob, R-ACK requested. ────────────────────────
      const hello = 'Hello Bob — please ack the route!';
      String? helloId;
      final bobInbox = <DecryptedMessage>[];

      for (var attempt = 0; attempt < 6 && bobInbox.isEmpty; attempt++) {
        helloId = await alice.sendMessage(
          channel.id,
          hello,
          messageId: helloId,
        );
        expect(alice.lastSendHopCount, 3);
        expect(
          alice.lastSendAckRequested,
          isTrue,
          reason: 'Alice has her own OH, so the send requests an R-ACK',
        );

        for (var i = 0; i < 5 && bobInbox.isEmpty; i++) {
          await Future.delayed(const Duration(seconds: 2));
          bobInbox.addAll(await bob.fetchMessages(bobOH));
        }
      }
      expect(bobInbox.map((m) => m.content), contains(hello));

      // ── Step 2: Alice fetches her own mailbox — the R-ACK is there. ───
      RoutingAckUpdate? storedAck;
      for (var i = 0; i < 15 && storedAck == null; i++) {
        await alice.fetchMessages(aliceOH);
        storedAck = routingAcks
            .where((a) => !a.timedOut && a.messageIdHex == helloId)
            .cast<RoutingAckUpdate?>()
            .firstWhere((_) => true, orElse: () => null);
        if (storedAck == null) await Future.delayed(const Duration(seconds: 2));
      }

      expect(
        storedAck,
        isNotNull,
        reason: 'Alice must receive an R-ACK for her acked send',
      );
      expect(storedAck!.status, RoutingAck.statusStored);
      expect(storedAck.channelId, channel.id);
      expect(
        storedAck.latencyMs,
        greaterThanOrEqualTo(0),
        reason: 'a received R-ACK carries a measured latency',
      );

      await ackSub.cancel();
    }, skip: jarAvailable ? null : 'RedPanda JAR not found');
  });
}
