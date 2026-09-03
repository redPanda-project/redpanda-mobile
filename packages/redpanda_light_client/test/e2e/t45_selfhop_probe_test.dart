@Tags(['e2e'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

/// Reproduces the single-node emulator-gate topology at the light-client level:
/// ONE isolated node, Alice + Bob both connected to it, NO other relay
/// candidates. A garlic-only send must therefore self-hop through the connected
/// node, which peels its own layer and deposits into Bob's LOCAL OH. This
/// probes whether the degenerate self-hop path actually delivers against the
/// reference JAR (gate S1 failed with an OhForwarder NOT_FOUND drop).
void main() async {
  final jarAvailable = e2eJarAvailable();

  const port = 50600;
  const address = '127.0.0.1:$port';

  group('E2E T45: single-node self-hop garlic delivery', () {
    late RedPandaNodeLauncher node;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;

    setUp(() async {
      node = RedPandaNodeLauncher(port: port, seeds: const []);
      await node.start();

      Future<Socket> onlyNode(String host, int p) {
        if ('$host:$p' != address) {
          throw const SocketException('test client only dials the node');
        }
        return Socket.connect(host, p);
      }

      final aliceKeys = await KeyPair.generate();
      alice = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(aliceKeys),
        selfKeys: aliceKeys,
        seeds: [address],
        socketFactory: onlyNode,
      );
      final bobKeys = await KeyPair.generate();
      bob = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(bobKeys),
        selfKeys: bobKeys,
        seeds: [address],
        socketFactory: onlyNode,
      );
    });

    tearDown(() async {
      await alice.disconnect();
      await bob.disconnect();
      await Future.delayed(const Duration(seconds: 1));
      await node.stop();
    });

    test(
      'Alice self-hop garlic deposit reaches Bob on the single node',
      () async {
        await alice.connect();
        expect(await waitForEncryption(alice), isTrue);
        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);

        final channel = await Channel.generate('T45 self-hop');
        final bobOH = await bob.registerOutboundHandle(channelId: channel.id);
        expect(bobOH.serverEndpoint, address);
        alice.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          counterpartOhId: bobOH.ohId,
          counterpartOhEndpoint: address,
          isChannelCreator: true,
        );
        bob.addChannelKeys(
          channel.id,
          channel.encryptionKey,
          isChannelCreator: false,
        );

        await Future.delayed(const Duration(seconds: 2));

        const content = 'self-hop hello';
        String? messageId;
        final received = DeliveryCollector(bob);
        addTearDown(received.cancel);

        for (var attempt = 0; attempt < 8; attempt++) {
          messageId = await alice.sendMessage(
            channel.id,
            content,
            messageId: messageId,
          );
          await received.waitUntil(
            (m) => m.any((x) => x.content == content),
            timeout: const Duration(seconds: 8),
          );
          if (received.messages.any((x) => x.content == content)) break;
        }

        expect(
          received.messages.map((m) => m.content),
          contains(content),
          reason: 'the self-hop garlic deposit must reach Bob on the one node',
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
