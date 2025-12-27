import 'dart:typed_data';

// PointyCastle imports
import 'package:pointycastle/export.dart';

class EncryptionManager {
  static const int activateEncryption = 3;

  CTRStreamCipher? _cipherSend;
  CTRStreamCipher? _cipherReceive;

  bool _isEncryptionActive = false;
  bool get isEncryptionActive => _isEncryptionActive;

  /// Generate 8 random bytes for "Random From Us"
  Uint8List generateRandomFromUs() {
    final random = FortunaRandom();
    // Secure seeding would happen here in production
    // For now using time-based seed + simple counter for distinctness
    final seedSource = Uint8List(32);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < 32; i++) {
      seedSource[i] = (now >> (i % 8)) & 0xFF;
    }
    random.seed(KeyParameter(seedSource));
    return random.nextBytes(8);
  }

  /// Perform ECDH agreement and derive AES keys/IVs
  /// Returns a Map containing debug info or internal state if needed, but primarily initializes ciphers
  void deriveAndInitialize({
    required AsymmetricKeyPair<PublicKey, PrivateKey> selfKeys,
    required ECPublicKey peerPublicKey,
    required Uint8List randomFromUs,
    required Uint8List randomFromThem,
  }) {
    // 1. ECDH Shared Secret
    final agreement = ECDHBasicAgreement();
    agreement.init(selfKeys.privateKey as ECPrivateKey);
    final sharedSecretBigInt = agreement.calculateAgreement(peerPublicKey);
    final sharedSecretBytes = _bigIntToBytes(sharedSecretBigInt, 32);

    // 2. SHA256 Derivation
    final digest = SHA256Digest();

    // Send Key: SHA256(SharedSecret + RandomUs + RandomThem)
    final sendBuffer = BytesBuilder();
    sendBuffer.add(sharedSecretBytes);
    sendBuffer.add(randomFromUs);
    sendBuffer.add(randomFromThem);
    final sendKeyInput = sendBuffer.toBytes();

    final sharedSecretSend = Uint8List(32);
    digest.update(sendKeyInput, 0, sendKeyInput.length);
    digest.doFinal(sharedSecretSend, 0);

    // Receive Key: SHA256(SharedSecret + RandomThem + RandomUs)
    final receiveBuffer = BytesBuilder();
    receiveBuffer.add(sharedSecretBytes);
    receiveBuffer.add(randomFromThem);
    receiveBuffer.add(randomFromUs);
    final receiveKeyInput = receiveBuffer.toBytes();

    final sharedSecretReceive = Uint8List(32);
    digest.reset();
    digest.update(receiveKeyInput, 0, receiveKeyInput.length);
    digest.doFinal(sharedSecretReceive, 0);

    // 3. IV Derivation
    final ivSend = Uint8List(16);
    ivSend.setRange(0, 8, randomFromUs);
    ivSend.setRange(8, 16, randomFromThem);

    final ivReceive = Uint8List(16);
    ivReceive.setRange(0, 8, randomFromThem);
    ivReceive.setRange(8, 16, randomFromUs);

    // 4. Initialize Ciphers
    _initCiphers(sharedSecretSend, ivSend, sharedSecretReceive, ivReceive);
    _isEncryptionActive = true;
  }

  void _initCiphers(
    Uint8List keySend,
    Uint8List ivSend,
    Uint8List keyReceive,
    Uint8List ivReceive,
  ) {
    // Initialize Send Cipher (Encryption)
    _cipherSend = CTRStreamCipher(AESEngine());
    _cipherSend!.init(true, ParametersWithIV(KeyParameter(keySend), ivSend));

    // Initialize Receive Cipher (Decryption)
    _cipherReceive = CTRStreamCipher(AESEngine());
    _cipherReceive!.init(
      false,
      ParametersWithIV(KeyParameter(keyReceive), ivReceive),
    );
  }

  Uint8List encrypt(Uint8List data) {
    if (!_isEncryptionActive || _cipherSend == null) {
      throw StateError("Encryption not active");
    }
    return _cipherSend!.process(data);
  }

  Uint8List decrypt(Uint8List data) {
    if (!_isEncryptionActive || _cipherReceive == null) {
      throw StateError("Encryption not active");
    }
    return _cipherReceive!.process(data);
  }

  Uint8List _bigIntToBytes(BigInt number, int length) {
    var bytes = number.toRadixString(16).padLeft(length * 2, '0');
    var list = Uint8List(length);
    for (var i = 0; i < length; i++) {
      list[i] = int.parse(bytes.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return list;
  }
}
