import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/isolate_client.dart';

void main() {
  group('RedPandaIsolateClient OH registration', () {
    test(
      'registerOutboundHandle round-trips an OHRegistration from the isolate',
      () async {
        // No seeds: the isolate client builds the registration locally and
        // sends it back without needing a network connection.
        final client = RedPandaIsolateClient(seeds: const []);

        final registration = await client.registerOutboundHandle(
          channelId: 'test-channel',
        );

        expect(registration.ohId, hasLength(20));
        expect(registration.keypair.publicKeyBytes, hasLength(32));
        expect(registration.keypair.privateKeyBytes, hasLength(32));
        expect(registration.channelId, 'test-channel');
        expect(
          registration.expiresAtMs,
          greaterThan(DateTime.now().millisecondsSinceEpoch),
        );

        await client.disconnect();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'concurrent registrations resolve independently',
      () async {
        final client = RedPandaIsolateClient(seeds: const []);

        final results = await Future.wait([
          client.registerOutboundHandle(channelId: 'channel-a'),
          client.registerOutboundHandle(channelId: 'channel-b'),
        ]);

        expect(results[0].channelId, 'channel-a');
        expect(results[1].channelId, 'channel-b');
        expect(results[0].ohId, isNot(equals(results[1].ohId)));

        await client.disconnect();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
