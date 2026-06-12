import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';

/// Ed25519 keypair for Outbound Handle (OH) authentication (MS03).
///
/// Signs OH registration, fetch and ack-fetch requests. The signature covers
/// the versioned signing bytes `[0x02 | CMD_BYTE | fields | timestamp |
/// nonce]` (see [signingVersion]); the server identifies the algorithm by the
/// 32-byte `oh_auth_public_key` (Ed25519 verify key).
class OHKeypair {
  /// Signing-bytes version byte for Ed25519 (MS03, master spec section 8).
  /// Prefixes every signed command body.
  static const int signingVersion = 0x02;

  final Ed25519KeyPairBytes _keys;

  OHKeypair._(this._keys);

  /// Generates a new random Ed25519 keypair.
  static Future<OHKeypair> generate() async {
    return OHKeypair._(await CryptoUtils.generateSigningKeypair());
  }

  /// Restores a keypair from its 32-byte private seed (see
  /// [privateKeyBytes]).
  static Future<OHKeypair> fromPrivateKeyBytes(Uint8List bytes) async {
    return OHKeypair._(await CryptoUtils.signingKeypairFromSeed(bytes));
  }

  /// The 32-byte Ed25519 verify key — sent as `oh_auth_public_key`.
  Uint8List get publicKeyBytes => _keys.publicKey;

  /// The 32-byte Ed25519 private seed, for persistence and isolate
  /// transfer. Restore with [OHKeypair.fromPrivateKeyBytes].
  Uint8List get privateKeyBytes => _keys.privateSeed;

  /// Signs the versioned bytes `[0x02 | signingBytes]` with Ed25519 and
  /// returns the 64-byte signature. [signingBytes] is the unversioned
  /// command body `[CMD_BYTE | fields | timestamp | nonce]`.
  Future<Uint8List> sign(Uint8List signingBytes) {
    final versioned = Uint8List(1 + signingBytes.length);
    versioned[0] = signingVersion;
    versioned.setRange(1, versioned.length, signingBytes);
    return CryptoUtils.sign(_keys.privateSeed, versioned);
  }

  /// Verifies a 64-byte signature over the versioned bytes
  /// `[0x02 | signingBytes]`.
  Future<bool> verify(Uint8List signingBytes, Uint8List signature) {
    final versioned = Uint8List(1 + signingBytes.length);
    versioned[0] = signingVersion;
    versioned.setRange(1, versioned.length, signingBytes);
    return CryptoUtils.verify(_keys.publicKey, versioned, signature);
  }
}
