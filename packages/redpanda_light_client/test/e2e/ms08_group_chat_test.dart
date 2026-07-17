@Tags(['e2e'])
@Retry(2)
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:io';

import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// MS08 acceptance, end to end against the reference JAR:
///
/// A three-member group (Alice = admin, Bob, Carol), each member with an own
/// group OH on the entry node. Alice installs epoch 1 via sealed rotations
/// (envelope v6 over 3-hop garlic), Bob fans a group message out to both
/// other mailboxes (envelope v5, R-ACK per recipient), everyone reads it,
/// Channel-ACKs flow back as v5 broadcasts. Then Alice removes Carol
/// (epoch 2): Bob keeps reading, Carol's client buffers the unknown epoch
/// and never surfaces the message (Decisions 3/10/12).
///
/// The group join handshake over 1:1 channels (Decision 8) is app-layer
/// logic and covered by the app unit tests — this suite wires the members
/// directly at the LC API, which is exactly what the handshake produces.
///
/// Same topology as the MS04–MS06 E2E: entry node on 59558 (the JAR's
/// built-in local seed) + three local relays; the shared entry port is why
/// all garlic suites take the topology lock.
void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  const entryPort = 59558;
  const relayPorts = [50584, 50585, 50586];
  const entryAddress = '127.0.0.1:$entryPort';
  final relayAddresses = relayPorts.map((p) => '127.0.0.1:$p').toSet();

  group('E2E MS08: group chat across 4 real nodes', () {
    final launchers = <RedPandaNodeLauncher>[];
    final clients = <RedPandaLightClient>[];
    ServerSocket? topologyLock;

    setUp(() async {
      topologyLock = await acquireTopologyLock();
      for (final port in [entryPort, ...relayPorts]) {
        final launcher = RedPandaNodeLauncher(port: port);
        launchers.add(launcher);
        await launcher.start();
      }
    });

    tearDown(() async {
      for (final client in clients) {
        await client.disconnect();
      }
      clients.clear();
      await Future.delayed(const Duration(seconds: 1));
      for (final launcher in launchers) {
        await launcher.stop();
      }
      launchers.clear();
      await topologyLock?.close();
      topologyLock = null;
    });

    Future<RedPandaLightClient> newClient() async {
      Future<Socket> entryOnly(String host, int port) {
        if ('$host:$port' != entryAddress) {
          throw const SocketException('test client only dials the entry node');
        }
        return Socket.connect(host, port);
      }

      final keys = await KeyPair.generate();
      final client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [entryAddress],
        socketFactory: entryOnly,
        hopCandidateFilter: (peer) => relayAddresses.contains(peer.address),
      );
      clients.add(client);
      return client;
    }

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

    test(
      'rotation, fan-out, per-member ACKs and member removal',
      () async {
        final alice = await newClient();
        final bob = await newClient();
        final carol = await newClient();

        for (final (client, who) in [
          (alice, 'Alice'),
          (bob, 'Bob'),
          (carol, 'Carol'),
        ]) {
          await client.connect();
          expect(await waitForEncryption(client), isTrue, reason: who);
        }

        final groupId = HEX.encode(CryptoUtils.randomBytes(32));

        // Member identities — in production generated during the 1:1 join
        // handshake (Decision 8); here wired directly at the LC API.
        final identities = <String, Ed25519KeyPairBytes>{};
        final x25519s = <String, X25519KeyPairBytes>{};
        final memberIds = <String, String>{};
        for (final who in ['Alice', 'Bob', 'Carol']) {
          final sign = await CryptoUtils.generateSigningKeypair();
          identities[who] = sign;
          x25519s[who] = await CryptoUtils.generateEncryptionKeypair();
          memberIds[who] = HEX.encode(sign.publicKey);
        }

        // One group OH per member (Decision 7), all on the entry node.
        final ohs = {
          'Alice': await alice.registerOutboundHandle(channelId: groupId),
          'Bob': await bob.registerOutboundHandle(channelId: groupId),
          'Carol': await carol.registerOutboundHandle(channelId: groupId),
        };

        GroupMemberInfo member(String who, int role) => GroupMemberInfo(
          memberIdHex: memberIds[who]!,
          displayName: who,
          ohId: ohs[who]!.ohId,
          ohEndpoint: entryAddress,
          x25519PubHex: HEX.encode(x25519s[who]!.publicKey),
          role: role,
        );

        final fullRoster = [
          member('Alice', GroupMemberInfo.roleAdmin),
          member('Bob', GroupMemberInfo.roleMember),
          member('Carol', GroupMemberInfo.roleMember),
        ];

        void register(
          RedPandaLightClient client,
          String who, {
          required bool isAdmin,
        }) {
          client.registerGroup(
            GroupRegistration(
              groupId: groupId,
              label: 'MS08 Runde',
              isAdmin: isAdmin,
              myMemberIdHex: memberIds[who]!,
              mySignSeed: identities[who]!.privateSeed,
              myX25519Priv: x25519s[who]!.privateKey,
              keyEpoch: 0,
              members: fullRoster,
            ),
          );
        }

        register(alice, 'Alice', isAdmin: true);
        register(bob, 'Bob', isAdmin: false);
        register(carol, 'Carol', isAdmin: false);

        for (final (client, who) in [
          (alice, 'Alice'),
          (bob, 'Bob'),
          (carol, 'Carol'),
        ]) {
          await waitForRelayCandidates(client, who);
        }
        await Future.delayed(const Duration(seconds: 5));

        // Track epoch installs via the group state stream.
        final epochs = <String, int>{'Bob': 0, 'Carol': 0};
        final stateSubs = [
          bob.groupStateUpdates.listen((u) => epochs['Bob'] = u.keyEpoch),
          carol.groupStateUpdates.listen((u) => epochs['Carol'] = u.keyEpoch),
        ];

        // ── Step 1: Alice installs epoch 1 — sealed rotations via garlic. ──
        await alice.rotateGroupKey(groupId, members: fullRoster);

        // Each client's poll loop (Connection-Notify auto-fetch, T38) fetches
        // its group OH and installs epochs from the sealed rotation boxes; the
        // groupStateUpdates stream reports the installed epoch. No explicit
        // fetchMessages() is needed.
        Future<void> waitForEpoch(
          RedPandaLightClient client,
          String who,
          int epoch,
        ) async {
          for (var i = 0; i < 30 && epochs[who]! < epoch; i++) {
            if (epochs[who]! >= epoch) break;
            // A box lost in the garlic network stays pending until its R-ACK
            // arrives; re-send it like the app's periodic retry does (Alice's
            // poll consumes the confirmations).
            if (i > 0 && i % 3 == 0) {
              try {
                await alice.retryPendingRotations(groupId);
              } on GroupSendException catch (_) {
                // Still undeliverable — keep polling.
              }
            }
            await Future.delayed(const Duration(seconds: 2));
          }
          expect(
            epochs[who],
            greaterThanOrEqualTo(epoch),
            reason: '$who must install epoch $epoch from the sealed rotation',
          );
        }

        await waitForEpoch(bob, 'Bob', 1);
        await waitForEpoch(carol, 'Carol', 1);

        // ── Step 2: Bob fans out a group message; both others read it. ─────
        final bobAcks = <RoutingAckUpdate>[];
        final bobChannelAcks = <ChannelAckUpdate>[];
        final ackSub = bob.routingAckUpdates.listen(bobAcks.add);
        final channelAckSub = bob.channelAckUpdates.listen(bobChannelAcks.add);

        bool hasContent(List<DecryptedMessage> m, String c) =>
            m.any((x) => x.content == c);

        // Deliveries are observed on the production path (each client's poll
        // loop decrypts group items and publishes them on incomingMessages).
        // Collectors start before Bob fans the message out.
        const hello = 'Hallo Runde — von Bob!';
        String? helloId;
        final aliceInbox = DeliveryCollector(alice);
        final carolInbox = DeliveryCollector(carol);
        addTearDown(aliceInbox.cancel);
        addTearDown(carolInbox.cancel);

        for (
          var attempt = 0;
          attempt < 6 &&
              !(hasContent(aliceInbox.messages, hello) &&
                  hasContent(carolInbox.messages, hello));
          attempt++
        ) {
          try {
            helloId = await bob.sendGroupMessage(
              groupId,
              hello,
              messageId: helloId,
            );
          } on GroupSendException catch (e) {
            // Partial fan-out: keep the id and retry (dedup at receivers).
            helloId = e.messageIdHex ?? helloId;
          }
          await Future.wait([
            aliceInbox.waitUntil(
              (m) => hasContent(m, hello),
              timeout: const Duration(seconds: 12),
            ),
            carolInbox.waitUntil(
              (m) => hasContent(m, hello),
              timeout: const Duration(seconds: 12),
            ),
          ]);
        }

        expect(aliceInbox.messages.map((m) => m.content), contains(hello));
        expect(carolInbox.messages.map((m) => m.content), contains(hello));
        // Sender authenticity: both receivers attribute the message to Bob.
        expect(
          aliceInbox.messages.map((m) => m.senderMemberIdHex),
          contains(memberIds['Bob']),
        );
        expect(
          carolInbox.messages.map((m) => m.senderMemberIdHex),
          contains(memberIds['Bob']),
        );

        // ── Step 3: Bob's per-member feedback arrives in his mailbox; his
        // poll fetches and correlates the R-ACKs and Channel-ACKs. ─────────
        final ackDeadline = DateTime.now().add(const Duration(seconds: 40));
        while ((bobAcks.where((a) => !a.timedOut).isEmpty ||
                bobChannelAcks.isEmpty) &&
            DateTime.now().isBefore(ackDeadline)) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        final storedAcks = bobAcks.where(
          (a) =>
              !a.timedOut &&
              a.messageIdHex == helloId &&
              a.status == RoutingAck.statusStored,
        );
        expect(
          storedAcks,
          isNotEmpty,
          reason: 'Bob must receive at least one per-member R-ACK',
        );
        expect(
          storedAcks.map((a) => a.memberIdHex).whereType<String>(),
          isNotEmpty,
          reason: 'group R-ACKs carry the targeted member id',
        );
        expect(
          bobChannelAcks.where(
            (a) => a.messageIdHex == helloId && a.memberIdHex != null,
          ),
          isNotEmpty,
          reason: 'receivers auto-send v5 Channel-ACKs with their member id',
        );

        // ── Step 4: Alice removes Carol (epoch 2); Carol reads nothing new. ─
        final remaining = [
          member('Alice', GroupMemberInfo.roleAdmin),
          member('Bob', GroupMemberInfo.roleMember),
        ];
        await alice.rotateGroupKey(groupId, members: remaining);
        await waitForEpoch(bob, 'Bob', 2);

        const secret = 'Nur noch für Bob.';
        String? secretId;
        final bobInbox = DeliveryCollector(bob);
        addTearDown(bobInbox.cancel);
        for (
          var attempt = 0;
          attempt < 6 && !hasContent(bobInbox.messages, secret);
          attempt++
        ) {
          try {
            secretId = await alice.sendGroupMessage(
              groupId,
              secret,
              messageId: secretId,
            );
          } on GroupSendException catch (e) {
            secretId = e.messageIdHex ?? secretId;
          }
          await bobInbox.waitUntil(
            (m) => hasContent(m, secret),
            timeout: const Duration(seconds: 12),
          );
        }
        expect(bobInbox.messages.map((m) => m.content), contains(secret));

        // Carol was removed and still holds only epoch 1 — the secret is never
        // deposited to her and anything she polls stays undecryptable, so her
        // continuously-listening collector must never surface it.
        await Future.delayed(const Duration(seconds: 3));
        expect(
          carolInbox.messages.map((m) => m.content),
          isNot(contains(secret)),
        );
        expect(epochs['Carol'], 1);

        await ackSub.cancel();
        await channelAckSub.cancel();
        for (final sub in stateSubs) {
          await sub.cancel();
        }
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
