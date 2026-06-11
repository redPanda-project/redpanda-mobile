import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

OHRegistration _registration({
  List<int>? ohId,
  int? expiresAtMs,
  int lastCursor = 0,
}) {
  return OHRegistration(
    ohId: ohId ?? List.generate(20, (i) => i),
    keypair: OHKeypair.generate(),
    expiresAtMs:
        expiresAtMs ??
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
    channelId: 'test-channel',
    serverEndpoint: 'localhost:59558',
    lastCursor: lastCursor,
  );
}

void main() {
  group('MS02: restoreOutboundHandle', () {
    late RedPandaLightClient client;

    setUp(() {
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
      );
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('adds the persisted registration for polling', () async {
      final oh = _registration(lastCursor: 99);
      await client.restoreOutboundHandle(oh);

      expect(client.registeredOutboundHandles, hasLength(1));
      expect(client.registeredOutboundHandles.single.lastCursor, equals(99));
    });

    test('ignores a duplicate restore of the same OH id', () async {
      final ohId = List.generate(20, (i) => 7);
      await client.restoreOutboundHandle(_registration(ohId: ohId));
      await client.restoreOutboundHandle(_registration(ohId: ohId));

      expect(client.registeredOutboundHandles, hasLength(1));
    });

    test('keeps distinct OH ids separate', () async {
      await client.restoreOutboundHandle(
        _registration(ohId: List.generate(20, (i) => 1)),
      );
      await client.restoreOutboundHandle(
        _registration(ohId: List.generate(20, (i) => 2)),
      );

      expect(client.registeredOutboundHandles, hasLength(2));
    });
  });

  group('MS02: ackFetch / renewal without a connected peer', () {
    late RedPandaLightClient client;

    setUp(() {
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
      );
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('ackFetch returns false when no peer is connected', () async {
      final result = await client.ackFetch(_registration(), 5);
      expect(result, isFalse);
    });

    test(
      'renewOutboundHandle returns false when no peer is connected',
      () async {
        final oh = _registration();
        final before = oh.expiresAtMs;

        final result = await client.renewOutboundHandle(oh);

        expect(result, isFalse);
        expect(oh.expiresAtMs, equals(before));
      },
    );

    test(
      'checkAndRenewExpiringHandles tolerates failures and keeps expiry',
      () async {
        // Expires within the renewal threshold (1 day) → renewal attempted.
        final expiring = _registration(
          expiresAtMs: DateTime.now()
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        );
        await client.restoreOutboundHandle(expiring);

        await client.checkAndRenewExpiringHandles();

        // No peer → renewal failed silently; will be retried next cycle.
        expect(
          client.registeredOutboundHandles.single.expiresAtMs,
          equals(expiring.expiresAtMs),
        );
      },
    );
  });

  group('MS02: renewal threshold configuration', () {
    test('renews within one day, checks every five minutes', () {
      expect(RedPandaLightClient.renewalThreshold, const Duration(days: 1));
      expect(
        RedPandaLightClient.renewalCheckInterval,
        const Duration(minutes: 5),
      );
    });
  });
}
