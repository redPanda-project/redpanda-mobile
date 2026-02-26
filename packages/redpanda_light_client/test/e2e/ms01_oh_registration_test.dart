import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';

void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  group('E2E MS01: OH Registration on Full Node', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient client;
    final int nodePort = 50011;

    setUp(() async {
      launcher = RedPandaNodeLauncher(port: nodePort);
      await launcher.start();

      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: ['127.0.0.1:$nodePort'],
      );
    });

    tearDown(() async {
      await client.disconnect();
      await launcher.stop();
    });

    test(
      'Client connects, registers OH, and fetches messages',
      () async {
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
        expect(oh.ohId.length, 32);
        expect(oh.keypair.publicKeyBytes.length, 65);
        expect(oh.keypair.publicKeyBytes[0], 0x04); // Uncompressed EC point

        // Fetch messages (empty since no backend OH support yet)
        final messages = await client.fetchMessages(oh);
        expect(messages, isEmpty);
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'Client creates v2 channel with OH descriptor after registration',
      () async {
        await client.connect();

        await Future.delayed(const Duration(seconds: 6));

        final oh = await client.registerOutboundHandle();

        // Build OHDescriptor from registration
        final descriptor = OHDescriptor(
          serverEndpoint: '127.0.0.1:$nodePort',
          handleId: oh.ohId,
          authPublicKey: oh.keypair.publicKeyBytes.toList(),
        );

        // Create v2 channel
        final channel = Channel.generate(
          'My Channel',
        ).copyWith(peerOhDescriptor: descriptor);

        // Serialize for QR code
        final qr = channel.toJson();
        expect(qr.contains('"v":2'), isTrue);

        // Deserialize
        final restored = Channel.fromJson(qr);
        expect(restored.peerOhDescriptor, isNotNull);
        expect(restored.peerOhDescriptor!.handleId, equals(oh.ohId));
        expect(
          restored.peerOhDescriptor!.authPublicKey,
          equals(oh.keypair.publicKeyBytes),
        );

        // sendMessage should work without error
        client.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          peerOhId: oh.ohId,
        );
        final msgId = await client.sendMessage(channel.id, 'Test message');
        expect(msgId, isNotEmpty);
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'Client registers OH and keypair can sign and verify',
      () async {
        await client.connect();
        await Future.delayed(const Duration(seconds: 4));

        final oh = await client.registerOutboundHandle();

        // Test signing
        final data = Uint8List.fromList(List.generate(64, (i) => i));
        final sig = oh.keypair.sign(data);
        expect(sig.isNotEmpty, isTrue);
        expect(oh.keypair.verify(data, sig), isTrue);

        // Tamper check
        final tampered = Uint8List.fromList(List.generate(64, (i) => 255 - i));
        expect(oh.keypair.verify(tampered, sig), isFalse);
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
