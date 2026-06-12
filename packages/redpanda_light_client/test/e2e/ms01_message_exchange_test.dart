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
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

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

        // Alice creates a channel and attaches Bob's OH descriptor
        final channel = await Channel.generate('Alice-Bob Chat');
        final channelWithOH = channel.copyWith(peerOhDescriptor: bobDescriptor);

        // Verify the QR JSON is v3
        final qrJson = channelWithOH.toJson();
        expect(qrJson.contains('"v":3'), isTrue);
        expect(qrJson.contains('"oh"'), isTrue);

        // Reconstruct from QR
        final scannedChannel = Channel.fromJson(qrJson);
        expect(scannedChannel.peerOhDescriptor, isNotNull);
        expect(
          scannedChannel.peerOhDescriptor!.serverEndpoint,
          '127.0.0.1:$nodePort',
        );
        expect(scannedChannel.peerOhDescriptor!.handleId, bobOH.ohId);

        // Alice registers channel keys and sends message
        alice.addChannelKeys(
          channelWithOH.id,
          channelWithOH.encryptionKey,
          peerOhId: bobOH.ohId,
        );

        final messageId = await alice.sendMessage(
          channelWithOH.id,
          'Hello Bob!',
        );
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

        // 2. Bob creates channel + shares via QR (simulated)
        final sharedChannel = await Channel.generate('Shared Channel');
        final bobDescriptor = OHDescriptor(
          serverEndpoint: '127.0.0.1:$nodePort',
          handleId: bobOH.ohId,
          authPublicKey: bobOH.keypair.publicKeyBytes.toList(),
        );
        final channelWithOH = sharedChannel.copyWith(
          peerOhDescriptor: bobDescriptor,
        );
        final qrPayload = channelWithOH.toJson();

        // 3. Alice scans QR
        final aliceChannel = Channel.fromJson(qrPayload);
        expect(aliceChannel.peerOhDescriptor, isNotNull);

        // 4. Alice registers keys
        alice.addChannelKeys(
          aliceChannel.id,
          aliceChannel.encryptionKey,
          peerOhId: aliceChannel.peerOhDescriptor!.handleId,
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
