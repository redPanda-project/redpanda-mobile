import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
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
    final oh = _oh('1.1.1.1:59558');
    expect(m.setOwnOhs(chan, [oh]), isTrue);
    // The identical set again is not a change (no spurious republish).
    expect(m.setOwnOhs(chan, [oh]), isFalse);
    // A different set is a change again.
    expect(m.setOwnOhs(chan, [oh, _oh('2.2.2.2:59558')]), isTrue);
    // Unknown channel never reports a change.
    expect(m.setOwnOhs('other', [oh]), isFalse);
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

  test('pins the record key: rejects a foreign-signed but decryptable record '
      '(T47c)', () async {
    // Adversarial node answers the lookup with a record whose content was
    // encrypted with OUR k_enc (decryptable!) but signed by a DIFFERENT
    // record keypair. Signature verification against the embedded key
    // succeeds — only the pin against the derived record pubkey catches it.
    final now = DateTime.utc(2026, 7, 19, 12).millisecondsSinceEpoch;
    final entries = [
      RendezvousEntry(
        participantId: ChannelRendezvous.participantId(sk, isCreator: true),
        name: 'Bob',
        entryTs: now,
        ohs: [_oh('6.6.6.6:59558')],
      ),
    ];
    final content = await ChannelRendezvous.encryptRecordContent(sk, entries);
    final foreignSk = CryptoUtils.randomBytes(32).toList();
    final forged = await ChannelRendezvous.signContent(foreignSk, content, now);
    expect(await ChannelRendezvous.verifyRecord(forged), isTrue);

    final alice = joiner();
    final adopted = await alice.applyResolvedRecord(chan, forged, now + 1000);
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

  group('TD117: the merge state survives a worker respawn', () {
    final now = DateTime.utc(2026, 7, 19, 12).millisecondsSinceEpoch;

    /// Bob's record as Alice resolves it — gives Alice a merge state with
    /// Bob's entry and its `entry_ts`.
    Future<RendezvousManager> aliceWhoKnowsBob({
      required int bobTs,
      required String bobEndpoint,
    }) async {
      final bob = RendezvousManager()
        ..register(chan, channelSecret: sk, isCreator: true, ownName: 'Bob');
      bob.setOwnOhs(chan, [_oh(bobEndpoint)]);
      final store = (await bob.buildSignedStore(chan, bobTs))!;
      final alice = joiner();
      final adopted = await alice.applyResolvedRecord(
        chan,
        RendezvousManager.recordFromStoreBytes(store),
        bobTs + 1000,
      );
      expect(adopted, isNotNull);
      return alice;
    }

    test('export is null without state, and round-trips otherwise', () async {
      expect(creator().exportMergeState(chan), isNull);
      expect(creator().exportMergeState('unknown'), isNull);

      final alice = await aliceWhoKnowsBob(
        bobTs: now,
        bobEndpoint: '1.1.1.1:59558',
      );
      final exported = alice.exportMergeState(chan)!;

      // The respawned worker: same channel, empty merge state.
      final respawned = joiner()..restoreMergeState(chan, exported);
      expect(respawned.exportMergeState(chan), exported);
    });

    test(
      'a respawned worker keeps the newest-wins guard for the counterpart',
      () async {
        // Bob published twice; Alice saw the NEW record before the crash.
        final bob = RendezvousManager()
          ..register(chan, channelSecret: sk, isCreator: true, ownName: 'Bob');
        bob.setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
        final oldStore = (await bob.buildSignedStore(chan, now))!;
        bob.setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
        final newStore = (await bob.buildSignedStore(chan, now + 60000))!;

        final alice = joiner();
        expect(
          (await alice.applyResolvedRecord(
            chan,
            RendezvousManager.recordFromStoreBytes(newStore),
            now + 61000,
          ))!.single.serverEndpoint,
          '2.2.2.2:59558',
        );
        final exported = alice.exportMergeState(chan)!;

        // Without the restore the fresh worker has no entry_ts to compare
        // against and adopts the OLD record — a mailbox rollback.
        final naive = joiner();
        expect(
          (await naive.applyResolvedRecord(
            chan,
            RendezvousManager.recordFromStoreBytes(oldStore),
            now + 62000,
          ))!.single.serverEndpoint,
          '1.1.1.1:59558',
        );

        final respawned = joiner()..restoreMergeState(chan, exported);
        expect(
          await respawned.applyResolvedRecord(
            chan,
            RendezvousManager.recordFromStoreBytes(oldStore),
            now + 62000,
          ),
          isNull,
          reason: 'the restored entry_ts must still beat the stale record',
        );
      },
    );

    test('a respawned worker republishes a record that still carries the '
        'counterpart', () async {
      final alice = await aliceWhoKnowsBob(
        bobTs: now,
        bobEndpoint: '1.1.1.1:59558',
      );
      final exported = alice.exportMergeState(chan)!;

      Future<int> participantsInPublishedRecord(RendezvousManager m) async {
        m.setOwnOhs(chan, [_oh('9.9.9.9:59558')]);
        final store = (await m.buildSignedStore(chan, now + 120000))!;
        final record = RendezvousManager.recordFromStoreBytes(store);
        final entries = await ChannelRendezvous.decryptRecordContent(
          sk,
          record.content,
        );
        return entries.length;
      }

      // A fresh worker drops Bob out of the record it publishes; with the
      // restored merge state the record carries both participants again.
      expect(await participantsInPublishedRecord(joiner()), 1);
      final respawned = joiner()..restoreMergeState(chan, exported);
      expect(await participantsInPublishedRecord(respawned), 2);
    });

    test('restore only adds knowledge — live state wins', () async {
      final older = await aliceWhoKnowsBob(
        bobTs: now,
        bobEndpoint: '1.1.1.1:59558',
      );
      final snapshotOfOlder = older.exportMergeState(chan)!;

      // The respawned worker already resolved a NEWER record before the
      // restore command arrived.
      final live = await aliceWhoKnowsBob(
        bobTs: now + 60000,
        bobEndpoint: '2.2.2.2:59558',
      );
      live.restoreMergeState(chan, snapshotOfOlder);
      expect(live.exportMergeState(chan), contains('2.2.2.2:59558'));
      expect(live.exportMergeState(chan), isNot(contains('1.1.1.1:59558')));
    });

    test(
      'a malformed or foreign snapshot leaves the live state alone',
      () async {
        final alice = await aliceWhoKnowsBob(
          bobTs: now,
          bobEndpoint: '1.1.1.1:59558',
        );
        final before = alice.exportMergeState(chan)!;
        for (final junk in [
          'not json',
          '{}',
          '[{"pid":"zz","name":"x","ts":1,"ohs":[]}]', // not hex
          '[{"pid":"aa","name":"x","ts":1,"ohs":[]}]', // pid not 32 bytes
          '[{"name":"x","ts":1,"ohs":[]}]', // missing pid
          '[{"pid":"${'aa' * 32}","name":"x","ts":"soon","ohs":[]}]', // ts type
        ]) {
          alice.restoreMergeState(chan, junk);
          expect(alice.exportMergeState(chan), before, reason: 'junk: $junk');
        }
        // An unknown channel is ignored rather than resurrected.
        alice.restoreMergeState('unknown-channel', before);
        expect(alice.exportMergeState('unknown-channel'), isNull);
      },
    );
  });

  group('T111: re-registration and the advertised display name', () {
    test('a re-register without a name keeps the published one', () {
      final m = creator();
      // A caller that holds only the channel row knows no display name; it
      // must not blank the name already in the record (this is what
      // `chat_screen.build` did on every rebuild).
      m.register(chan, channelSecret: sk, isCreator: true, ownName: null);
      expect(m.ownNameOf(chan), equals('Alice'));
    });

    test('an explicit empty name does clear it', () {
      final m = creator();
      m.register(chan, channelSecret: sk, isCreator: true, ownName: '');
      expect(m.ownNameOf(chan), isEmpty);
    });

    test('a first registration without a name means no name', () {
      final m = RendezvousManager()
        ..register(chan, channelSecret: sk, isCreator: true, ownName: null);
      expect(m.ownNameOf(chan), isEmpty);
    });

    test('a re-register keeps the accumulated merge state', () {
      final m = creator();
      final oh = _oh('1.1.1.1:59558');
      expect(m.setOwnOhs(chan, [oh]), isTrue);
      m.register(chan, channelSecret: sk, isCreator: true, ownName: 'Alice');
      // Unchanged set ⇒ no spurious publish, i.e. the state survived.
      expect(m.setOwnOhs(chan, [oh]), isFalse);
    });
  });
}
