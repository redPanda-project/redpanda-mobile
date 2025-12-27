import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/ecc/api.dart'; // For ECPoint
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/security/encryption_manager.dart';

void main() {
  group('EncryptionManager Handshake & Crypto', () {
    late KeyPair clientKeys;
    late KeyPair serverKeys;
    late EncryptionManager clientManager;
    late EncryptionManager serverManager;

    setUp(() {
      clientKeys = KeyPair.generate();
      serverKeys = KeyPair.generate();
      clientManager = EncryptionManager();
      serverManager = EncryptionManager();
    });

    test('should derive compatible secrets and exchange encrypted messages', () {
      // 1. Simluulate Handshake Randoms
      final randomClient = clientManager.generateRandomFromUs();
      final randomServer = serverManager.generateRandomFromUs();

      expect(randomClient.length, 8);
      expect(randomServer.length, 8);

      // 2. Client Side Derivation
      // Client perspective:
      // Self = ClientKeys
      // Peer = ServerKeys.publicKey
      // RandomUs = randomClient
      // RandomThem = randomServer
      clientManager.deriveAndInitialize(
        selfKeys: clientKeys.asAsymmetricKeyPair(),
        peerPublicKey: serverKeys.publicKey as ECPublicKey,
        randomFromUs: randomClient,
        randomFromThem: randomServer,
      );

      // 3. Server Side Derivation
      // Server perspective:
      // Self = ServerKeys
      // Peer = ClientKeys.publicKey
      // RandomUs = randomServer
      // RandomThem = randomClient
      // Note: EncryptionManager.deriveAndInitialize expects 'randomFromUs' to be the logic's own random.
      serverManager.deriveAndInitialize(
        selfKeys: serverKeys.asAsymmetricKeyPair(),
        peerPublicKey: clientKeys.publicKey,
        randomFromUs: randomServer,
        randomFromThem: randomClient,
      );

      expect(clientManager.isEncryptionActive, isTrue);
      expect(serverManager.isEncryptionActive, isTrue);

      // 4. Verify Encryption: Client -> Server
      final plainText = Uint8List.fromList([1, 2, 3, 4, 5, 255, 0, 128]);
      final encryptedByClient = clientManager.encrypt(plainText);
      final decryptedByServer = serverManager.decrypt(encryptedByClient);

      expect(
        decryptedByServer,
        equals(plainText),
        reason: "Server should decrypt Client's message",
      );

      // 5. Verify Encryption: Server -> Client
      final serverMsg = Uint8List.fromList([10, 20, 30]);
      final encryptedByServer = serverManager.encrypt(
        serverMsg,
      ); // Warning: EncryptionManager encrypt uses _cipherSend?

      // Wait, let's check symmetry.
      // Client:
      //   SendKey = SHA(Secret + ClientRandom + ServerRandom)
      //   RecvKey = SHA(Secret + ServerRandom + ClientRandom)
      //   IVSend = ClientRandom + ServerRandom
      //   IVRecv = ServerRandom + ClientRandom

      // Server:
      //   randomFromUs = ServerRandom
      //   randomFromThem = ClientRandom
      //   SendKey = SHA(Secret + ServerRandom + ClientRandom)  Match Client RecvKey? YES.
      //   RecvKey = SHA(Secret + ClientRandom + ServerRandom)  Match Client SendKey? YES.
      //   IVSend = ServerRandom + ClientRandom               Match Client IVRecv? YES.
      //   IVRecv = ClientRandom + ServerRandom               Match Client IVSend? YES.

      final decryptedByClient = clientManager.decrypt(encryptedByServer);
      expect(
        decryptedByClient,
        equals(serverMsg),
        reason: "Client should decrypt Server's message",
      );
    });

    test('should fail to decrypt garbage', () {
      // ... setup ...
      final randomClient = clientManager.generateRandomFromUs();
      final randomServer = serverManager.generateRandomFromUs();
      clientManager.deriveAndInitialize(
        selfKeys: clientKeys.asAsymmetricKeyPair(),
        peerPublicKey: serverKeys.publicKey as ECPublicKey,
        randomFromUs: randomClient,
        randomFromThem: randomServer,
      );

      final garbage = Uint8List.fromList([1, 2, 3]);
      // CTR mode will just decrypt it to something else, checking it doesn't crash
      expect(() => clientManager.decrypt(garbage), returnsNormally);
      final res = clientManager.decrypt(garbage);
      expect(res.length, 3);
    });
  });
}
