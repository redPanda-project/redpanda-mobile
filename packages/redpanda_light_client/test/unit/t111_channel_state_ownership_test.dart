import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// T111: the worker owns channel state — `addChannelKeys` is a RESTORE, not
/// an assignment. These tests pin the "live state wins" rule in code, which
/// until now existed only as a doc comment while `chat_screen.build`
/// re-registered every channel on every rebuild with a SUBSET of the
/// arguments (the H8 bug class).
void main() {
  late RedPandaLightClient client;

  final channelKey = List<int>.filled(32, 7);
  final channelSecret = List<int>.filled(32, 3);
  List<int> ohId(int b) => List<int>.filled(20, b);

  OHDescriptor descriptor(int b, String endpoint) => OHDescriptor(
    serverEndpoint: endpoint,
    handleId: ohId(b),
    authPublicKey: List<int>.filled(32, b),
  );

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

  test('the first registration adopts the persisted mailbox set', () {
    expect(client.knowsChannel('chan'), isFalse);

    client.addChannelKeys(
      'chan',
      channelKey,
      counterpartOhSet: [
        descriptor(1, 'host-a:59558'),
        descriptor(2, 'host-b:59558'),
      ],
      isChannelCreator: true,
    );

    expect(client.knowsChannel('chan'), isTrue);
    expect(client.counterpartMailboxIds('chan'), equals([ohId(1), ohId(2)]));
    expect(client.counterpartMailboxEndpoint('chan'), equals('host-a:59558'));
  });

  test('a re-register with a stale primary never re-points the live set', () {
    // The live set as the partner announced it in-band (T42 `oh_update`) or as
    // the T44 rendezvous lookup resolved it.
    client.addChannelKeys(
      'chan',
      channelKey,
      counterpartOhSet: [
        descriptor(5, 'live-a:59558'),
        descriptor(6, 'live-b:59558'),
      ],
      isChannelCreator: false,
    );

    // A re-registration from a stale row: the partner has moved on, the row
    // still names the old mailbox. This is what the chat screen did on every
    // rebuild — and it used to redirect every single-target send (garlic, RGB
    // reply, channel-ACK) at the dead mailbox.
    client.addChannelKeys(
      'chan',
      channelKey,
      counterpartOhId: ohId(9),
      counterpartOhEndpoint: 'dead-host:59558',
      isChannelCreator: false,
    );

    expect(client.counterpartMailboxIds('chan'), equals([ohId(5), ohId(6)]));
    expect(client.counterpartMailboxEndpoint('chan'), equals('live-a:59558'));
  });

  test('a re-register still fills a gap: no live mailbox yet', () {
    // A channel joined by QR knows no partner mailbox until the rendezvous
    // lookup answers, so the restore path must still be able to seed one.
    client.addChannelKeys('chan', channelKey, isChannelCreator: false);
    expect(client.counterpartMailboxIds('chan'), isEmpty);

    client.addChannelKeys(
      'chan',
      channelKey,
      counterpartOhId: ohId(4),
      counterpartOhEndpoint: 'host-c:59558',
      isChannelCreator: false,
    );

    expect(client.counterpartMailboxIds('chan'), equals([ohId(4)]));
    expect(client.counterpartMailboxEndpoint('chan'), equals('host-c:59558'));
  });

  test('a re-registration without a display name keeps the published one', () {
    client.addChannelKeys(
      'chan',
      channelKey,
      channelSecret: channelSecret,
      ownDisplayName: 'Alice',
      isChannelCreator: true,
    );
    expect(client.rendezvousOwnNameOf('chan'), equals('Alice'));

    // A partial re-register (the chat screen never passed a display name)
    // must not blank the name that is being published in the DHT record.
    client.addChannelKeys(
      'chan',
      channelKey,
      channelSecret: channelSecret,
      isChannelCreator: true,
    );

    expect(client.rendezvousOwnNameOf('chan'), equals('Alice'));
  });

  test('a re-register with a different encryption key is ignored', () {
    client.addChannelKeys('chan', channelKey, isChannelCreator: true);

    // The channel id is derived from the channel secret, so this can only be
    // a wiring bug — the live key (and with it the live ratchet) wins.
    client.addChannelKeys(
      'chan',
      List<int>.filled(32, 42),
      isChannelCreator: true,
    );

    expect(client.channelEncryptionKeyOf('chan'), equals(channelKey));
  });

  group('the redundancy sweep never creates a channel\'s FIRST mailbox', () {
    test('a channel without an own mailbox is skipped', () async {
      client.addChannelKeys('chan', channelKey, isChannelCreator: true);

      await client.sweepOhRedundancy();

      // Creating the first mailbox stays with the app layer
      // (`ensureOwnDescriptor`) — the sweep only tops UP.
      expect(client.registeredOutboundHandles, isEmpty);
    });

    test('an unknown channel is not swept at all', () async {
      await client.sweepOhRedundancy();
      expect(client.registeredOutboundHandles, isEmpty);
    });

    test('sweeping without a connected peer is a safe no-op', () async {
      client.addChannelKeys('chan', channelKey, isChannelCreator: true);
      await client.restoreOutboundHandle(
        OHRegistration(
          ohId: ohId(3),
          keypair: await OHKeypair.generate(),
          expiresAtMs: DateTime.now()
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          channelId: 'chan',
          serverEndpoint: 'host-a:59558',
        ),
      );

      await client.sweepOhRedundancy();
      // Throttled: a second sweep right away must not run again either.
      await client.sweepOhRedundancy();

      expect(client.registeredOutboundHandles, hasLength(1));
    });
  });

  test('a second restore of the same channel is a no-op', () {
    client.addChannelKeys(
      'chan',
      channelKey,
      channelSecret: channelSecret,
      ownDisplayName: 'Alice',
      counterpartOhSet: [descriptor(1, 'host-a:59558')],
      isChannelCreator: true,
      ratchetState: null,
      sessionTags: const {'aa': 1},
      pendingRgbHex: null,
    );
    final keyBefore = client.channelEncryptionKeyOf('chan');

    // Replaying the very same snapshot — what a duplicate startup restore or
    // a late `registerChannel` does — changes nothing.
    client.addChannelKeys(
      'chan',
      channelKey,
      channelSecret: channelSecret,
      ownDisplayName: 'Alice',
      counterpartOhSet: [descriptor(1, 'host-a:59558')],
      isChannelCreator: true,
      sessionTags: const {'aa': 1},
    );

    expect(client.knowsChannel('chan'), isTrue);
    expect(client.channelEncryptionKeyOf('chan'), equals(keyBefore));
    expect(client.counterpartMailboxIds('chan'), equals([ohId(1)]));
    expect(client.rendezvousOwnNameOf('chan'), equals('Alice'));
  });
}
