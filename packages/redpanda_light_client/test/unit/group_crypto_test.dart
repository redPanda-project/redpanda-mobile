import 'dart:convert';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/group_control.dart';
import 'package:redpanda_light_client/src/crypto/group_crypto.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';

/// One in-memory group member for the tests: identity keys plus a crypto
/// session, all sharing the same epoch secret.
class _Member {
  final Ed25519KeyPairBytes signKeys;
  final X25519KeyPairBytes x25519Keys;
  final GroupCryptoSession session;

  _Member(this.signKeys, this.x25519Keys, this.session);

  String get memberIdHex => HEX.encode(signKeys.publicKey);

  static Future<_Member> create(String groupId) async {
    return _Member(
      await CryptoUtils.generateSigningKeypair(),
      await CryptoUtils.generateEncryptionKeypair(),
      GroupCryptoSession.empty(groupId),
    );
  }
}

Future<List<_Member>> _groupOf(
  String groupId,
  int size, {
  int epoch = 1,
  List<int>? secret,
}) async {
  final members = [
    for (var i = 0; i < size; i++) await _Member.create(groupId),
  ];
  final ids = [for (final m in members) m.memberIdHex];
  final epochSecret = secret ?? CryptoUtils.randomBytes(32);
  for (final member in members) {
    await member.session.installEpoch(epoch, epochSecret, ids);
  }
  return members;
}

void main() {
  const groupId =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('GroupCryptoSession v5 envelope', () {
    test('round-trips between members and authenticates the sender', () async {
      final members = await _groupOf(groupId, 3);
      final alice = members[0];

      final payload = await alice.session.encrypt(
        utf8.encode('hello group'),
        myMemberIdHex: alice.memberIdHex,
        mySignSeed: alice.signKeys.privateSeed,
      );
      expect(payload[0], GroupCryptoSession.versionGroupMessage);
      expect(
        payload.length,
        utf8.encode('hello group').length + GroupCryptoSession.envelopeOverhead,
      );

      for (final receiver in members.skip(1)) {
        // Each member decrypts an own copy — same ciphertext for everyone.
        final result = await receiver.session.decrypt(payload);
        expect(utf8.decode(result.plaintext), 'hello group');
        expect(result.senderMemberIdHex, alice.memberIdHex);
        expect(result.epoch, 1);
      }
    });

    test('rejects a replayed counter', () async {
      final members = await _groupOf(groupId, 2);
      final payload = await members[0].session.encrypt(
        utf8.encode('once'),
        myMemberIdHex: members[0].memberIdHex,
        mySignSeed: members[0].signKeys.privateSeed,
      );
      await members[1].session.decrypt(payload);
      expect(
        () => members[1].session.decrypt(payload),
        throwsA(isA<GroupCryptoException>()),
      );
    });

    test('serves out-of-order messages from the skipped-key store', () async {
      final members = await _groupOf(groupId, 2);
      final alice = members[0];
      final bob = members[1];

      final first = await alice.session.encrypt(
        utf8.encode('first'),
        myMemberIdHex: alice.memberIdHex,
        mySignSeed: alice.signKeys.privateSeed,
      );
      final second = await alice.session.encrypt(
        utf8.encode('second'),
        myMemberIdHex: alice.memberIdHex,
        mySignSeed: alice.signKeys.privateSeed,
      );

      final outOfOrder = await bob.session.decrypt(second);
      expect(utf8.decode(outOfOrder.plaintext), 'second');
      final late = await bob.session.decrypt(first);
      expect(utf8.decode(late.plaintext), 'first');
    });

    test('rejects a forged sender signature', () async {
      final members = await _groupOf(groupId, 3);
      final alice = members[0];
      final mallory = members[2];

      // Mallory tries to speak as Alice: she knows every key derived from
      // the epoch secret (including Alice's chain) but not Alice's signing
      // seed, so she signs with her own.
      final aliceId = Uint8List.fromList(HEX.decode(alice.memberIdHex));
      final forged = await _forgeAs(
        groupId,
        members,
        senderId: aliceId,
        signSeed: mallory.signKeys.privateSeed,
      );
      expect(
        () => members[1].session.decrypt(forged),
        throwsA(isA<GroupCryptoException>()),
      );
    });

    test('rejects senders without a chain (not a member)', () async {
      final members = await _groupOf(groupId, 2);
      final outsider = await _Member.create(groupId);

      final outsiderId = Uint8List.fromList(HEX.decode(outsider.memberIdHex));
      final forged = await _forgeAs(
        groupId,
        members,
        senderId: outsiderId,
        signSeed: outsider.signKeys.privateSeed,
      );
      expect(
        () => members[1].session.decrypt(forged),
        throwsA(isA<GroupCryptoException>()),
      );
    });

    test('throws GroupUnknownEpochException for a future epoch', () async {
      final members = await _groupOf(groupId, 2);
      final ids = [for (final m in members) m.memberIdHex];

      // Sender rotates to epoch 2, receiver has not.
      await members[0].session.installEpoch(
        2,
        CryptoUtils.randomBytes(32),
        ids,
      );
      final payload = await members[0].session.encrypt(
        utf8.encode('future'),
        myMemberIdHex: members[0].memberIdHex,
        mySignSeed: members[0].signKeys.privateSeed,
      );
      expect(
        () => members[1].session.decrypt(payload),
        throwsA(isA<GroupUnknownEpochException>()),
      );
    });

    test(
      'decrypts a late message of an archived epoch after rotation',
      () async {
        final members = await _groupOf(groupId, 2);
        final ids = [for (final m in members) m.memberIdHex];

        final lateMessage = await members[0].session.encrypt(
          utf8.encode('late from epoch 1'),
          myMemberIdHex: members[0].memberIdHex,
          mySignSeed: members[0].signKeys.privateSeed,
        );

        // Both rotate to epoch 2, then the epoch-1 message arrives.
        final secret2 = CryptoUtils.randomBytes(32);
        await members[0].session.installEpoch(2, secret2, ids);
        await members[1].session.installEpoch(2, secret2, ids);

        final result = await members[1].session.decrypt(lateMessage);
        expect(utf8.decode(result.plaintext), 'late from epoch 1');
        expect(result.epoch, 1);
      },
    );

    test('a member removed at rotation cannot read the new epoch', () async {
      final members = await _groupOf(groupId, 3);
      final ids = [for (final m in members) m.memberIdHex];
      final removed = members[2];

      // Rotate epoch 2 without the removed member; it never receives the
      // secret, so its session stays at epoch 1.
      final remainingIds = ids.sublist(0, 2);
      final secret2 = CryptoUtils.randomBytes(32);
      await members[0].session.installEpoch(2, secret2, remainingIds);
      await members[1].session.installEpoch(2, secret2, remainingIds);

      final payload = await members[0].session.encrypt(
        utf8.encode('secret meeting'),
        myMemberIdHex: members[0].memberIdHex,
        mySignSeed: members[0].signKeys.privateSeed,
      );
      expect(
        () => removed.session.decrypt(payload),
        throwsA(isA<GroupUnknownEpochException>()),
      );
      final result = await members[1].session.decrypt(payload);
      expect(utf8.decode(result.plaintext), 'secret meeting');
    });

    test('stale rotations are ignored', () async {
      final members = await _groupOf(groupId, 2, epoch: 3);
      final installed = await members[0].session.installEpoch(
        2,
        CryptoUtils.randomBytes(32),
        [for (final m in members) m.memberIdHex],
      );
      expect(installed, false);
      expect(members[0].session.epoch, 3);
    });

    test('state survives JSON round-trip', () async {
      final members = await _groupOf(groupId, 2);
      final alice = members[0];
      final bob = members[1];

      final first = await alice.session.encrypt(
        utf8.encode('before persist'),
        myMemberIdHex: alice.memberIdHex,
        mySignSeed: alice.signKeys.privateSeed,
      );
      await bob.session.decrypt(first);

      final restored = GroupCryptoSession.fromJson(
        groupId,
        bob.session.toJson(),
      );
      final second = await alice.session.encrypt(
        utf8.encode('after persist'),
        myMemberIdHex: alice.memberIdHex,
        mySignSeed: alice.signKeys.privateSeed,
      );
      final result = await restored.decrypt(second);
      expect(utf8.decode(result.plaintext), 'after persist');

      // The replay protection survives too.
      expect(
        () => restored.decrypt(first),
        throwsA(isA<GroupCryptoException>()),
      );
    });

    test('fromJson normalizes malformed input to FormatException', () {
      expect(
        () => GroupCryptoSession.fromJson(groupId, '{"v":1}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => GroupCryptoSession.fromJson(groupId, 'not json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GroupCryptoSession v6 sealed control', () {
    test('round-trips for the right member and group', () async {
      final keys = await CryptoUtils.generateEncryptionKeypair();
      final sealed = await GroupCryptoSession.seal(
        utf8.encode('rotation payload'),
        memberX25519Pub: keys.publicKey,
        groupId: groupId,
      );
      expect(sealed[0], GroupCryptoSession.versionSealedControl);
      final opened = await GroupCryptoSession.unseal(
        sealed,
        myX25519Priv: keys.privateKey,
        groupId: groupId,
      );
      expect(utf8.decode(opened), 'rotation payload');
    });

    test('rejects the wrong recipient key and the wrong group', () async {
      final keys = await CryptoUtils.generateEncryptionKeypair();
      final other = await CryptoUtils.generateEncryptionKeypair();
      final sealed = await GroupCryptoSession.seal(
        utf8.encode('secret'),
        memberX25519Pub: keys.publicKey,
        groupId: groupId,
      );
      expect(
        () => GroupCryptoSession.unseal(
          sealed,
          myX25519Priv: other.privateKey,
          groupId: groupId,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
      expect(
        () => GroupCryptoSession.unseal(
          sealed,
          myX25519Priv: keys.privateKey,
          groupId: 'b' * 64,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });
  });

  group('Group control codecs', () {
    test('KeyRotation round-trips through GroupControl', () {
      final rotation = KeyRotation(
        groupSecret: Uint8List.fromList(List.filled(32, 7)),
        keyEpoch: 4,
        members: [
          GroupMemberInfo(
            memberIdHex: 'a' * 64,
            displayName: 'Alice',
            ohId: List.filled(20, 1),
            ohEndpoint: 'localhost:59558',
            x25519PubHex: 'b' * 64,
            role: GroupMemberInfo.roleAdmin,
          ),
          const GroupMemberInfo(
            memberIdHex:
                'cc'
                'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
                'cc',
            displayName: 'Böb 😀',
            x25519PubHex:
                'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
                'dddd',
            role: GroupMemberInfo.roleMember,
          ),
        ],
        groupName: 'Test-Gruppe',
      );
      final decoded = GroupControl.decode(
        GroupControl.rotation(rotation).encode(),
      );
      final result = decoded.keyRotation!;
      expect(result.groupSecret, rotation.groupSecret);
      expect(result.keyEpoch, 4);
      expect(result.groupName, 'Test-Gruppe');
      expect(result.members.length, 2);
      expect(result.members[0], rotation.members[0]);
      expect(result.members[1].displayName, 'Böb 😀');
      expect(result.members[1].ohId, isNull);
    });

    test('GroupInfoUpdate round-trips', () {
      final decoded = GroupControl.decode(
        GroupControl.info(const GroupInfoUpdate(name: 'Neuer Name')).encode(),
      );
      expect(decoded.infoUpdate!.name, 'Neuer Name');
      expect(decoded.keyRotation, isNull);
    });

    test('GroupHandshake proposal and accept round-trip', () {
      final proposal = GroupHandshake.decode(
        GroupHandshake.proposal(
          groupIdHex: 'a' * 64,
          groupName: 'Runde',
          adminMemberIdHex: 'e' * 64,
        ).encode(),
      );
      expect(proposal.isProposal, true);
      expect(proposal.proposalGroupIdHex, 'a' * 64);
      expect(proposal.proposalGroupName, 'Runde');
      expect(proposal.proposalAdminMemberIdHex, 'e' * 64);

      final accept = GroupHandshake.decode(
        GroupHandshake.accept(
          groupIdHex: 'a' * 64,
          memberIdHex: 'b' * 64,
          x25519PubHex: 'c' * 64,
          ohId: List.filled(20, 9),
          ohEndpoint: 'localhost:59559',
        ).encode(),
      );
      expect(accept.isProposal, false);
      expect(accept.acceptGroupIdHex, 'a' * 64);
      expect(accept.acceptMemberIdHex, 'b' * 64);
      expect(accept.acceptX25519PubHex, 'c' * 64);
      expect(accept.acceptOhId, List.filled(20, 9));
      expect(accept.acceptOhEndpoint, 'localhost:59559');
    });

    test('malformed input throws FormatException', () {
      expect(
        () => GroupControl.decode([0xFF, 0xFF]),
        throwsA(isA<FormatException>()),
      );
      expect(() => GroupHandshake.decode([]), throwsA(isA<FormatException>()));
    });
  });
}

/// Builds a syntactically valid v5 envelope claiming [senderId] but signed
/// with [signSeed] — the forgery a malicious member could attempt (all
/// symmetric keys are derivable from the shared epoch secret; the Ed25519
/// seed is not).
Future<Uint8List> _forgeAs(
  String groupId,
  List<_Member> members, {
  required Uint8List senderId,
  required List<int> signSeed,
}) async {
  // Reconstruct the symmetric material exactly like the session does. We
  // reuse a fresh session sharing the same secret via JSON copy from a real
  // member — simplest path: pull the outer key and chain out of the state.
  final state = jsonDecode(members[0].session.toJson()) as Map<String, dynamic>;
  final outerKey = Uint8List.fromList(HEX.decode(state['ko'] as String));
  final chains = state['chains'] as Map<String, dynamic>;
  final chain = chains[HEX.encode(senderId)] as Map<String, dynamic>?;
  final chainKey = chain != null
      ? Uint8List.fromList(HEX.decode(chain['ck'] as String))
      : CryptoUtils.randomBytes(32);
  final counter = chain != null ? chain['n'] as int : 0;

  final messageKey = await CryptoUtils.hkdfSha256(
    chainKey,
    const [],
    'ms08-msg-v1',
    32,
  );
  final aad = BytesBuilder()
    ..add(utf8.encode(groupId))
    ..add((ByteData(4)..setUint32(0, 1)).buffer.asUint8List())
    ..add(senderId)
    ..add((ByteData(4)..setUint32(0, counter)).buffer.asUint8List());
  final aadBytes = aad.toBytes();
  final innerNonce = CryptoUtils.randomBytes(12);
  final innerCt = await CryptoUtils.aesGcmEncrypt(
    messageKey,
    innerNonce,
    utf8.encode('forged'),
    aadBytes,
  );
  final signature = await CryptoUtils.sign(signSeed, [
    ...aadBytes,
    ...innerNonce,
    ...innerCt,
  ]);
  final inner = BytesBuilder()
    ..add(senderId)
    ..add((ByteData(4)..setUint32(0, counter)).buffer.asUint8List())
    ..add(innerNonce)
    ..add(innerCt)
    ..add(signature);
  final outerNonce = CryptoUtils.randomBytes(12);
  final outerCt = await CryptoUtils.aesGcmEncrypt(
    outerKey,
    outerNonce,
    inner.toBytes(),
    utf8.encode(groupId),
  );
  final out = BytesBuilder()
    ..addByte(GroupCryptoSession.versionGroupMessage)
    ..add((ByteData(4)..setUint32(0, 1)).buffer.asUint8List())
    ..add(outerNonce)
    ..add(outerCt);
  return out.toBytes();
}
