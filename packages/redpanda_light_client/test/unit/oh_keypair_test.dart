import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';

void main() {
  group('OHKeypair', () {
    test('should generate a valid keypair', () {
      final keypair = OHKeypair.generate();

      expect(keypair.publicKey, isNotNull);
      expect(keypair.privateKey, isNotNull);
    });

    test('should export 65-byte uncompressed public key', () {
      final keypair = OHKeypair.generate();
      final pubBytes = keypair.publicKeyBytes;

      expect(pubBytes.length, 65);
      expect(pubBytes[0], 0x04); // Uncompressed format marker
    });

    test('should generate different keys each time', () {
      final a = OHKeypair.generate();
      final b = OHKeypair.generate();

      expect(a.publicKeyBytes, isNot(equals(b.publicKeyBytes)));
    });

    test('should sign and verify data', () {
      final keypair = OHKeypair.generate();
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final signature = keypair.sign(data);
      expect(signature.isNotEmpty, true);

      final isValid = keypair.verify(data, signature);
      expect(isValid, true);
    });

    test('should fail verification with tampered data', () {
      final keypair = OHKeypair.generate();
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final tampered = Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]);

      final signature = keypair.sign(data);

      final isValid = keypair.verify(tampered, signature);
      expect(isValid, false);
    });

    test('should fail verification with different key', () {
      final keypair1 = OHKeypair.generate();
      final keypair2 = OHKeypair.generate();
      final data = Uint8List.fromList([1, 2, 3, 4]);

      final signature = keypair1.sign(data);

      final isValid = keypair2.verify(data, signature);
      expect(isValid, false);
    });
  });
}
