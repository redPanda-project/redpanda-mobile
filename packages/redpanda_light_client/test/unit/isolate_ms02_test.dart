import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/isolate_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';

void main() {
  group('RedPandaIsolateClient MS02', () {
    test('sendMessage surfaces failures from the isolate', () async {
      // No seeds → no peers and no channel keys: the inner client throws
      // and the error must propagate through the isolate to the caller.
      final client = RedPandaIsolateClient(seeds: const []);

      await expectLater(
        client.sendMessage('unknown-channel', 'hello'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no encryption keys'),
          ),
        ),
      );

      await client.disconnect();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('sendMessage requests resolve independently per requestId', () async {
      final client = RedPandaIsolateClient(seeds: const []);

      final results = await Future.wait([
        client
            .sendMessage('channel-a', 'one')
            .then((_) => 'ok', onError: (Object e) => 'error-a'),
        client
            .sendMessage('channel-b', 'two')
            .then((_) => 'ok', onError: (Object e) => 'error-b'),
      ]);

      expect(results, equals(['error-a', 'error-b']));

      await client.disconnect();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'restoreOutboundHandle is accepted by the isolate without errors',
      () async {
        final client = RedPandaIsolateClient(seeds: const []);

        final registration = OHRegistration(
          ohId: List.generate(20, (i) => i),
          keypair: await OHKeypair.generate(),
          expiresAtMs: DateTime.now()
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          channelId: 'restored-channel',
          serverEndpoint: 'localhost:59558',
          lastCursor: 12,
        );

        await client.restoreOutboundHandle(registration);

        // The restored OH lives inside the isolate; a subsequent send for its
        // channel still fails (no keys/peers) which proves the isolate stayed
        // responsive after processing the restore command.
        await expectLater(
          client.sendMessage('restored-channel', 'ping'),
          throwsA(isA<StateError>()),
        );

        await client.disconnect();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('ohMailboxUpdates stream is exposed', () async {
      final client = RedPandaIsolateClient(seeds: const []);
      expect(client.ohMailboxUpdates, isNotNull);
      await client.disconnect();
    });
  });
}
