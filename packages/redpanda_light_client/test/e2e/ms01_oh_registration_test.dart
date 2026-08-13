@Tags(['e2e'])
@Retry(2)
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

void main() async {
  final jarAvailable = e2eJarAvailable();

  group('E2E MS01: OH Registration on Full Node', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient client;
    int nodePort = 50100;

    setUp(() async {
      nodePort++; // Use unique port per test
      launcher = RedPandaNodeLauncher(port: nodePort);
      await launcher.start();

      final keys = await KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: ['127.0.0.1:$nodePort'],
      );
    });

    tearDown(() async {
      await client.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      await launcher.stop();
    });

    test('Client connects, registers OH, and fetches messages', () async {
      await client.connect();

      // Wait for encryption to be established
      bool encryptionActive = false;
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (client.isEncryptionActive) {
          encryptionActive = true;
          break;
        }
      }
      expect(encryptionActive, isTrue, reason: 'Encryption should be active');

      // Register outbound handle
      final oh = await client.registerOutboundHandle();
      expect(oh.ohId.length, 20);
      expect(oh.keypair.publicKeyBytes.length, 32); // Ed25519 verify key

      // Fetch messages (empty since no backend OH support yet)
      final messages = await client.fetchMessages(oh);
      expect(messages, isEmpty);
    }, skip: jarAvailable ? null : 'RedPanda JAR not found');

    test(
      'Client creates v2 channel with OH descriptor after registration',
      () async {
        await client.connect();

        // Wait until the handshake is done instead of a fixed delay —
        // sendMessage requires a verified peer since MS02.
        expect(await waitForEncryption(client), isTrue);

        final oh = await client.registerOutboundHandle();

        // Build OHDescriptor from registration
        final descriptor = OHDescriptor(
          serverEndpoint: '127.0.0.1:$nodePort',
          handleId: oh.ohId,
          authPublicKey: oh.keypair.publicKeyBytes.toList(),
        );

        // Create channel (QR v4 carries only the channel secret)
        final channel = await Channel.generate('My Channel');

        // Serialize for QR code (v4, no OH embedded)
        final qr = channel.toJson();
        expect(qr.contains('"v":4'), isTrue);
        expect(qr.contains('"oh"'), isFalse);

        // Deserialize (async in v4)
        final restored = await Channel.fromJson(qr);
        expect(restored.id, channel.id);
        expect(restored.peerOhDescriptor, isNull);

        // sendMessage should work without error. Bob's OH is discovered out
        // of band (rendezvous DHT) — here passed directly.
        client.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          channelSecret: channel.channelSecret,
          peerOhId: oh.ohId,
          peerOhEndpoint: descriptor.serverEndpoint,
          isChannelCreator: true,
        );
        final msgId = await client.sendMessage(channel.id, 'Test message');
        expect(msgId, isNotEmpty);
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test('Client registers OH and keypair can sign and verify', () async {
      await client.connect();
      await Future.delayed(const Duration(seconds: 4));

      final oh = await client.registerOutboundHandle();

      // Test signing
      final data = Uint8List.fromList(List.generate(64, (i) => i));
      final sig = await oh.keypair.sign(data);
      expect(sig.length, 64);
      expect(await oh.keypair.verify(data, sig), isTrue);

      // Tamper check
      final tampered = Uint8List.fromList(List.generate(64, (i) => 255 - i));
      expect(await oh.keypair.verify(tampered, sig), isFalse);
    }, skip: jarAvailable ? null : 'RedPanda JAR not found');
  });
}
