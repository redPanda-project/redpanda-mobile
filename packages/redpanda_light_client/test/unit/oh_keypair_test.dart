import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';

void main() {
  group('OHKeypair (Ed25519)', () {
    test('should generate a valid keypair with 32-byte keys', () async {
      final keypair = await OHKeypair.generate();

      expect(keypair.publicKeyBytes.length, 32);
      expect(keypair.privateKeyBytes.length, 32);
    });

    test('should generate different keys each time', () async {
      final a = await OHKeypair.generate();
      final b = await OHKeypair.generate();

      expect(a.publicKeyBytes, isNot(equals(b.publicKeyBytes)));
    });

    test('should sign and verify data with a 64-byte signature', () async {
      final keypair = await OHKeypair.generate();
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final signature = await keypair.sign(data);
      expect(signature.length, 64);

      final isValid = await keypair.verify(data, signature);
      expect(isValid, true);
    });

    test('signature covers the versioned bytes [0x02 | signingBytes]', () async {
      final keypair = await OHKeypair.generate();
      final data = Uint8List.fromList([10, 20, 30]);

      final signature = await keypair.sign(data);

      // The raw Ed25519 signature verifies over [0x02 | data] ...
      final versioned = Uint8List.fromList([
        OHKeypair.signingVersion,
        ...data,
      ]);
      expect(
        await CryptoUtils.verify(keypair.publicKeyBytes, versioned, signature),
        true,
      );
      // ... and NOT over the unversioned data (a v1-style signature check
      // must fail).
      expect(
        await CryptoUtils.verify(keypair.publicKeyBytes, data, signature),
        false,
      );
    });

    test('should export 32-byte seed and restore the same keypair', () async {
      final original = await OHKeypair.generate();

      final privBytes = original.privateKeyBytes;
      expect(privBytes.length, 32);

      final restored = await OHKeypair.fromPrivateKeyBytes(privBytes);
      expect(restored.publicKeyBytes, equals(original.publicKeyBytes));
      expect(restored.privateKeyBytes, equals(privBytes));

      // Signature from the restored key must verify with the original key
      final data = Uint8List.fromList(List.generate(16, (i) => i));
      final signature = await restored.sign(data);
      expect(await original.verify(data, signature), true);
    });

    test('should reject invalid private key bytes', () async {
      expect(
        () => OHKeypair.fromPrivateKeyBytes(Uint8List(16)),
        throwsArgumentError,
      );
    });

    test('should fail verification with tampered data', () async {
      final keypair = await OHKeypair.generate();
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final tampered = Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]);

      final signature = await keypair.sign(data);

      expect(await keypair.verify(tampered, signature), false);
    });

    test('should fail verification with a flipped signature bit', () async {
      final keypair = await OHKeypair.generate();
      final data = Uint8List.fromList([1, 2, 3, 4]);

      final signature = await keypair.sign(data);
      signature[0] ^= 0x01;

      expect(await keypair.verify(data, signature), false);
    });

    test('should fail verification with different key', () async {
      final keypair1 = await OHKeypair.generate();
      final keypair2 = await OHKeypair.generate();
      final data = Uint8List.fromList([1, 2, 3, 4]);

      final signature = await keypair1.sign(data);

      expect(await keypair2.verify(data, signature), false);
    });
  });
}
