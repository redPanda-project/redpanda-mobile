@Tags(['e2e'])
@Retry(2)
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'redpanda_node_launcher.dart';
import 'test_helpers.dart';

void main() async {
  final jarAvailable = e2eJarAvailable();

  group('E2E MS02b: deposit responses (want_response) against a real node', () {
    late RedPandaNodeLauncher launcher;
    late RedPandaLightClient alice;
    late RedPandaLightClient bob;
    int nodePort = 50500;

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

    Future<List<int>> setupExchange(Channel sharedChannel) async {
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
      return bobOH.ohId;
    }

    test(
      'a deposit is confirmed with OK before the response timeout',
      () async {
        final sharedChannel = await Channel.generate('MS02b OK');
        await setupExchange(sharedChannel);

        // sendMessage now awaits the FlaschenpostPutResponse (158). A return
        // well below the 10s fallback timeout proves the node answered.
        final stopwatch = Stopwatch()..start();
        final messageId = await alice.sendMessage(sharedChannel.id, 'Hello!');
        stopwatch.stop();

        expect(messageId, hasLength(32));
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason:
              'node must confirm the deposit, not run into the '
              'fire-and-forget fallback',
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'an oversize item (> 64 KiB) is rejected with BAD_REQUEST',
      () async {
        final sharedChannel = await Channel.generate('MS02b Oversize');
        await setupExchange(sharedChannel);

        // 70_000 ASCII chars encrypt to > 64 KiB ciphertext.
        final oversize = 'x' * 70000;

        await expectLater(
          alice.sendMessage(sharedChannel.id, oversize),
          throwsA(
            isA<DepositException>().having(
              (e) => e.isBadRequest,
              'isBadRequest',
              isTrue,
            ),
          ),
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'a deposit to a non-local oh_id is accepted best-effort (OK)',
      () async {
        final sharedChannel = await Channel.generate('MS02b Unknown OH');
        await setupExchange(sharedChannel);

        // Point the channel at an oh_id not registered on this node. Per the
        // MS02b contract, OK means "deposited OR accepted for forwarding
        // toward the OH host node (best-effort)" — the sender must NOT see an
        // error for a recipient whose OH lives elsewhere.
        final bogusChannel = await Channel.generate('MS02b Bogus');
        alice.addChannelKeys(
          bogusChannel.id,
          bogusChannel.encryptionKey,
          peerOhId: List.generate(20, (i) => 255 - i),
          isChannelCreator: true,
        );

        final messageId = await alice.sendMessage(
          bogusChannel.id,
          'Best effort',
        );
        expect(messageId, hasLength(32));
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );

    test(
      'excessive registrations on one connection hit RATE_LIMIT',
      () async {
        await bob.connect();
        expect(await waitForEncryption(bob), isTrue);

        // The node allows 5 RegisterOhRequest per minute per connection.
        Object? rateLimit;
        for (var i = 0; i < 8; i++) {
          try {
            await bob.registerOutboundHandle(channelId: 'spam-$i');
          } on RateLimitException catch (e) {
            rateLimit = e;
            break;
          }
        }

        expect(
          rateLimit,
          isA<RateLimitException>(),
          reason: 'the 6th registration within a minute must be rate-limited',
        );
      },
      skip: jarAvailable ? null : 'RedPanda JAR not found',
    );
  });
}
