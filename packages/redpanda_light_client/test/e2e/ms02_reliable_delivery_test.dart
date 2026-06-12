@Tags(['e2e'])
@Retry(2)
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  group('E2E MS02: AckFetch, cursor and renewal against a real node', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;
    int nodePort = 50400;

    setUp(() async {
      nodePort++;
      launcher = RedPandaNodeLauncher(port: nodePort);
      await launcher.start();

      final aliceKeys = await KeyPair.generate();
      alice = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(aliceKeys),
        selfKeys: aliceKeys,
        seeds: ['127.0.0.1:$nodePort'],
      );

      final bobKeys = await KeyPair.generate();
      bob = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(bobKeys),
        selfKeys: bobKeys,
        seeds: ['127.0.0.1:$nodePort'],
      );
    });

    tearDown(() async {
      await alice.disconnect();
      await bob.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      await launcher.stop();
    });

    Future<OHRegistration> setupExchange(Channel sharedChannel) async {
      await alice.connect();
      expect(await waitForEncryption(alice), isTrue);
      await bob.connect();
      expect(await waitForEncryption(bob), isTrue);

      final bobOH = await bob.registerOutboundHandle(
        channelId: sharedChannel.id,
      );
      alice.addChannelKeys(
        sharedChannel.id,
        sharedChannel.encryptionKey,
        peerOhId: bobOH.ohId,
        isChannelCreator: true,
      );
      bob.addChannelKeys(
        sharedChannel.id,
        sharedChannel.encryptionKey,
        isChannelCreator: false,
      );
      return bobOH;
    }

    test(
      'fetched messages are acked and deleted on the node; cursor advances',
      () async {
        final sharedChannel = await Channel.generate('MS02 AckFetch');
        final bobOH = await setupExchange(sharedChannel);

        final updates = <OhMailboxUpdate>[];
        final sub = bob.ohMailboxUpdates.listen(updates.add);

        await alice.sendMessage(sharedChannel.id, 'Reliable hello!');
        await Future.delayed(const Duration(milliseconds: 500));

        // First fetch: message delivered, AckFetch sent automatically.
        final messages = await bob.fetchMessages(bobOH);
        expect(messages, hasLength(1));
        expect(messages.first.content, equals('Reliable hello!'));
        expect(messages.first.channelId, equals(sharedChannel.id));
        expect(bobOH.lastCursor, greaterThan(0));

        // The mailbox update for persistence was emitted.
        await Future.delayed(const Duration(milliseconds: 100));
        expect(updates, isNotEmpty);
        expect(updates.last.lastCursor, equals(bobOH.lastCursor));
        expect(updates.last.channelId, equals(sharedChannel.id));
        expect(updates.last.mailboxOverflow, isFalse);

        // Second fetch from cursor 0: the acked item must be gone server-side.
        final freshHandle = OHRegistration(
          ohId: bobOH.ohId,
          keypair: bobOH.keypair,
          expiresAtMs: bobOH.expiresAtMs,
          channelId: bobOH.channelId,
          serverEndpoint: bobOH.serverEndpoint,
        );
        final afterAck = await bob.fetchMessages(freshHandle);
        expect(
          afterAck,
          isEmpty,
          reason: 'acked messages must be deleted from the mailbox',
        );

        await sub.cancel();
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'Bob receives BOTH of two messages Alice sends (C1 contract)',
      () async {
        final sharedChannel = await Channel.generate('MS03 Two Messages');
        final bobOH = await setupExchange(sharedChannel);

        // Alice sends two distinct messages. Each gets its own stable inner
        // ChannelMessage.message_id; the reference node does NOT set
        // MailItem.message_id, so dedup must rely on the decrypted id.
        final id1 = await alice.sendMessage(sharedChannel.id, 'First message');
        final id2 = await alice.sendMessage(sharedChannel.id, 'Second message');
        expect(id1, isNot(equals(id2)));
        await Future.delayed(const Duration(milliseconds: 800));

        // Collect across fetches: the node may return them in one or more
        // batches. Fetch a couple of times to drain the mailbox.
        final received = <DecryptedMessage>[];
        for (var i = 0; i < 3 && received.length < 2; i++) {
          received.addAll(await bob.fetchMessages(bobOH));
          if (received.length < 2) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }

        final contents = received.map((m) => m.content).toSet();
        expect(
          contents,
          containsAll(['First message', 'Second message']),
          reason: 'both messages must survive dedup (regression for C1)',
        );

        // The decrypted ids match what Alice reported and are distinct.
        final ids = received.map((m) => m.id).toSet();
        expect(ids, containsAll({id1, id2}));
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'a re-sent message (same id) is deduplicated to one delivery',
      () async {
        final sharedChannel = await Channel.generate('MS03 Resend Dedup');
        final bobOH = await setupExchange(sharedChannel);

        // Simulate a retry: send the SAME logical message id twice with fresh
        // IVs (the network layer re-encrypts each attempt).
        final id = await alice.sendMessage(sharedChannel.id, 'Only once');
        await alice.sendMessage(sharedChannel.id, 'Only once', messageId: id);
        await Future.delayed(const Duration(milliseconds: 800));

        final received = <DecryptedMessage>[];
        for (var i = 0; i < 3; i++) {
          received.addAll(await bob.fetchMessages(bobOH));
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Both copies may arrive on the wire (the node does not dedup), but
        // they carry the SAME decrypted id, so the app layer collapses them.
        final distinctIds = received.map((m) => m.id).toSet();
        expect(distinctIds, contains(id));
        expect(
          distinctIds.length,
          equals(1),
          reason: 'both deliveries share one sender message id',
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'renewOutboundHandle extends the TTL and emits a mailbox update',
      () async {
        final sharedChannel = await Channel.generate('MS02 Renewal');
        final bobOH = await setupExchange(sharedChannel);

        final updateFuture = bob.ohMailboxUpdates.first;

        final renewed = await bob.renewOutboundHandle(bobOH);
        expect(renewed, isTrue);
        expect(
          bobOH.expiresAtMs,
          greaterThan(DateTime.now().millisecondsSinceEpoch),
        );

        final update = await updateFuture.timeout(const Duration(seconds: 5));
        expect(update.ohId, equals(bobOH.ohId));
        expect(update.expiresAtMs, equals(bobOH.expiresAtMs));

        // The renewed handle must still accept deposits and fetches.
        await alice.sendMessage(sharedChannel.id, 'After renewal');
        await Future.delayed(const Duration(milliseconds: 500));
        final messages = await bob.fetchMessages(bobOH);
        expect(messages, hasLength(1));
        expect(messages.first.content, equals('After renewal'));
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
