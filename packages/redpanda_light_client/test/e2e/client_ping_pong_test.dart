import 'package:test/test.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'redpanda_node_launcher.dart';

void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  group('E2E Real Client PING/PONG', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient client;
    final int nodePort = 50003; // Different port to avoid conflicts

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
      'Client exchanges PING/PONG over encrypted channel',
      () async {
        // Capture stdout to verify PING/PONG logs
        // Note: In a real unit test we might want to mock the logger or expose a stream.
        // For this E2E, we assume if the connection holds and encryption is active, PINGs are flowing.
        // But we can also check if the client stays connected for > 5 seconds, as the server usually pings every few seconds.

        await client.connect();

        // Wait for handshake
        await Future.delayed(const Duration(seconds: 4));
        expect(
          client.isEncryptionActive,
          isTrue,
          reason: "Encryption should be active",
        );

        // Wait for PING/PONG exchange (Server pings shortly after handshake)
        await Future.delayed(const Duration(seconds: 4));

        expect(
          client.isPongSent,
          isTrue,
          reason: "Client should have responded to PING with PONG",
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
