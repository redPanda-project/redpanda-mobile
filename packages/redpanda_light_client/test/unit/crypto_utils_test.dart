import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:test/test.dart';

void main() {
  group('CryptoUtils Ed25519', () {
    test('sign/verify roundtrip with RFC 8032 test vector', () async {
      // RFC 8032 §7.1 TEST 2: one-byte message 0x72.
      final seed = _hex(
        '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
      );
      final expectedPublic = _hex(
        '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
      );
      final expectedSignature = _hex(
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
        '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      );

      final keypair = await CryptoUtils.signingKeypairFromSeed(seed);
      expect(keypair.publicKey, equals(expectedPublic));

      final signature = await CryptoUtils.sign(seed, [0x72]);
      expect(signature, equals(expectedSignature));

      expect(
        await CryptoUtils.verify(keypair.publicKey, [0x72], signature),
        true,
      );
      expect(
        await CryptoUtils.verify(keypair.publicKey, [0x73], signature),
        false,
      );
    });
  });

  group('CryptoUtils X25519', () {
    test('both sides derive the same shared secret', () async {
      final a = await CryptoUtils.generateEncryptionKeypair();
      final b = await CryptoUtils.generateEncryptionKeypair();

      final sharedA = await CryptoUtils.x25519(a.privateKey, b.publicKey);
      final sharedB = await CryptoUtils.x25519(b.privateKey, a.publicKey);

      expect(sharedA.length, 32);
      expect(sharedA, equals(sharedB));
    });

    test('RFC 7748 §6.1 test vector', () async {
      final alicePriv = _hex(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
      );
      final bobPub = _hex(
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f',
      );
      final expectedShared = _hex(
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742',
      );

      final shared = await CryptoUtils.x25519(alicePriv, bobPub);
      expect(shared, equals(expectedShared));
    });
  });

  group('CryptoUtils HKDF-SHA256', () {
    test('RFC 5869 test case 1', () async {
      final ikm = _hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b');
      final salt = _hex('000102030405060708090a0b0c');
      // info = 0xf0f1f2f3f4f5f6f7f8f9 — not ASCII, so test via raw helper
      // by comparing against a known derivation of the ASCII-info variant
      // is not possible; instead verify determinism and length here and the
      // ASCII-info path against the backend in the e2e tests.
      final okm1 = await CryptoUtils.hkdfSha256(ikm, salt, 'tcp-client', 42);
      final okm2 = await CryptoUtils.hkdfSha256(ikm, salt, 'tcp-client', 42);
      final other = await CryptoUtils.hkdfSha256(ikm, salt, 'tcp-server', 42);

      expect(okm1.length, 42);
      expect(okm1, equals(okm2));
      expect(okm1, isNot(equals(other)));
    });
  });

  group('CryptoUtils AES-256-GCM', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i * 2));

    test('roundtrip with AAD', () async {
      final plaintext = List<int>.generate(50, (i) => i);
      final aad = [9, 9, 9];

      final ct = await CryptoUtils.aesGcmEncrypt(key, nonce, plaintext, aad);
      expect(ct.length, plaintext.length + CryptoUtils.gcmTagLength);

      final decrypted = await CryptoUtils.aesGcmDecrypt(key, nonce, ct, aad);
      expect(decrypted, equals(plaintext));
    });

    test('tampered ciphertext fails', () async {
      final ct = await CryptoUtils.aesGcmEncrypt(key, nonce, [1, 2, 3], []);
      ct[0] ^= 0x01;
      expect(
        () => CryptoUtils.aesGcmDecrypt(key, nonce, ct, []),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('wrong AAD fails', () async {
      final ct = await CryptoUtils.aesGcmEncrypt(key, nonce, [1, 2, 3], [1]);
      expect(
        () => CryptoUtils.aesGcmDecrypt(key, nonce, ct, [2]),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('too-short ciphertext fails cleanly', () async {
      expect(
        () => CryptoUtils.aesGcmDecrypt(key, nonce, [1, 2, 3], []),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });
  });

  group('CryptoUtils helpers', () {
    test('constantTimeEquals', () {
      expect(CryptoUtils.constantTimeEquals([1, 2, 3], [1, 2, 3]), true);
      expect(CryptoUtils.constantTimeEquals([1, 2, 3], [1, 2, 4]), false);
      expect(CryptoUtils.constantTimeEquals([1, 2], [1, 2, 3]), false);
    });

    test('compareUnsigned sorts byte-wise like Java Arrays.compareUnsigned',
        () {
      expect(CryptoUtils.compareUnsigned([0x00], [0xff]), lessThan(0));
      expect(CryptoUtils.compareUnsigned([0xff], [0x00]), greaterThan(0));
      expect(CryptoUtils.compareUnsigned([1, 2], [1, 2]), 0);
      expect(CryptoUtils.compareUnsigned([1], [1, 0]), lessThan(0));
    });

    test('randomBytes returns requested length and varies', () {
      final a = CryptoUtils.randomBytes(32);
      final b = CryptoUtils.randomBytes(32);
      expect(a.length, 32);
      expect(a, isNot(equals(b)));
    });
  });
}

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
