import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';

/// The node identity of this light client (MS03): a dual keypair with strict
/// key separation, mirroring the backend `NodeId`.
///
/// - **Signing**: Ed25519 — identity (KademliaId is derived from the verify
///   key) and signatures.
/// - **Encryption**: X25519 — Diffie-Hellman key exchange (TCP v23 session
///   keys, garlic messages).
///
/// Public export (sent as `SEND_PUBLIC_KEY` payload):
/// `[32 verifyKey][32 encryptionPubKey]` = 64 bytes.
class KeyPair {
  /// Public export length: 32-byte Ed25519 verify key + 32-byte X25519 key.
  static const int publicKeyLength = 64;

  final Ed25519KeyPairBytes signing;
  final X25519KeyPairBytes encryption;

  KeyPair({required this.signing, required this.encryption});

  /// Generates a new random identity.
  ///
  /// No HashCash grinding: the server only enforces the proof-of-work for
  /// full-node identities, not for light clients, and the light-client
  /// identity is ephemeral (regenerated per app run).
  static Future<KeyPair> generate() async {
    final signing = await CryptoUtils.generateSigningKeypair();
    final encryption = await CryptoUtils.generateEncryptionKeypair();
    return KeyPair(signing: signing, encryption: encryption);
  }

  /// The 32-byte Ed25519 verify key (identity).
  Uint8List get verifyKeyBytes => signing.publicKey;

  /// The 64-byte public export `[verifyKey][encryptionPubKey]`.
  Uint8List get publicKeyBytes {
    final out = Uint8List(publicKeyLength);
    out.setRange(0, 32, signing.publicKey);
    out.setRange(32, 64, encryption.publicKey);
    return out;
  }
}
