import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/garlic_message_wrapper.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:test/test.dart';

void main() {
  group('GarlicMessageWrapper v2 (AES-256-GCM + X25519 + HKDF)', () {
    late X25519KeyPairBytes recipientKeys;
    late NodeId destination;

    setUp(() async {
      recipientKeys = await CryptoUtils.generateEncryptionKeypair();
      destination = NodeId(
        Uint8List.fromList(List<int>.generate(20, (i) => i)),
      );
    });

    test('wrap produces the documented wire format', () async {
      final payload = [1, 2, 3, 4, 5];

      final bytes = await GarlicMessageWrapper.wrap(
        destination: destination,
        targetEncryptionPublicKey: recipientKeys.publicKey,
        payload: payload,
      );

      // [1 version][4 totalLen][20 dest][12 nonce][32 ephemeral][4 ctLen][ct+tag]
      expect(bytes[0], equals(GarlicMessageWrapper.version));
      final view = ByteData.sublistView(bytes);
      final totalLen = view.getUint32(1);
      expect(totalLen, equals(bytes.length - 5));
      expect(bytes.sublist(5, 25), equals(destination.bytes));
      final ctLen = view.getUint32(5 + 20 + 12 + 32);
      expect(ctLen, equals(payload.length + CryptoUtils.gcmTagLength));
      expect(bytes.length, equals(5 + 20 + 12 + 32 + 4 + ctLen));
    });

    test('wrap → unwrap roundtrip recovers the payload', () async {
      final payload = List<int>.generate(100, (i) => i % 256);

      final bytes = await GarlicMessageWrapper.wrap(
        destination: destination,
        targetEncryptionPublicKey: recipientKeys.publicKey,
        payload: payload,
      );

      final decrypted = await GarlicMessageWrapper.unwrap(
        garlicBytes: bytes,
        encryptionPrivateKey: recipientKeys.privateKey,
      );
      expect(decrypted, equals(payload));
    });

    test('a flipped ciphertext bit fails authentication', () async {
      final bytes = await GarlicMessageWrapper.wrap(
        destination: destination,
        targetEncryptionPublicKey: recipientKeys.publicKey,
        payload: [10, 20, 30],
      );

      bytes[bytes.length - 1] ^= 0xFF;

      expect(
        () => GarlicMessageWrapper.unwrap(
          garlicBytes: bytes,
          encryptionPrivateKey: recipientKeys.privateKey,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('a tampered destination fails authentication (AAD binding)',
        () async {
      final bytes = await GarlicMessageWrapper.wrap(
        destination: destination,
        targetEncryptionPublicKey: recipientKeys.publicKey,
        payload: [10, 20, 30],
      );

      // Redirecting the message to another KademliaId breaks the GCM tag.
      bytes[5] ^= 0x01;

      expect(
        () => GarlicMessageWrapper.unwrap(
          garlicBytes: bytes,
          encryptionPrivateKey: recipientKeys.privateKey,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('wrong recipient key fails authentication', () async {
      final otherKeys = await CryptoUtils.generateEncryptionKeypair();

      final bytes = await GarlicMessageWrapper.wrap(
        destination: destination,
        targetEncryptionPublicKey: recipientKeys.publicKey,
        payload: [10, 20],
      );

      expect(
        () => GarlicMessageWrapper.unwrap(
          garlicBytes: bytes,
          encryptionPrivateKey: otherKeys.privateKey,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('rejects the v1 format byte', () async {
      final bytes = await GarlicMessageWrapper.wrap(
        destination: destination,
        targetEncryptionPublicKey: recipientKeys.publicKey,
        payload: [1],
      );
      bytes[0] = 0x01;

      expect(
        () => GarlicMessageWrapper.unwrap(
          garlicBytes: bytes,
          encryptionPrivateKey: recipientKeys.privateKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects inconsistent length fields', () async {
      final bytes = await GarlicMessageWrapper.wrap(
        destination: destination,
        targetEncryptionPublicKey: recipientKeys.publicKey,
        payload: [1, 2, 3],
      );
      // Corrupt totalLen.
      bytes[4] = bytes[4] + 1;

      expect(
        () => GarlicMessageWrapper.unwrap(
          garlicBytes: bytes,
          encryptionPrivateKey: recipientKeys.privateKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
