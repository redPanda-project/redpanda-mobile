import 'package:test/test.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'redpanda_node_launcher.dart';

void main() async {
  final jarAvailable = await RedPandaNodeLauncher.isJarAvailable();

  group('E2E Real Client', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient client;
    final int nodePort = 50002;

    setUp(() async {
      // 1. Start a real node
      launcher = RedPandaNodeLauncher(port: nodePort);
      await launcher.start();

      // 2. Init client
      final keys = await KeyPair.generate();
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
      'Client connects to local node and transitions to connected state',
      () async {
        // The first event is the state at subscribe time, and we subscribe
        // before connect() — so `disconnected` is correct and is now actually
        // delivered. It used to be swallowed: the old `yield _currentStatus`
        // generator did not run its body until the first pull, by which time
        // connect() had already moved the status on (T81).
        final statusExpectation = expectLater(
          client.connectionStatus,
          emitsInOrder([
            ConnectionStatus.disconnected,
            ConnectionStatus.connecting,
            ConnectionStatus.connected,
          ]),
        );

        await client.connect();

        // Wait for status to be connected
        await statusExpectation;

        // Poll for encryption to become active (up to 10 seconds)
        bool encryptionActive = false;
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (client.isEncryptionActive) {
            encryptionActive = true;
            break;
          }
        }

        expect(
          encryptionActive,
          isTrue,
          reason: "Encryption should be active after handshake",
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
