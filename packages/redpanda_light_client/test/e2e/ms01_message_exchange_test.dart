@Tags(['e2e'])
@Retry(2)
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v3.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

void main() async {
  final jarAvailable = e2eJarAvailable();

  group('E2E MS01: Two clients message exchange', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;
    int nodePort = 50200;

    setUp(() async {
      nodePort++; // Use unique port per test
      launcher = RedPandaNodeLauncher(port: nodePort);
      await launcher.start();

      // Create Alice
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

      // Create Bob
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
      'Both clients connect and register outbound handles',
      () async {
        // Connect sequentially to avoid race on single-node
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

        // Register OH for both
        final aliceOH = await alice.registerOutboundHandle();
        final bobOH = await bob.registerOutboundHandle();

        expect(aliceOH.ohId.length, 20);
        expect(bobOH.ohId.length, 20);
        expect(aliceOH.ohId, isNot(equals(bobOH.ohId)));

        // Both should have valid keypairs
        final testData = Uint8List.fromList([1, 2, 3]);
        expect(
          await aliceOH.keypair.verify(
            testData,
            await aliceOH.keypair.sign(testData),
          ),
          isTrue,
        );
        expect(
          await bobOH.keypair.verify(
            testData,
            await bobOH.keypair.sign(testData),
          ),
          isTrue,
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'Alice creates channel v3 with Bobs OH descriptor and sends message',
      () async {
        // Connect sequentially to avoid race on single-node
        await alice.connect();
        expect(await waitForEncryption(alice), isTrue);

        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);

        // Bob registers his OH
        final bobOH = await bob.registerOutboundHandle();

        // Bob creates an OH descriptor to share via QR
        final bobDescriptor = OHDescriptor(
          serverEndpoint: '127.0.0.1:$nodePort',
          handleId: bobOH.ohId,
          authPublicKey: bobOH.keypair.publicKeyBytes.toList(),
        );

        // Alice creates a channel (QR v4 carries only the channel secret).
        final channel = await Channel.generate('Alice-Bob Chat');

        // Verify the QR JSON is v4 and carries no OH.
        final qrJson = channel.toJson();
        expect(qrJson.contains('"v":4'), isTrue);
        expect(qrJson.contains('"oh"'), isFalse);

        // Reconstruct from QR (async in v4); both sides derive the same id.
        final scannedChannel = await Channel.fromJson(qrJson);
        expect(scannedChannel.id, channel.id);
        expect(scannedChannel.peerOhDescriptor, isNull);

        // Alice registers channel keys and sends message. Bob's OH is
        // discovered out of band (rendezvous DHT) — here passed directly.
        alice.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          channelSecret: channel.channelSecret,
          peerOhId: bobOH.ohId,
          peerOhEndpoint: bobDescriptor.serverEndpoint,
          isChannelCreator: true,
        );

        final messageId = await alice.sendMessage(channel.id, 'Hello Bob!');
        expect(messageId, isNotEmpty);
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'Simulated full flow: encrypt, QR exchange, decrypt',
      () async {
        // Connect sequentially to avoid race on single-node
        await alice.connect();
        expect(await waitForEncryption(alice), isTrue);

        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);

        // 1. Bob registers OH
        final bobOH = await bob.registerOutboundHandle();

        // 2. Bob creates channel + shares via QR v4 (secret only)
        final sharedChannel = await Channel.generate('Shared Channel');
        final bobDescriptor = OHDescriptor(
          serverEndpoint: '127.0.0.1:$nodePort',
          handleId: bobOH.ohId,
          authPublicKey: bobOH.keypair.publicKeyBytes.toList(),
        );
        final qrPayload = sharedChannel.toJson();

        // 3. Alice scans QR (async in v4)
        final aliceChannel = await Channel.fromJson(qrPayload);
        expect(aliceChannel.id, sharedChannel.id);

        // 4. Alice registers keys. Bob's OH is discovered out of band
        //    (rendezvous DHT) — here passed directly.
        alice.addChannelKeys(
          aliceChannel.id,
          aliceChannel.encryptionKey,
          channelSecret: aliceChannel.channelSecret,
          peerOhId: bobDescriptor.handleId,
          peerOhEndpoint: bobDescriptor.serverEndpoint,
          isChannelCreator: false,
        );

        // 5. Alice sends encrypted message
        final messageId = await alice.sendMessage(
          aliceChannel.id,
          'Secret message from Alice!',
        );
        expect(messageId, isNotEmpty);

        // 6. Simulate Bob receiving and decrypting via the v3 envelope
        //    (AES-256-GCM, AAD = channel id — both sides derive the same id).
        const plaintext = 'Secret message from Alice!';
        final inner = ChannelMessage(
          messageId: Uint8List.fromList(List<int>.generate(16, (i) => i)),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          content: plaintext,
        );
        final payload = await MessageCryptoV3.encrypt(
          inner,
          aliceChannel.encryptionKey,
          aliceChannel.id,
        );
        final decoded = await MessageCryptoV3.decrypt(
          payload,
          sharedChannel.encryptionKey,
          sharedChannel.id,
        );
        expect(decoded.content, equals(plaintext));
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
