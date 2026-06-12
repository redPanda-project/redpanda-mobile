import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// Garlic message v2 (MS03): AES-256-GCM + ephemeral X25519 + HKDF-SHA256.
///
/// Wire format (identical to the backend `GarlicMessage`):
///
/// ```
/// [1  version/GMType = 0x02]
/// [4  totalLen (bytes after this field), big-endian]
/// [20 destination KademliaId]
/// [12 nonce (random)]
/// [32 ephemeral X25519 public key]
/// [4  ciphertextLen, big-endian]
/// [N  ciphertext + 16-byte GCM tag]
/// ```
///
/// Key derivation: `key = HKDF-SHA256(ikm = X25519(ephemeralPriv,
/// targetEncPub), salt = ephemeralPub, info = "garlic-v2")`. The AAD is the
/// 20-byte destination KademliaId, binding the ciphertext to its intended
/// recipient. There is no separate signature — the GCM tag authenticates the
/// message; tampered bytes fail with [GcmAuthenticationException].
class GarlicMessageWrapper {
  GarlicMessageWrapper._();

  /// The GMType byte doubles as the format version (Garlic v2). The v1
  /// format (brainpool ECDH + AES-CTR + ECDSA) is no longer supported.
  static const int version = 0x02;

  static const String hkdfInfo = 'garlic-v2';

  static const int _destinationLength = 20;
  static const int _headerLength =
      1 + // version
      4 + // totalLen
      _destinationLength +
      CryptoUtils.gcmNonceLength +
      CryptoUtils.keyLength + // ephemeral public key
      4; // ciphertextLen

  /// Encrypts [payload] for the node owning [targetEncryptionPublicKey]
  /// (32-byte X25519 key), addressed to [destination].
  static Future<Uint8List> wrap({
    required NodeId destination,
    required List<int> targetEncryptionPublicKey,
    required List<int> payload,
  }) async {
    final ephemeral = await CryptoUtils.generateEncryptionKeypair();
    final shared = await CryptoUtils.x25519(
      ephemeral.privateKey,
      targetEncryptionPublicKey,
    );
    final key = await CryptoUtils.hkdfSha256(
      shared,
      ephemeral.publicKey,
      hkdfInfo,
      CryptoUtils.aesKeyLength,
    );

    final nonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
    final ciphertext = await CryptoUtils.aesGcmEncrypt(
      key,
      nonce,
      payload,
      destination.bytes,
    );

    final totalLength = _headerLength - 1 - 4 + ciphertext.length;
    final out = BytesBuilder();
    out.addByte(version);
    out.add(_uint32be(totalLength));
    out.add(destination.bytes);
    out.add(nonce);
    out.add(ephemeral.publicKey);
    out.add(_uint32be(ciphertext.length));
    out.add(ciphertext);
    return out.toBytes();
  }

  /// Parses and decrypts a Garlic v2 message with our X25519
  /// [encryptionPrivateKey]. Returns the decrypted payload.
  ///
  /// Throws [FormatException] on malformed bytes or an unsupported version
  /// and [GcmAuthenticationException] when the GCM tag does not verify
  /// (tampered message, wrong recipient key or wrong destination AAD).
  static Future<Uint8List> unwrap({
    required List<int> garlicBytes,
    required List<int> encryptionPrivateKey,
  }) async {
    final data = Uint8List.fromList(garlicBytes);
    if (data.length < _headerLength + CryptoUtils.gcmTagLength) {
      throw FormatException('garlic message too short: ${data.length} bytes');
    }
    final view = ByteData.sublistView(data);

    var offset = 0;
    final versionByte = data[offset];
    offset += 1;
    if (versionByte != version) {
      throw FormatException(
        'unsupported garlic message version: '
        '0x${versionByte.toRadixString(16)}',
      );
    }

    final totalLength = view.getUint32(offset);
    offset += 4;
    if (totalLength != data.length - offset) {
      throw FormatException(
        'garlic message length mismatch: header says $totalLength, '
        'got ${data.length - offset}',
      );
    }

    final destination = Uint8List.sublistView(
      data,
      offset,
      offset + _destinationLength,
    );
    offset += _destinationLength;

    final nonce = Uint8List.sublistView(
      data,
      offset,
      offset + CryptoUtils.gcmNonceLength,
    );
    offset += CryptoUtils.gcmNonceLength;

    final ephemeralPublicKey = Uint8List.sublistView(
      data,
      offset,
      offset + CryptoUtils.keyLength,
    );
    offset += CryptoUtils.keyLength;

    final ciphertextLength = view.getUint32(offset);
    offset += 4;
    if (ciphertextLength < CryptoUtils.gcmTagLength ||
        ciphertextLength != data.length - offset) {
      throw FormatException(
        'invalid garlic message ciphertext length: $ciphertextLength',
      );
    }
    final ciphertext = Uint8List.sublistView(data, offset);

    final shared = await CryptoUtils.x25519(
      encryptionPrivateKey,
      ephemeralPublicKey,
    );
    final key = await CryptoUtils.hkdfSha256(
      shared,
      ephemeralPublicKey,
      hkdfInfo,
      CryptoUtils.aesKeyLength,
    );

    return CryptoUtils.aesGcmDecrypt(key, nonce, ciphertext, destination);
  }

  static Uint8List _uint32be(int value) {
    final data = ByteData(4)..setUint32(0, value);
    return data.buffer.asUint8List();
  }
}
