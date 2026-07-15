import 'dart:io';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

// OH state lives ONLY on the node the handle was registered with. A fetch
// (or ack/renew) sent to any other connected node answers NOT_FOUND — seen
// in the field when the peer map order changed after a reconnect and the
// client silently asked the wrong node forever.
void main() {
  const hostEndpoint = '198.51.100.7:59558';

  late RedPandaLightClient client;
  late InMemoryPeerRepository repo;

  setUp(() async {
    final keys = await KeyPair.generate();
    repo = InMemoryPeerRepository();
    client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: [],
      peerRepository: repo,
      // No real network in this test — every connect attempt fails fast.
      socketFactory: (host, port) async =>
          throw const SocketException('test: no network'),
    );
  });

  tearDown(() async {
    await client.disconnect();
  });

  Future<OHRegistration> registration() async {
    return OHRegistration(
      ohId: List.generate(20, (i) => i),
      keypair: await OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      channelId: 'host-channel',
      serverEndpoint: hostEndpoint,
    );
  }

  test('fetch for a disconnected host requests a reconnect to it', () async {
    await client.fetchMessages(await registration());
    await Future<void>.delayed(Duration.zero);

    expect(
      repo.getBestPeers(100).map((p) => p.address),
      contains(hostEndpoint),
      reason:
          'the host node must be (re)queued for connection, because '
          'no other node can serve this mailbox',
    );
  });

  test(
    'renew for a disconnected host fails instead of asking another node',
    () async {
      final renewed = await client.renewOutboundHandle(await registration());
      expect(renewed, isFalse);
    },
  );

  test('re-registration after NOT_FOUND resets the fetch cursor', () async {
    // A NOT_FOUND fetch means the host recreated (or lost) the mailbox —
    // its sequence ids restart at 1, so the old cursor would silently
    // swallow all new mail. The cursor must be reset AND persisted (via
    // ohMailboxUpdates) even when the re-registration attempt itself
    // cannot reach the host yet.
    final oh = await registration();
    oh.lastCursor = 57;
    final updates = <OhMailboxUpdate>[];
    final sub = client.ohMailboxUpdates.listen(updates.add);

    await client.reregisterLostHandle(oh);
    await Future<void>.delayed(Duration.zero);

    expect(oh.lastCursor, 0);
    expect(updates, hasLength(1));
    expect(updates.single.lastCursor, 0);
    expect(updates.single.ohId, oh.ohId);

    await sub.cancel();
  });
}
