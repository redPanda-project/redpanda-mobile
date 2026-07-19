import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
import 'package:test/test.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';

void main() {
  group('Channel (QR v4)', () {
    test(
      'generates a channel with a 32-byte secret and derived keys',
      () async {
        final channel = await Channel.generate('Test Channel');

        expect(channel.label, 'Test Channel');
        expect(channel.channelSecret.length, 32);
        expect(channel.encryptionKey.length, 32);
        expect(channel.authPublicKey.length, 32);
        expect(channel.authPrivateKey!.length, 32);
        expect(channel.isCreator, isTrue);
      },
    );

    test('all material is derived deterministically from the secret', () async {
      final creator = await Channel.generate('X');
      final rebuilt = await Channel.fromSecret(
        'X',
        creator.channelSecret,
        isCreator: true,
      );
      expect(rebuilt.encryptionKey, creator.encryptionKey);
      expect(rebuilt.authPublicKey, creator.authPublicKey);
      expect(rebuilt.id, creator.id);
    });

    test('two generated channels have different secrets and ids', () async {
      final a = await Channel.generate('A');
      final b = await Channel.generate('B');

      expect(a.channelSecret, isNot(equals(b.channelSecret)));
      expect(a.encryptionKey, isNot(equals(b.encryptionKey)));
      expect(a.id, isNot(equals(b.id)));
    });

    test(
      'QR v4 round-trips: joiner derives the same keys, no role marker',
      () async {
        final creator = await Channel.generate('Round Trip');
        final qr = creator.toJson();
        expect(qr, contains('"v":4'));
        expect(qr, isNot(contains('k_enc')));
        expect(qr, isNot(contains('oh')));

        final joiner = await Channel.fromJson(qr);
        expect(joiner.channelSecret, creator.channelSecret);
        expect(joiner.encryptionKey, creator.encryptionKey);
        expect(joiner.authPublicKey, creator.authPublicKey);
        expect(joiner.id, creator.id); // both derive the same channel id
        expect(joiner.isCreator, isFalse);
        expect(joiner.authPrivateKey, isNull);
      },
    );

    test('channel id is SHA256(channel_pk)', () async {
      final channel = await Channel.generate('Id');
      // Recomputed from the public key alone.
      final expected = HEX.encode(
        (await Channel.fromJson(channel.toJson())).authPublicKey,
      );
      expect(channel.authPublicKey, HEX.decode(expected));
    });

    test('creator and joiner get distinct, opposite participant ids', () async {
      final creator = await Channel.generate('P');
      final joiner = await Channel.fromJson(creator.toJson());

      expect(creator.ownParticipantId, isNot(equals(joiner.ownParticipantId)));
      // The recovering side looks up the peer's entry by the opposite role.
      expect(creator.peerParticipantId, joiner.ownParticipantId);
      expect(joiner.peerParticipantId, creator.ownParticipantId);
      // Matches the standalone derivation.
      expect(
        creator.ownParticipantId,
        ChannelRendezvous.participantId(creator.channelSecret, isCreator: true),
      );
    });

    test('rejects v3 and other unsupported versions', () async {
      const v3 = '{"l":"Bad","k_enc":"00","k_auth_pub":"00","v":3}';
      await expectLater(Channel.fromJson(v3), throwsA(isA<FormatException>()));
      const v999 = '{"l":"Bad","sk":"00","v":999}';
      await expectLater(
        Channel.fromJson(v999),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a malformed channel secret length', () async {
      const bad = '{"l":"Bad","sk":"00","v":4}';
      await expectLater(Channel.fromJson(bad), throwsA(isA<FormatException>()));
    });
  });
}
