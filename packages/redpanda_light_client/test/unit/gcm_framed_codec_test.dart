import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/security/gcm_framed_codec.dart';
import 'package:test/test.dart';

void main() {
  final clientSend = List<int>.generate(32, (i) => i);
  final serverSend = List<int>.generate(32, (i) => 255 - i);

  (GcmFramedCodec, GcmFramedCodec) pair() {
    // client sends with clientSend, server receives with it (and vice versa)
    final client = GcmFramedCodec(sendKey: clientSend, receiveKey: serverSend);
    final server = GcmFramedCodec(sendKey: serverSend, receiveKey: clientSend);
    return (client, server);
  }

  group('GcmFramedCodec', () {
    test('roundtrip: encrypt -> decrypt recovers the plaintext', () async {
      final (client, server) = pair();
      final plaintext = List<int>.generate(1000, (i) => i % 256);

      final frames = await client.encrypt(plaintext);
      // [4 len][12 nonce][ct+16 tag]
      expect(frames.length, equals(4 + 12 + plaintext.length + 16));

      final decrypted = await server.decrypt(frames);
      expect(decrypted, equals(plaintext));
    });

    test('frame nonce is the big-endian counter starting at 0', () async {
      final (client, server) = pair();

      final frame0 = await client.encrypt([1]);
      expect(frame0.sublist(4, 16), equals(GcmFramedCodec.nonceFromCounter(0)));
      final frame1 = await client.encrypt([2]);
      expect(frame1.sublist(4, 16), equals(GcmFramedCodec.nonceFromCounter(1)));
      expect(
        GcmFramedCodec.nonceFromCounter(1).sublist(0, 11),
        equals([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      );
      expect(GcmFramedCodec.nonceFromCounter(1)[11], equals(1));

      expect(await server.decrypt(frame0), equals([1]));
      expect(await server.decrypt(frame1), equals([2]));
    });

    test('partial frames are buffered until complete', () async {
      final (client, server) = pair();
      final plaintext = [10, 20, 30];

      final frames = await client.encrypt(plaintext);
      final first = await server.decrypt(frames.sublist(0, 7));
      expect(first, isEmpty);
      final second = await server.decrypt(frames.sublist(7));
      expect(second, equals(plaintext));
    });

    test('large writes are split into max 32 KiB frames', () async {
      final (client, server) = pair();
      final plaintext = List<int>.generate(
        GcmFramedCodec.maxPlaintextPerFrame + 10,
        (i) => i % 256,
      );

      final frames = await client.encrypt(plaintext);
      // Two frames: 32 KiB + 10 bytes
      expect(frames.length, equals(2 * (4 + 12 + 16) + plaintext.length));
      expect(await server.decrypt(frames), equals(plaintext));
    });

    test('a flipped ciphertext bit fails authentication', () async {
      final (client, server) = pair();
      final frames = await client.encrypt([1, 2, 3, 4]);
      frames[frames.length - 20] ^= 0x01;

      expect(
        () => server.decrypt(frames),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('a replayed frame fails the counter check', () async {
      final (client, server) = pair();
      final frame = await client.encrypt([1, 2, 3]);

      expect(await server.decrypt(frame), equals([1, 2, 3]));
      // Same frame again: nonce counter 0 does not match expected 1.
      expect(
        () => server.decrypt(frame),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('reordered frames fail the counter check', () async {
      final (client, server) = pair();
      final frame0 = await client.encrypt([0]);
      final frame1 = await client.encrypt([1]);

      expect(
        () => server.decrypt(Uint8List.fromList([...frame1, ...frame0])),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('invalid frame length is rejected', () async {
      final (_, server) = pair();
      expect(
        () => server.decrypt([0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0]),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'per-direction keys: server cannot decrypt with swapped roles',
      () async {
        final (client, _) = pair();
        // A codec wired backwards (receive key = serverSend) must reject
        // client frames.
        final wrong = GcmFramedCodec(
          sendKey: clientSend,
          receiveKey: serverSend,
        );
        final frames = await client.encrypt([9, 9]);
        expect(
          () => wrong.decrypt(frames),
          throwsA(isA<GcmAuthenticationException>()),
        );
      },
    );

    test('deriveForInitiator derives matching directional keys', () async {
      final ourVerify = List<int>.generate(32, (i) => i);
      final theirVerify = List<int>.generate(32, (i) => i + 1);
      final shared = List<int>.generate(32, (i) => 7 * i % 256);

      // Initiator (client role)
      final initiator = await GcmFramedCodec.deriveForInitiator(
        sharedSecret: shared,
        ourVerifyKey: ourVerify,
        theirVerifyKey: theirVerify,
      );

      // Simulate the server side: client key = HKDF(salt=min, "tcp-client"),
      // server key = HKDF(salt=max, "tcp-server").
      final clientKey = await CryptoUtils.hkdfSha256(
        shared,
        ourVerify, // min (i < i+1 bytewise)
        'tcp-client',
        32,
      );
      final serverKey = await CryptoUtils.hkdfSha256(
        shared,
        theirVerify,
        'tcp-server',
        32,
      );
      final responder = GcmFramedCodec(
        sendKey: serverKey,
        receiveKey: clientKey,
      );

      final toServer = await initiator.encrypt([5]);
      expect(await responder.decrypt(toServer), equals([5]));
      final toClient = await responder.encrypt([6]);
      expect(await initiator.decrypt(toClient), equals([6]));
    });
  });
}
