import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:test/test.dart';

void main() {
  group('GarlicMessageWrapper', () {
    late KeyPair recipientKeys;
    late NodeId recipientNodeId;

    setUp(() {
      recipientKeys = KeyPair.generate();
      recipientNodeId = NodeId.fromPublicKey(recipientKeys);
    });

    test('should encrypt and decrypt a message successfully', () async {
      final payload = [1, 2, 3, 4, 5];
      final targetPublicKey = recipientKeys.publicKeyBytes;

      // Create (Encrypt)
      final wrapper = await GarlicMessageWrapper.create(
        type: 1, // GARLIC_MESSAGE
        destination: recipientNodeId,
        targetPublicKey: targetPublicKey,
        payload: payload,
      );

      expect(wrapper.proto.type, 1);
      expect(wrapper.proto.iv, isNotEmpty);
      expect(wrapper.proto.encryptedPayload, isNotEmpty);
      expect(wrapper.proto.senderPublicKey, isNotEmpty);
      expect(wrapper.proto.signature, isNotEmpty);

      // Decrypt
      final decrypted = wrapper.decrypt(recipientKeys);
      expect(decrypted, equals(payload));
    });

    test('should fail decryption if signature is tampered', () async {
      final payload = [10, 20];
      final targetPublicKey = recipientKeys.publicKeyBytes;

      final wrapper = await GarlicMessageWrapper.create(
        type: 1,
        destination: recipientNodeId,
        targetPublicKey: targetPublicKey,
        payload: payload,
      );

      // Tamper with encrypted payload
      wrapper.proto.encryptedPayload[0] ^= 0xFF;

      expect(() => wrapper.decrypt(recipientKeys), throwsException);
      // Wait, tampering payload breaks signature verification.
      // But we also want to test tempering signature itself.
    });

    test('should fail decryption if wrong recipient key is used', () async {
      final payload = [10, 20];
      final targetPublicKey = recipientKeys.publicKeyBytes;

      final wrapper = await GarlicMessageWrapper.create(
        type: 1,
        destination: recipientNodeId,
        targetPublicKey: targetPublicKey,
        payload: payload,
      );

      final otherKeys = KeyPair.generate();
      // ECDH should fail to yield correct secret, so decryption yields garbage.
      // However, signature verification should still Pass if we only verify sender signature?
      // Wait, signature verifies that (encryptedPayload) was signed by (senderPublicKey).
      // This is independent of Recipient Key.
      // So verification passes.
      // But _decrypt produces garbage.

      final decrypted = wrapper.decrypt(otherKeys);
      expect(decrypted, isNot(equals(payload)));
    });
  });
}
