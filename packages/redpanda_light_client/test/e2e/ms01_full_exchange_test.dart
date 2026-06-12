@Tags(['e2e'])
@Retry(2)
library;

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  group('E2E MS01: Full exchange — Alice sends, Bob receives', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;
    int nodePort = 50300;

    setUp(() async {
      nodePort++;
      launcher = RedPandaNodeLauncher(port: nodePort);
      await launcher.start();

      final aliceKeys = await KeyPair.generate();
      alice = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(aliceKeys),
        selfKeys: aliceKeys,
        seeds: ['127.0.0.1:$nodePort'],
        // This test exercises the DIRECT deposit path. Without the pin the
        // client may garlic-route over public peers learned from the node's
        // known-nodes list (MS04) and the message never reaches the local
        // mailbox. The garlic path is covered by ms04_multi_hop_garlic_test.
        hopCandidateFilter: (_) => false,
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

    test(
      'Alice sends encrypted message, Bob fetches and decrypts it',
      () async {
        // 1. Connect both clients
        await alice.connect();
        expect(
          await waitForEncryption(alice),
          isTrue,
          reason: 'Alice should have encryption active',
        );

        await bob.connect();
        expect(
          await waitForEncryption(bob),
          isTrue,
          reason: 'Bob should have encryption active',
        );

        // 2. Create shared channel
        final sharedChannel = await Channel.generate('Alice-Bob E2E');

        // 3. Bob registers OH with channelId
        final bobOH = await bob.registerOutboundHandle(
          channelId: sharedChannel.id,
        );
        expect(bobOH.ohId.length, 20);
        expect(bobOH.channelId, sharedChannel.id);

        // 4. Bob creates OH descriptor to share with Alice
        final bobDescriptor = OHDescriptor(
          serverEndpoint: '127.0.0.1:$nodePort',
          handleId: bobOH.ohId,
          authPublicKey: bobOH.keypair.publicKeyBytes.toList(),
        );

        // 5. Alice imports channel and registers keys with Bob's OH as peer
        final channelWithOH = sharedChannel.copyWith(
          peerOhDescriptor: bobDescriptor,
        );
        alice.addChannelKeys(
          channelWithOH.id,
          channelWithOH.encryptionKey,
          peerOhId: bobOH.ohId,
          isChannelCreator: true,
        );

        // 6. Bob registers channel keys (for decryption)
        bob.addChannelKeys(
          sharedChannel.id,
          sharedChannel.encryptionKey,
          isChannelCreator: false,
        );

        // 7. Alice sends message
        final messageId = await alice.sendMessage(
          channelWithOH.id,
          'Hello Bob!',
        );
        expect(messageId, isNotEmpty);

        // 8. Short delay for backend routing
        await Future.delayed(const Duration(milliseconds: 500));

        // 9. Bob fetches messages
        final messages = await bob.fetchMessages(bobOH);

        // 10. Verify Bob received and decrypted the message
        expect(messages, hasLength(1));
        expect(messages.first.content, equals('Hello Bob!'));
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
