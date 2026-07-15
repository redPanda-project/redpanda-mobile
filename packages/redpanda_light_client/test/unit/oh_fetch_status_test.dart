import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_fetch_status.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

void main() {
  group('ohFetchStatus', () {
    late RedPandaLightClient client;

    setUp(() async {
      final keys = await KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
      );
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('emits a failure outcome for every failed fetch attempt', () async {
      final oh = OHRegistration(
        ohId: List.generate(20, (i) => i),
        keypair: await OHKeypair.generate(),
        expiresAtMs: DateTime.now()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch,
        channelId: 'health-channel',
        serverEndpoint: 'localhost:59558',
        lastCursor: 0,
      );

      final events = <OhFetchStatus>[];
      final sub = client.ohFetchStatus.listen(events.add);

      // No connected peer -> the attempt fails, but unlike ohMailboxUpdates
      // (state changes only) the outcome must still be reported.
      final before = DateTime.now().millisecondsSinceEpoch;
      await client.fetchMessages(oh);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.success, isFalse);
      expect(events.single.detail, 'host node not connected');
      expect(events.single.channelId, 'health-channel');
      expect(events.single.ohId, oh.ohId);
      expect(events.single.atMs, greaterThanOrEqualTo(before));

      await sub.cancel();
    });
  });
}
