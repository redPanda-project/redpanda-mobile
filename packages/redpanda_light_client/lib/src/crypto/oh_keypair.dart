import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// ECDSA Keypair for Outbound Handle (OH) authentication.
///
/// Uses brainpoolp256r1 curve (same as the handshake layer).
/// Generates signing keys and provides a `sign()` method
/// for OH registration and fetch request authentication.
class OHKeypair {
  final ECPublicKey publicKey;
  final ECPrivateKey privateKey;

  OHKeypair({required this.publicKey, required this.privateKey});

  /// Generates a new random ECDSA keypair on brainpoolp256r1.
  factory OHKeypair.generate() {
    final ecParams = ECDomainParameters('brainpoolp256r1');
    final keyParams = ECKeyGeneratorParameters(ecParams);

    final random = FortunaRandom();
    final secureRandom = math.Random.secure();
    final seed = Uint8List.fromList(
      List.generate(32, (_) => secureRandom.nextInt(256)),
    );
    random.seed(KeyParameter(seed));

    final generator = ECKeyGenerator();
    generator.init(ParametersWithRandom(keyParams, random));

    final pair = generator.generateKeyPair();
    return OHKeypair(publicKey: pair.publicKey, privateKey: pair.privateKey);
  }

  /// Uncompressed public key bytes (65 bytes: 0x04 + X + Y).
  Uint8List get publicKeyBytes {
    return publicKey.Q!.getEncoded(false);
  }

  /// Signs [data] using SHA256withECDSA and returns a DER-encoded signature.
  Uint8List sign(Uint8List data) {
    final signer = Signer('SHA-256/ECDSA');
    final random = FortunaRandom();
    final secureRandom = math.Random.secure();
    final seed = Uint8List.fromList(
      List.generate(32, (_) => secureRandom.nextInt(256)),
    );
    random.seed(KeyParameter(seed));
    signer.init(
      true,
      ParametersWithRandom(PrivateKeyParameter(privateKey), random),
    );
    final sig = signer.generateSignature(data) as ECSignature;
    return _derEncodeSignature(sig);
  }

  /// Verifies a DER-encoded signature against [data].
  bool verify(Uint8List data, Uint8List signature) {
    try {
      final signer = Signer('SHA-256/ECDSA');
      signer.init(false, PublicKeyParameter(publicKey));
      final ecSig = _derDecodeSignature(signature);
      return signer.verifySignature(data, ecSig);
    } catch (_) {
      return false;
    }
  }

  // --- DER encoding helpers ---

  static Uint8List _derEncodeSignature(ECSignature sig) {
    final r = _derEncodeInteger(sig.r);
    final s = _derEncodeInteger(sig.s);

    final sequence = BytesBuilder();
    sequence.addByte(0x30); // SEQUENCE
    final totalLength = r.length + s.length;
    sequence.addByte(totalLength);
    sequence.add(r);
    sequence.add(s);
    return sequence.toBytes();
  }

  static ECSignature _derDecodeSignature(Uint8List bytes) {
    var offset = 0;
    if (bytes[offset++] != 0x30) {
      throw FormatException('Invalid signature: expected SEQUENCE');
    }
    offset++; // skip length

    final r = _derDecodeInteger(bytes, offset);
    offset += (bytes[offset + 1] + 2);
    final s = _derDecodeInteger(bytes, offset);

    return ECSignature(r, s);
  }

  static Uint8List _derEncodeInteger(BigInt n) {
    var bytes = _bigIntToBytes(n, (n.bitLength + 7) >> 3);

    // Remove leading zeros
    var firstNonZero = 0;
    while (firstNonZero < bytes.length - 1 && bytes[firstNonZero] == 0) {
      firstNonZero++;
    }
    bytes = bytes.sublist(firstNonZero);

    // Prepend 0x00 if high bit set (to keep positive in DER)
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      final tmp = Uint8List(bytes.length + 1);
      tmp[0] = 0x00;
      tmp.setRange(1, tmp.length, bytes);
      bytes = tmp;
    } else if (bytes.isEmpty) {
      bytes = Uint8List.fromList([0]);
    }

    final builder = BytesBuilder();
    builder.addByte(0x02); // INTEGER
    builder.addByte(bytes.length);
    builder.add(bytes);
    return builder.toBytes();
  }

  static BigInt _derDecodeInteger(Uint8List bytes, int offset) {
    if (bytes[offset++] != 0x02) {
      throw FormatException('Invalid signature: expected INTEGER');
    }
    final len = bytes[offset++];
    var val = bytes.sublist(offset, offset + len);

    // Strip leading zero used for sign
    if (val.length > 1 && val[0] == 0x00 && (val[1] & 0x80) != 0) {
      val = val.sublist(1);
    }
    return _bytesToBigInt(val);
  }

  static Uint8List _bigIntToBytes(BigInt number, int length) {
    final hex = number.toRadixString(16).padLeft(length * 2, '0');
    final list = Uint8List(length);
    for (var i = 0; i < length; i++) {
      list[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return list;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
