import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart'; // generated protobuf
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

class GarlicMessageWrapper {
  final GarlicMessage proto;

  GarlicMessageWrapper(this.proto);

  /// Creates a new GarlicMessage by encrypting the payload for the target.
  ///
  /// [type] - GMType ID.
  /// [destination] - The KademliaId of the destination.
  /// [targetPublicKey] - The public key of the destination peer (required for encryption).
  /// [payload] - The content to encrypt (e.g. serialized nested messages).
  static Future<GarlicMessageWrapper> create({
    required int type,
    required NodeId destination, // Using NodeId for KademliaId
    required List<int> targetPublicKey,
    required List<int> payload,
  }) async {
    // 1. Generate Ephemeral KeyPair for this message (EncryptionNodeId)
    final encryptionKeyPair = KeyPair.generate();

    // 2. Generate Random IV (16 bytes)
    final iv = _generateRandomBytes(16);

    // 3. Perform ECDH (Our Private + Their Public) -> Shared Secret
    final sharedSecret = _calculateSharedSecret(
      encryptionKeyPair,
      Uint8List.fromList(targetPublicKey),
    );

    // 4. Encrypt Payload (AES/CTR/NoPadding)
    final encryptedPayload = _encrypt(
      Uint8List.fromList(payload),
      sharedSecret,
      iv,
    );

    // 5. Sign the Encrypted Payload (Sign with Ephemeral Private Key)
    // Note: Java implementation signs the *encrypted* bytes.
    final signature = _sign(encryptedPayload, encryptionKeyPair);

    // 6. Build Protobuf
    final proto = GarlicMessage()
      ..type = type
      ..destination = (KademliaIdProto()..keyBytes = destination.bytes)
      ..iv = iv
      ..senderPublicKey = encryptionKeyPair.publicKeyBytes
      ..encryptedPayload = encryptedPayload
      ..signature = signature;

    return GarlicMessageWrapper(proto);
  }

  /// Decrypts the payload of this GarlicMessage using the recipient's private key.
  List<int> decrypt(KeyPair recipientKeyPair) {
    // 1. Verify Signature (Optional but recommended)
    if (!_verifySignature()) {
      throw Exception('GarlicMessage signature verification failed.');
    }

    // 2. Perform ECDH (Our Private + Their Public from message) -> Shared Secret
    final senderPubBytes = Uint8List.fromList(proto.senderPublicKey);
    final sharedSecret = _calculateSharedSecret(
      recipientKeyPair,
      senderPubBytes,
    );

    // 3. Decrypt
    final iv = Uint8List.fromList(proto.iv);
    final encryptedData = Uint8List.fromList(proto.encryptedPayload);

    return _decrypt(encryptedData, sharedSecret, iv);
  }

  bool _verifySignature() {
    final signatureBytes = Uint8List.fromList(proto.signature);
    final data = Uint8List.fromList(proto.encryptedPayload);
    final pubKeyBytes = Uint8List.fromList(proto.senderPublicKey);

    try {
      final ecParams = ECDomainParameters('brainpoolp256r1');
      final q = ecParams.curve.decodePoint(pubKeyBytes);
      final publicKey = ECPublicKey(q, ecParams);

      final signer = Signer('SHA-256/ECDSA');
      signer.init(false, PublicKeyParameter(publicKey));

      final ecSig = _decodeSignature(signatureBytes);

      return signer.verifySignature(data, ecSig);
    } catch (e) {
      print("Signature verification error: $e");
      return false;
    }
  }

  // --- Helpers ---

  static Uint8List _generateRandomBytes(int length) {
    final random = FortunaRandom();
    final seed = Uint8List.fromList(
      List.generate(32, (i) => i),
    ); // TODO: Secure seed
    // Note: In real app use proper platform entropy.
    random.seed(KeyParameter(seed));
    return random.nextBytes(length);
  }

  static Uint8List _calculateSharedSecret(
    KeyPair selfKeyPair,
    Uint8List peerPublicKeyBytes,
  ) {
    final ecParams = ECDomainParameters('brainpoolp256r1');
    final q = ecParams.curve.decodePoint(peerPublicKeyBytes);
    final peerKey = ECPublicKey(q, ecParams);

    final agreement = ECDHBasicAgreement();
    agreement.init(selfKeyPair.privateKey!);

    final sharedSecretBigInt = agreement.calculateAgreement(peerKey);
    return _bigIntToBytes(sharedSecretBigInt, 32); // 32 bytes for 256-bit curve
  }

  static Uint8List _encrypt(Uint8List data, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine());
    cipher.init(true, ParametersWithIV(KeyParameter(key), iv));
    return cipher.process(data);
  }

  static Uint8List _decrypt(Uint8List data, Uint8List key, Uint8List iv) {
    final cipher = CTRStreamCipher(AESEngine());
    cipher.init(false, ParametersWithIV(KeyParameter(key), iv));
    return cipher.process(data);
  }

  static Uint8List _bigIntToBytes(BigInt number, int length) {
    var bytes = number.toRadixString(16).padLeft(length * 2, '0');
    var list = Uint8List(length);
    for (var i = 0; i < length; i++) {
      list[i] = int.parse(bytes.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return list;
  }

  static Uint8List _sign(Uint8List data, KeyPair keyPair) {
    final signer = Signer('SHA-256/ECDSA');
    final random = FortunaRandom();
    random.seed(KeyParameter(_generateRandomBytes(32)));
    signer.init(
      true,
      ParametersWithRandom(PrivateKeyParameter(keyPair.privateKey!), random),
    );
    final sig = signer.generateSignature(data) as ECSignature;
    return _encodeSignature(sig);
  }

  static Uint8List _encodeSignature(ECSignature sig) {
    final r = _derEncodeInteger(sig.r);
    final s = _derEncodeInteger(sig.s);

    final sequence = BytesBuilder();
    sequence.addByte(0x30); // SEQUENCE

    // Calculate total length of r and s DER encodings
    final totalLength = r.length + s.length;
    if (totalLength < 128) {
      sequence.addByte(totalLength); // Short form length
    } else {
      // Long form length (not typically needed for ECDSA signatures, but good practice)
      final lengthBytes = _bigIntToBytes(
        BigInt.from(totalLength),
        (totalLength.bitLength + 7) >> 3,
      );
      sequence.addByte(0x80 | lengthBytes.length);
      sequence.add(lengthBytes);
    }

    sequence.add(r);
    sequence.add(s);
    return sequence.toBytes();
  }

  static ECSignature _decodeSignature(Uint8List bytes) {
    // Minimal DER decoder
    var offset = 0;
    if (bytes[offset++] != 0x30) {
      throw Exception('Invalid signature: expected SEQUENCE');
    }

    var lenByte = bytes[offset++];
    int totalLen;
    if (lenByte & 0x80 != 0) {
      // Long form length
      final numLenBytes = lenByte & 0x7F;
      if (numLenBytes == 0 || numLenBytes > 4) {
        throw Exception(
          'Invalid signature: unsupported length encoding',
        ); // Max 4 bytes for length
      }
      totalLen = 0;
      for (var i = 0; i < numLenBytes; i++) {
        totalLen = (totalLen << 8) | bytes[offset++];
      }
    } else {
      // Short form length
      totalLen = lenByte;
    }

    // Ensure the parsed length matches the remaining bytes
    if (totalLen != bytes.length - offset) {
      throw Exception('Invalid signature: length mismatch');
    }

    final r = _derDecodeInteger(bytes, offset);
    offset += (bytes[offset + 1] + 2); // tag + len + value

    final s = _derDecodeInteger(bytes, offset);

    return ECSignature(r, s);
  }

  static Uint8List _derEncodeInteger(BigInt n) {
    var bytes = _bigIntToBytes(n, (n.bitLength + 7) >> 3);

    // Remove leading zeros, unless the number is 0 itself
    var firstNonZero = 0;
    while (firstNonZero < bytes.length - 1 && bytes[firstNonZero] == 0) {
      firstNonZero++;
    }
    bytes = bytes.sublist(firstNonZero);

    // If first bit is 1, prepend 0x00 to make it positive in two's complement
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      final tmp = Uint8List(bytes.length + 1);
      tmp[0] = 0x00;
      tmp.setRange(1, tmp.length, bytes);
      bytes = tmp;
    } else if (bytes.isEmpty) {
      bytes = Uint8List.fromList([0]); // Represent 0 as a single 0x00 byte
    }

    final builder = BytesBuilder();
    builder.addByte(0x02); // INTEGER

    // Add length byte
    if (bytes.length < 128) {
      builder.addByte(bytes.length);
    } else {
      // Long form length
      final lengthBytes = _bigIntToBytes(
        BigInt.from(bytes.length),
        (bytes.length.bitLength + 7) >> 3,
      );
      builder.addByte(0x80 | lengthBytes.length);
      builder.add(lengthBytes);
    }

    builder.add(bytes);
    return builder.toBytes();
  }

  static BigInt _derDecodeInteger(Uint8List bytes, int offset) {
    if (bytes[offset++] != 0x02) {
      throw Exception('Invalid signature: expected INTEGER');
    }

    var lenByte = bytes[offset++];
    int len;
    if (lenByte & 0x80 != 0) {
      // Long form length
      final numLenBytes = lenByte & 0x7F;
      if (numLenBytes == 0 || numLenBytes > 4) {
        throw Exception('Invalid signature: unsupported length encoding');
      }
      len = 0;
      for (var i = 0; i < numLenBytes; i++) {
        len = (len << 8) | bytes[offset++];
      }
    } else {
      // Short form length
      len = lenByte;
    }

    var valConfig = bytes.sublist(offset, offset + len);

    // Handle potential leading zero for positive numbers (DER canonical form)
    if (valConfig.length > 1 &&
        valConfig[0] == 0x00 &&
        (valConfig[1] & 0x80) == 0) {
      valConfig = valConfig.sublist(1);
    } else if (valConfig.length == 1 && valConfig[0] == 0x00) {
      // Special case for BigInt.zero
      return BigInt.zero;
    }

    return _bytesToBigInt(valConfig);
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
