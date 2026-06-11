@Tags(['e2e'])
@Retry(2)
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
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

      final aliceKeys = KeyPair.generate();
      alice = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(aliceKeys),
        selfKeys: aliceKeys,
        seeds: ['127.0.0.1:$nodePort'],
      );

      final bobKeys = KeyPair.generate();
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
      );
      bob.addChannelKeys(sharedChannel.id, sharedChannel.encryptionKey);
      return bobOH;
    }

    test(
      'fetched messages are acked and deleted on the node; cursor advances',
      () async {
        final sharedChannel = Channel.generate('MS02 AckFetch');
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
      'renewOutboundHandle extends the TTL and emits a mailbox update',
      () async {
        final sharedChannel = Channel.generate('MS02 Renewal');
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
