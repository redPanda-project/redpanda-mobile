import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';

void main() {
  final channelKey = List<int>.generate(32, (i) => i);
  final channelId = '00112233' * 8;

  ChannelMessage msg(String content) => ChannelMessage(
    messageId: Uint8List.fromList(
      List<int>.generate(16, (i) => content.hashCode + i),
    ),
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    content: content,
  );

  Future<(RatchetSession, RatchetSession)> pair() async {
    final creator = await RatchetSession.create(
      channelKey: channelKey,
      isChannelCreator: true,
    );
    final joiner = await RatchetSession.create(
      channelKey: channelKey,
      isChannelCreator: false,
    );
    return (creator, joiner);
  }

  group('MS03b RatchetSession: lockstep exchange', () {
    test('creator → joiner first message (bootstrap chain)', () async {
      final (creator, joiner) = await pair();
      final payload = await creator.encrypt(msg('hello'), channelId);
      expect(payload[0], MessageCryptoV4.version);
      final decoded = await joiner.decrypt(payload, channelId);
      expect(decoded.content, 'hello');
    });

    test('joiner → creator first message (first DH step)', () async {
      final (creator, joiner) = await pair();
      final payload = await joiner.encrypt(msg('hi there'), channelId);
      final decoded = await creator.decrypt(payload, channelId);
      expect(decoded.content, 'hi there');
    });

    test('long alternating conversation decrypts end-to-end', () async {
      final (creator, joiner) = await pair();
      for (var round = 0; round < 12; round++) {
        for (var i = 0; i < 3; i++) {
          final p = await creator.encrypt(msg('c$round-$i'), channelId);
          expect((await joiner.decrypt(p, channelId)).content, 'c$round-$i');
        }
        for (var i = 0; i < 2; i++) {
          final p = await joiner.encrypt(msg('j$round-$i'), channelId);
          expect((await creator.decrypt(p, channelId)).content, 'j$round-$i');
        }
      }
    });

    test('mismatched roles cannot decrypt', () async {
      final a = await RatchetSession.create(
        channelKey: channelKey,
        isChannelCreator: true,
      );
      final b = await RatchetSession.create(
        channelKey: channelKey,
        isChannelCreator: true, // wrong: both claim the creator role
      );
      final payload = await a.encrypt(msg('x'), channelId);
      expect(
        () => b.decrypt(payload, channelId),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });
  });

  group('MS03b RatchetSession: out-of-order delivery', () {
    test('late message within a chain is served from skipped keys', () async {
      final (creator, joiner) = await pair();
      final p0 = await creator.encrypt(msg('m0'), channelId);
      final p1 = await creator.encrypt(msg('m1'), channelId);
      final p2 = await creator.encrypt(msg('m2'), channelId);

      expect((await joiner.decrypt(p2, channelId)).content, 'm2');
      expect((await joiner.decrypt(p0, channelId)).content, 'm0');
      expect((await joiner.decrypt(p1, channelId)).content, 'm1');
    });

    test('late message from the previous chain decrypts after a DH step '
        '(prev_chain_len handling)', () async {
      final (creator, joiner) = await pair();

      // Creator sends a0, a1 on the bootstrap chain; only a0 arrives.
      final a0 = await creator.encrypt(msg('a0'), channelId);
      final a1 = await creator.encrypt(msg('a1'), channelId);
      expect((await joiner.decrypt(a0, channelId)).content, 'a0');

      // Round trip: joiner replies, creator DH-steps and sends on the new
      // chain. The new header announces prev_chain_len = 2.
      final b0 = await joiner.encrypt(msg('b0'), channelId);
      expect((await creator.decrypt(b0, channelId)).content, 'b0');
      final a2 = await creator.encrypt(msg('a2'), channelId);
      expect((await joiner.decrypt(a2, channelId)).content, 'a2');

      // a1 arrives hours late — still decryptable from the skipped store.
      expect((await joiner.decrypt(a1, channelId)).content, 'a1');
    });

    test(
      'replayed message is rejected and leaves the session usable',
      () async {
        final (creator, joiner) = await pair();
        final p0 = await creator.encrypt(msg('m0'), channelId);
        await joiner.decrypt(p0, channelId);

        expect(
          () => joiner.decrypt(p0, channelId),
          throwsA(isA<RatchetException>()),
        );

        // The session keeps working after the rejected replay.
        final p1 = await creator.encrypt(msg('m1'), channelId);
        expect((await joiner.decrypt(p1, channelId)).content, 'm1');
      },
    );

    test('gap larger than maxSkip is declared undecryptable', () async {
      final (creator, joiner) = await pair();
      final p0 = await creator.encrypt(msg('m0'), channelId);
      await joiner.decrypt(p0, channelId);

      // Forge a header far ahead in the same chain: the key derivation is
      // refused before any chain grinding happens.
      final header = MessageCryptoV4.parseHeader(p0);
      final forged = await MessageCryptoV4.seal(
        messageKey: List<int>.filled(32, 1),
        ratchetPublicKey: header.ratchetPublicKey,
        previousChainLength: 0,
        chainCounter: RatchetSession.maxSkip + 2,
        plaintext: msg('far').encode(),
        channelId: channelId,
      );
      expect(
        () => joiner.decrypt(forged, channelId),
        throwsA(isA<RatchetException>()),
      );
    });

    test('tampered payload does not corrupt or advance the state', () async {
      final (creator, joiner) = await pair();
      final p0 = await creator.encrypt(msg('m0'), channelId);

      final tampered = Uint8List.fromList(p0);
      tampered[tampered.length - 1] ^= 0x01; // break the GCM tag
      expect(
        () => joiner.decrypt(tampered, channelId),
        throwsA(isA<GcmAuthenticationException>()),
      );

      // Commit-on-success: the original message still decrypts.
      expect((await joiner.decrypt(p0, channelId)).content, 'm0');
    });

    test(
      'header counter tamper fails authentication without state damage',
      () async {
        final (creator, joiner) = await pair();
        final p0 = await creator.encrypt(msg('m0'), channelId);
        final p1 = await creator.encrypt(msg('m1'), channelId);

        // Bump chain_counter in the clear header of p0: the receiver derives
        // the key for the claimed counter, the AAD check then fails.
        final tampered = Uint8List.fromList(p0);
        tampered[1 + 32 + 4 + 3] += 2;
        expect(
          () => joiner.decrypt(tampered, channelId),
          throwsA(isA<GcmAuthenticationException>()),
        );

        expect((await joiner.decrypt(p0, channelId)).content, 'm0');
        expect((await joiner.decrypt(p1, channelId)).content, 'm1');
      },
    );
  });

  group('MS03b RatchetSession: persistence', () {
    test('toJson/fromJson roundtrip continues the conversation', () async {
      final (creator, joiner) = await pair();
      final p0 = await creator.encrypt(msg('before'), channelId);
      await joiner.decrypt(p0, channelId);
      final b0 = await joiner.encrypt(msg('reply'), channelId);
      await creator.decrypt(b0, channelId);

      // Simulate app restarts on both sides.
      final creator2 = RatchetSession.fromJson(creator.toJson());
      final joiner2 = RatchetSession.fromJson(joiner.toJson());

      final p1 = await creator2.encrypt(msg('after restart'), channelId);
      expect((await joiner2.decrypt(p1, channelId)).content, 'after restart');
      final b1 = await joiner2.encrypt(msg('still works'), channelId);
      expect((await creator2.decrypt(b1, channelId)).content, 'still works');
    });

    test('restored skipped keys survive the roundtrip', () async {
      final (creator, joiner) = await pair();
      final p0 = await creator.encrypt(msg('m0'), channelId);
      final p1 = await creator.encrypt(msg('m1'), channelId);
      expect((await joiner.decrypt(p1, channelId)).content, 'm1');

      final restored = RatchetSession.fromJson(joiner.toJson());
      expect((await restored.decrypt(p0, channelId)).content, 'm0');
    });

    test('fromJson rejects malformed state', () {
      expect(() => RatchetSession.fromJson('{}'), throwsFormatException);
      expect(() => RatchetSession.fromJson('not json'), throwsFormatException);
      // Right version but missing fields: still a FormatException, not a
      // TypeError leaking out of the parser.
      expect(() => RatchetSession.fromJson('{"v":1}'), throwsFormatException);
    });
  });

  group('MS03b RatchetSession: forward secrecy & post-compromise security', () {
    test(
      'forward secrecy: current state cannot decrypt earlier messages',
      () async {
        final (creator, joiner) = await pair();
        final p0 = await creator.encrypt(msg('old secret'), channelId);
        final p1 = await creator.encrypt(msg('newer'), channelId);
        await joiner.decrypt(p0, channelId);
        await joiner.decrypt(p1, channelId);

        // Device seizure after both messages were read: the captured state
        // holds neither CK_0/CK_1 nor MK_0/MK_1 anymore.
        final seized = RatchetSession.fromJson(joiner.toJson());
        expect(
          () => seized.decrypt(p0, channelId),
          throwsA(isA<RatchetException>()),
        );
        expect(
          () => seized.decrypt(p1, channelId),
          throwsA(isA<RatchetException>()),
        );
      },
    );

    test(
      'post-compromise security: one round trip locks a state clone out',
      () async {
        final (creator, joiner) = await pair();

        // Some traffic, then the joiner's full state leaks.
        final p0 = await creator.encrypt(msg('m0'), channelId);
        await joiner.decrypt(p0, channelId);
        final stolen = RatchetSession.fromJson(joiner.toJson());

        // Healing round trip: joiner sends (fresh DH key), creator DH-steps
        // and replies with its own fresh key, joiner DH-steps again. The
        // joiner's fresh private key never appears in the stolen state.
        final b0 = await joiner.encrypt(msg('b0'), channelId);
        await creator.decrypt(b0, channelId);
        final a1 = await creator.encrypt(msg('a1'), channelId);
        await joiner.decrypt(a1, channelId);
        final b1 = await joiner.encrypt(msg('b1'), channelId);
        await creator.decrypt(b1, channelId);
        final a2 = await creator.encrypt(msg('post-heal secret'), channelId);

        // The clone can replicate the steps up to a1 (it holds the same key
        // material), but a2 was DH'd against the joiner's post-compromise
        // ratchet key, which the clone cannot know.
        await stolen.decrypt(a1, channelId);
        await expectLater(
          stolen.decrypt(a2, channelId),
          throwsA(isA<GcmAuthenticationException>()),
        );

        // The real joiner reads it fine.
        expect(
          (await joiner.decrypt(a2, channelId)).content,
          'post-heal secret',
        );
      },
    );
  });

  group('MS03b RatchetSession: validation', () {
    test('create rejects a wrong-length channel key', () {
      expect(
        () => RatchetSession.create(
          channelKey: List<int>.filled(16, 0),
          isChannelCreator: true,
        ),
        throwsArgumentError,
      );
    });

    test('v3 payloads are not accepted by the ratchet', () async {
      final (_, joiner) = await pair();
      final v3ish = Uint8List(80)..[0] = 0x03;
      expect(() => joiner.decrypt(v3ish, channelId), throwsFormatException);
    });
  });
}
