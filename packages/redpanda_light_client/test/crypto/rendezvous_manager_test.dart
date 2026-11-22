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

  group('T160 read-before-write / read-repair', () {
    final now = DateTime.utc(2026, 11, 22, 12).millisecondsSinceEpoch;

    test(
      'knowsCounterpartEntry flips only once the other ROLE was read',
      () async {
        final a = creator();
        final b = joiner();
        expect(b.isCreatorOf(chan), isFalse);
        expect(a.isCreatorOf(chan), isTrue);
        expect(b.isCreatorOf('other'), isNull);
        expect(b.knowsCounterpartEntry(chan), isFalse);

        // Bob's own publish does not count as knowing Alice.
        b.setOwnOhs(chan, [_oh('9.9.9.9:59558')]);
        final ownStore = (await b.buildSignedStore(chan, now))!;
        await b.applyResolvedRecord(
          chan,
          RendezvousManager.recordFromStoreBytes(ownStore),
          now + 1,
        );
        expect(b.knowsCounterpartEntry(chan), isFalse);

        a.setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
        final aliceStore = (await a.buildSignedStore(chan, now + 2))!;
        await b.applyResolvedRecord(
          chan,
          RendezvousManager.recordFromStoreBytes(aliceStore),
          now + 3,
        );
        expect(b.knowsCounterpartEntry(chan), isTrue);
      },
    );

    test('a newer record without our entry needs a repair; the merged '
        'republish carries both and settles it', () async {
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      // Bob published first (his hold timed out) ...
      await b.buildSignedStore(chan, now);
      // ... then Alice, blind, replaced it with her own entry only.
      final aliceOnly = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, now + 1000))!,
      );
      final resolved = await b.applyResolvedRecordDetailed(
        chan,
        aliceOnly,
        now + 2000,
      );
      expect(resolved!.needsRepair, isTrue);
      expect(resolved.counterpartOhs, hasLength(1));

      final merged = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, now + 3000))!,
      );
      final entries = await ChannelRendezvous.decryptRecordContent(
        sk,
        merged.content,
      );
      expect(entries, hasLength(2));
      // Reading our own merged record back is no reason to repair again.
      final again = await b.applyResolvedRecordDetailed(
        chan,
        merged,
        now + 4000,
      );
      expect(again!.needsRepair, isFalse);
    });

    test(
      'an OLDER record that teaches nothing new is no reason to repair',
      () async {
        final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
        final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
        final aliceOld = RendezvousManager.recordFromStoreBytes(
          (await a.buildSignedStore(chan, now))!,
        );
        // Bob already knows Alice's entry and has written it.
        await b.applyResolvedRecord(chan, aliceOld, now + 500);
        await b.buildSignedStore(chan, now + 1000);
        final resolved = await b.applyResolvedRecordDetailed(
          chan,
          aliceOld,
          now + 2000,
        );
        expect(resolved!.needsRepair, isFalse);
      },
    );

    test('P3: an OLDER record that teaches an entry our last write lacked '
        'needs a republish (late answer after a timed-out hold)', () async {
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      final aliceAtCreation = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, now))!,
      );
      // Bob's hold timed out: he wrote only himself, AFTER Alice's record.
      final bobAlone = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, now + 5000))!,
      );
      expect(aliceAtCreation.timestampMs, lessThan(bobAlone.timestampMs));
      final resolved = await b.applyResolvedRecordDetailed(
        chan,
        aliceAtCreation,
        now + 6000,
      );
      expect(resolved!.needsRepair, isTrue);
      expect(resolved.counterpartOhs, hasLength(1));
      // The merged republish carries both and settles it.
      final merged = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, now + 7000))!,
      );
      expect(
        await ChannelRendezvous.decryptRecordContent(sk, merged.content),
        hasLength(2),
      );
      final again = await b.applyResolvedRecordDetailed(
        chan,
        aliceAtCreation,
        now + 8000,
      );
      expect(again!.needsRepair, isFalse);
    });

    test(
      'a record carrying a STALE copy of our entry needs a repair',
      () async {
        final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
        final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
        // Alice learned Bob's first entry ...
        final bobFirst = RendezvousManager.recordFromStoreBytes(
          (await b.buildSignedStore(chan, now))!,
        );
        await a.applyResolvedRecord(chan, bobFirst, now + 1);
        // ... Bob moves his mailbox and publishes ...
        b.setOwnOhs(chan, [_oh('3.3.3.3:59558')]);
        await b.buildSignedStore(chan, now + 1000);
        // ... and Alice republishes with Bob's OLD entry.
        final aliceStale = RendezvousManager.recordFromStoreBytes(
          (await a.buildSignedStore(chan, now + 2000))!,
        );
        final resolved = await b.applyResolvedRecordDetailed(
          chan,
          aliceStale,
          now + 3000,
        );
        expect(resolved!.needsRepair, isTrue);
      },
    );

    test(
      'three participants: the joiner\'s merged write keeps every entry',
      () async {
        final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
        final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
        final carol = RendezvousEntry(
          participantId: CryptoUtils.randomBytes(32),
          name: 'Carol',
          entryTs: now - 5000,
          ohs: [_oh('4.4.4.4:59558')],
        );
        // Alice's record already carries a third participant's entry.
        final signed = await ChannelRendezvous.buildSignedRecord(
          sk,
          ChannelRendezvous.mergeEntries(
            [carol],
            [
              RendezvousEntry(
                participantId: ChannelRendezvous.participantId(
                  sk,
                  isCreator: true,
                ),
                name: 'Alice',
                entryTs: now,
                ohs: [_oh('1.1.1.1:59558')],
              ),
            ],
          ),
          now,
        );
        expect(a.knows(chan), isTrue);
        await b.applyResolvedRecordDetailed(chan, signed, now + 1000);
        final bobMerged = RendezvousManager.recordFromStoreBytes(
          (await b.buildSignedStore(chan, now + 2000))!,
        );
        final entries = await ChannelRendezvous.decryptRecordContent(
          sk,
          bobMerged.content,
        );
        expect(entries, hasLength(3));
        expect(
          entries.map((e) => e.name).toSet(),
          equals({'Alice', 'Bob', 'Carol'}),
        );
      },
    );
  });

  group('T160/P5 monotonic record timestamps', () {
    final now = DateTime.utc(2026, 11, 22, 12).millisecondsSinceEpoch;
    const minute = 60 * 1000;

    test('a writer whose clock runs 5 min behind still writes a NEWER record '
        'than the one it read', () async {
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      final alice = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, now))!,
      );
      final bobNow = now - 5 * minute; // Bob's clock
      await b.applyResolvedRecordDetailed(chan, alice, bobNow);
      final bob = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, bobNow))!,
      );
      expect(
        bob.timestampMs,
        greaterThan(alice.timestampMs),
        reason: 'the node replaces a record only by a strictly newer one',
      );
      // Alice reading it sees her entry in it: no repair, no loop.
      final resolved = await a.applyResolvedRecordDetailed(chan, bob, now + 1);
      expect(resolved!.needsRepair, isFalse);
    });

    test('a writer whose clock runs ahead keeps the other side able to '
        'overwrite after reading', () async {
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      final bobAhead = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, now + 5 * minute))!,
      );
      await a.applyResolvedRecordDetailed(chan, bobAhead, now);
      a.setOwnOhs(chan, [_oh('3.3.3.3:59558')]); // Alice moves
      final alice = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, now))!,
      );
      expect(alice.timestampMs, greaterThan(bobAhead.timestampMs));
    });

    test('Q6: a record further ahead than the node accepts (> 15 min) does '
        'not lift the floor', () async {
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      final bobFar = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, now + 60 * minute))!,
      );
      await a.applyResolvedRecordDetailed(chan, bobFar, now);
      final alice = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, now))!,
      );
      expect(alice.timestampMs, now);
    });

    test('a record inside the node\'s window lifts the floor, capped at '
        '14 min ahead', () async {
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      final bobAhead = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, now + 14 * minute + 30000))!,
      );
      await a.applyResolvedRecordDetailed(chan, bobAhead, now);
      final alice = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, now))!,
      );
      expect(alice.timestampMs, now + RendezvousManager.maxFutureLeadMs);
    });

    test('Q6: near UTC midnight the record timestamp never crosses into '
        'tomorrow — the node files it under the timestamp\'s day', () async {
      final late = DateTime.utc(2026, 11, 22, 23, 58).millisecondsSinceEpoch;
      final endOfDay = DateTime.utc(2026, 11, 23).millisecondsSinceEpoch - 1;
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      // Bob's clock is 90 s ahead: his record already says 23:59:30.
      final bob = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, late + 90000))!,
      );
      await a.applyResolvedRecordDetailed(chan, bob, late);
      // Another, still later one at the very last millisecond of the day.
      final bob2 = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, endOfDay))!,
      );
      await a.applyResolvedRecordDetailed(chan, bob2, late);
      final alice = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, late))!,
      );
      expect(alice.timestampMs, endOfDay, reason: 'capped at the day end');
      final todayKey = (await a.lookupKeys(chan, late)).first;
      expect(
        await ChannelRendezvous.rendezvousKademliaId(sk, alice.timestampMs),
        todayKey,
        reason: 'the write must stay findable under today\'s key',
      );
    });

    test('Q6: a record of TOMORROW (other clock ahead past midnight) does '
        'not set today\'s floor — it lives under another key', () async {
      final late = DateTime.utc(2026, 11, 22, 23, 55).millisecondsSinceEpoch;
      final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
      final b = joiner()..setOwnOhs(chan, [_oh('2.2.2.2:59558')]);
      final bobTomorrow = RendezvousManager.recordFromStoreBytes(
        (await b.buildSignedStore(chan, late + 10 * minute))!,
      );
      await a.applyResolvedRecordDetailed(chan, bobTomorrow, late);
      final alice = RendezvousManager.recordFromStoreBytes(
        (await a.buildSignedStore(chan, late))!,
      );
      expect(alice.timestampMs, late);
    });

    test(
      'successive own writes never go backwards, even if the clock does',
      () async {
        final a = creator()..setOwnOhs(chan, [_oh('1.1.1.1:59558')]);
        final first = RendezvousManager.recordFromStoreBytes(
          (await a.buildSignedStore(chan, now))!,
        );
        final second = RendezvousManager.recordFromStoreBytes(
          (await a.buildSignedStore(chan, now - 2 * minute))!,
        );
        expect(second.timestampMs, greaterThan(first.timestampMs));
        final entries = await ChannelRendezvous.decryptRecordContent(
          sk,
          second.content,
        );
        expect(entries.single.entryTs, greaterThan(now));
      },
    );
  });
}
