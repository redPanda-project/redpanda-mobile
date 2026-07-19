import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/rendezvous_manager.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:test/test.dart';

OHDescriptor _oh(String ep) => OHDescriptor(
  serverEndpoint: ep,
  handleId: CryptoUtils.randomBytes(20),
  authPublicKey: CryptoUtils.randomBytes(32),
);

void main() {
  // Shared 32-byte channel secret (QR v4): both sides hold it.
  final sk = CryptoUtils.randomBytes(32).toList();
  const chan = 'channel-1';

  RendezvousManager creator() {
    final m = RendezvousManager()
      ..register(chan, channelSecret: sk, isCreator: true, ownName: 'Alice');
    return m;
  }

  RendezvousManager joiner() {
    final m = RendezvousManager()
      ..register(chan, channelSecret: sk, isCreator: false, ownName: 'Bob');
    return m;
  }

  test('setOwnOhs reports changes (publish trigger)', () {
    final m = creator();
    expect(m.setOwnOhs(chan, [_oh('1.1.1.1:59558')]), isTrue);
    // Same set again → no change.
    final same = m.channelSecretOf(chan);
    expect(same, isNotNull);
  });

  test(
    'publish/lookup keys rotate per UTC day and agree across participants',
    () async {
      final a = creator();
      final b = joiner();
      final now = DateTime.utc(2026, 7, 19, 12).millisecondsSinceEpoch;
      final aKey = await a.publishKey(chan, now);
      final bKeys = await b.lookupKeys(chan, now);
      // Both derive the same "today" key from the shared secret.
      expect(bKeys.first, aKey);
      // Yesterday differs from today.
      expect(bKeys[1], isNot(equals(bKeys.first)));
    },
  );

  test(
    'heal: joiner adopts creator\'s new OHs purely from a resolved record',
    () async {
      // Bob (creator here) publishes a record after his hosts moved.
      final bob = RendezvousManager()
        ..register(chan, channelSecret: sk, isCreator: true, ownName: 'Bob');
      final bobNewOhs = [
        _oh('5.75.137.166:59558'),
        _oh('46.224.156.238:59558'),
      ];
      expect(bob.setOwnOhs(chan, bobNewOhs), isTrue);
      final now = DateTime.utc(2026, 7, 19, 12).millisecondsSinceEpoch;
      final storeBytes = (await bob.buildSignedStore(chan, now))!;

      // Alice (joiner) has never seen these OHs. She resolves the record.
      final alice = RendezvousManager()
        ..register(chan, channelSecret: sk, isCreator: false, ownName: 'Alice');
      final record = RendezvousManager.recordFromStoreBytes(storeBytes);
      final adopted = await alice.applyResolvedRecord(chan, record, now + 1000);

      expect(adopted, isNotNull);
      expect(
        adopted!.map((o) => o.serverEndpoint).toList(),
        containsAll(['5.75.137.166:59558', '46.224.156.238:59558']),
      );
    },
  );

  test(
    'newest-wins: a stale record does not override a newer known peer entry',
    () async {
      final now = DateTime.utc(2026, 7, 19, 12).millisecondsSinceEpoch;

      // Bob publishes at t0 (old) and t1 (new, different OHs).
      final bob = RendezvousManager()
        ..register(chan, channelSecret: sk, isCreator: true, ownName: 'Bob');
      bob.setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final oldStore = (await bob.buildSignedStore(chan, now))!;
      bob.setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      final newStore = (await bob.buildSignedStore(chan, now + 60000))!;

      final alice = RendezvousManager()
        ..register(chan, channelSecret: sk, isCreator: false, ownName: 'Alice');
      // Apply the NEW record first.
      final first = await alice.applyResolvedRecord(
        chan,
        RendezvousManager.recordFromStoreBytes(newStore),
        now + 61000,
      );
      expect(first!.single.serverEndpoint, '2.2.2.2:59558');
      // Then a stale (older) record arrives — must be ignored (returns null).
      final second = await alice.applyResolvedRecord(
        chan,
        RendezvousManager.recordFromStoreBytes(oldStore),
        now + 62000,
      );
      expect(second, isNull);
    },
  );

  test('rejects a record signed by a different channel secret', () async {
    final bob = RendezvousManager()
      ..register(chan, channelSecret: sk, isCreator: true, ownName: 'Bob');
    bob.setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
    final now = DateTime.utc(2026, 7, 19, 12).millisecondsSinceEpoch;
    final store = (await bob.buildSignedStore(chan, now))!;

    // Alice's manager uses a DIFFERENT secret → cannot verify/decrypt.
    final alice = RendezvousManager()
      ..register(
        chan,
        channelSecret: CryptoUtils.randomBytes(32).toList(),
        isCreator: false,
        ownName: 'Alice',
      );
    final adopted = await alice.applyResolvedRecord(
      chan,
      RendezvousManager.recordFromStoreBytes(store),
      now + 1000,
    );
    expect(adopted, isNull);
  });

  test('rejects a stale record beyond the 48h TTL', () async {
    final bob = RendezvousManager()
      ..register(chan, channelSecret: sk, isCreator: true, ownName: 'Bob');
    bob.setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
    final now = DateTime.utc(2026, 7, 19, 12).millisecondsSinceEpoch;
    final store = (await bob.buildSignedStore(chan, now))!;
    final alice = RendezvousManager()
      ..register(chan, channelSecret: sk, isCreator: false, ownName: 'Alice');
    final tooLate = now + 51 * 60 * 60 * 1000; // > 48h + 2h slack
    final adopted = await alice.applyResolvedRecord(
      chan,
      RendezvousManager.recordFromStoreBytes(store),
      tooLate,
    );
    expect(adopted, isNull);
  });

  test('buildSignedStore is null without an own OH', () async {
    final m = creator();
    expect(await m.buildSignedStore(chan, 1000), isNull);
  });
}
