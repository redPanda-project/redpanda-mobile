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
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// MS05 acceptance, end to end against the reference JAR:
///
/// Alice attaches a Reverse Garlic Block to her message (return hops +
/// session tag + her OH id) and routes it to Bob's OH over 3 garlic hops.
/// Bob — who never learns Alice's OH endpoint or network location and has
/// **no counterpart OH id registered** — replies over the hops Alice chose, with a
/// CMD_DELIVER_TAGGED innermost layer. The relays peel it with unmodified
/// MS04 logic; the final hop deposits payload + session tag into Alice's OH
/// mailbox. Alice fetches the reply and correlates it via the tag
/// (single-use). Bob's reply carried his own fresh RGB, so Alice's next
/// message travels the reverse path toward Bob's mailbox in turn — the full
/// two-way conversation of the acceptance criteria.
///
/// Topology as in the MS04 E2E (T30): suite-private ports — an isolated
/// entry node + three relays explicitly seeded with the entry address. No
/// shared ports between suites, hence no topology lock.
void main() async {
  final jarAvailable = e2eJarAvailable();

  const entryPort = 50580;
  const relayPorts = [50581, 50582, 50583];
  const entryAddress = '127.0.0.1:$entryPort';
  final relayAddresses = relayPorts.map((p) => '127.0.0.1:$p').toSet();

  group('E2E MS05: reverse garlic reply across 4 real nodes', () {
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

      Future<Socket> entryOnly(String host, int port) {
        if ('$host:$port' != entryAddress) {
          throw const SocketException('test client only dials the entry node');
        }
        return Socket.connect(host, port);
      }

      // Both clients pin the three local relays as hop candidates so the
      // forward path, Alice's RGB and Bob's counter-RGB never route over
      // discovered public-internet nodes.
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
    });

    /// Polls until [client] knows all three relays incl. their X25519 keys.
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

    test('Alice sends with RGB, Bob replies via the reverse path, Alice '
        'correlates by session tag and answers over Bob\'s RGB', () async {
      await alice.connect();
      expect(await waitForEncryption(alice), isTrue);
      await bob.connect();
      expect(await waitForEncryption(bob), isTrue);

      final channel = await Channel.generate('MS05 Reverse Garlic');
      final bobOH = await bob.registerOutboundHandle(channelId: channel.id);
      // Alice registers her own OH too: her poll delivers the tagged reply and
      // her sends attach a Reverse Garlic Block pointing at this mailbox.
      await alice.registerOutboundHandle(channelId: channel.id);

      alice.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        counterpartOhId: bobOH.ohId,
        counterpartOhEndpoint: entryAddress,
        isChannelCreator: true,
      );
      // Bob gets NO counterpart OH id: his only way back to Alice is the RGB.
      bob.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: false,
      );

      // Discover the relay candidates for both clients in parallel — the
      // peer lists come from the same entry node, and keeping this phase
      // short matters for the per-attempt time budget.
      await Future.wait([
        waitForRelayCandidates(alice, 'Alice'),
        waitForRelayCandidates(bob, 'Bob'),
      ]);
      // Give the OH announces and the relay interconnections a moment.
      await Future.delayed(const Duration(seconds: 5));

      // Delivery is observed on the production path: both clients' poll loops
      // (Connection-Notify auto-fetch, T38) fetch, decrypt and — crucially for
      // this test — store any received Reverse Garlic Block, so no explicit
      // fetchMessages() is needed to drive the RGB exchange. Collectors are
      // started before any send (broadcast streams do not replay).
      final bobInbox = DeliveryCollector(bob);
      final aliceInbox = DeliveryCollector(alice);
      addTearDown(bobInbox.cancel);
      addTearDown(aliceInbox.cancel);

      bool hasContent(List<DecryptedMessage> m, String c) =>
          m.any((x) => x.content == c);

      // ── Step 1: Alice → Bob over the forward garlic path, with RGB. ──
      // Garlic delivery is fire-and-forget (no R-ACK before MS06): re-send
      // the SAME logical message id until Bob's poll sees it; every attempt
      // picks fresh hops and carries a fresh RGB.
      const hello = 'Hello Bob — reply through my hops!';
      String? helloId;

      for (var attempt = 0; attempt < 8; attempt++) {
        helloId = await alice.sendMessage(
          channel.id,
          hello,
          messageId: helloId,
        );
        expect(alice.lastSendHopCount, 3);
        expect(
          alice.lastSendViaRgb,
          isFalse,
          reason: 'the first message has no reply path to use yet',
        );
        await bobInbox.waitUntil(
          (m) => hasContent(m, hello),
          timeout: const Duration(seconds: 14),
        );
        if (hasContent(bobInbox.messages, hello)) break;
      }

      final helloMsgs = bobInbox.messages
          .where((m) => m.content == hello)
          .toList();
      expect(helloMsgs, isNotEmpty);
      expect(
        helloMsgs.first.viaSessionTag,
        isFalse,
        reason: 'the forward direction is untagged',
      );

      // ── Step 2: Bob → Alice via the RGB (reverse path). ──────────────
      // Bob holds Alice's freshest RGB (stored by his poll while delivering
      // hello). The RGB is single-use, so each retry first REPLENISHES it
      // (Alice re-sends hello, Bob's poll re-fetches) before Bob replies
      // again — otherwise the consumed RGB would force the reply onto a path
      // Bob (no counterpart OH id) cannot take. We require the reply to travel the
      // RGB at least once and to reach Alice.
      const reply = 'Hi Alice — routed over your return hops!';
      String? replyId;
      var repliedViaRgb = false;

      for (var attempt = 0; attempt < 8; attempt++) {
        if (attempt > 0) {
          // Refresh Bob's single-use RGB: Alice re-sends hello (same id — the
          // app layer would deduplicate; the point is Bob's poll re-fetches
          // and refreshes the pending RGB).
          final before = bobInbox.messages.length;
          await alice.sendMessage(channel.id, hello, messageId: helloId);
          await bobInbox.waitUntil(
            (m) => m.length > before,
            timeout: const Duration(seconds: 14),
          );
        }

        replyId = await bob.sendMessage(channel.id, reply, messageId: replyId);
        if (bob.lastSendViaRgb) {
          expect(
            bob.lastSendHopCount,
            3,
            reason: 'the RGB reply must traverse the 3 hops Alice chose',
          );
          repliedViaRgb = true;
        }

        await aliceInbox.waitUntil(
          (m) => hasContent(m, reply),
          timeout: const Duration(seconds: 14),
        );
        if (hasContent(aliceInbox.messages, reply)) break;
      }

      expect(
        repliedViaRgb,
        isTrue,
        reason:
            'Bob (no counterpart OH id) must reply via the RGB at least once',
      );
      expect(aliceInbox.messages.map((m) => m.content), contains(reply));
      final tagged = aliceInbox.messages.firstWhere((m) => m.content == reply);
      expect(
        tagged.viaSessionTag,
        isTrue,
        reason: 'the reply must be correlated through its session tag',
      );
      expect(tagged.channelId, channel.id);
      expect(tagged.id, replyId);

      // ── Step 3: Alice → Bob over Bob's counter-RGB. ───────────────────
      // Bob's reply carried his own fresh RGB (stored by Alice's poll while
      // delivering it), so Alice's next message takes the reverse path into
      // Bob's mailbox (two-way conversation).
      const followUp = 'Got it — answering over YOUR return hops!';
      String? followUpId;

      followUpId = await alice.sendMessage(
        channel.id,
        followUp,
        messageId: followUpId,
      );
      expect(
        alice.lastSendViaRgb,
        isTrue,
        reason: 'Alice must use the RGB from Bob\'s reply',
      );

      for (var attempt = 0; attempt < 6; attempt++) {
        await bobInbox.waitUntil(
          (m) => hasContent(m, followUp),
          timeout: const Duration(seconds: 12),
        );
        if (hasContent(bobInbox.messages, followUp)) break;
        // The single-use RGB is consumed; retries fall back to the forward
        // garlic path (OQ 3) with the same logical id.
        await alice.sendMessage(channel.id, followUp, messageId: followUpId);
      }

      expect(bobInbox.messages.map((m) => m.content), contains(followUp));
    }, skip: jarAvailable ? null : 'RedPanda JAR not found');
  });
}
