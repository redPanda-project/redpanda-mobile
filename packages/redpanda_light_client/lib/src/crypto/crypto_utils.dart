import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as c;

/// An Ed25519 signing keypair as raw bytes.
///
/// [privateSeed] is the 32-byte private seed (RFC 8032); [publicKey] is the
/// 32-byte verify key. The seed alone fully determines the keypair, so only
/// the seed needs to be persisted or transferred between isolates.
class Ed25519KeyPairBytes {
  final Uint8List privateSeed;
  final Uint8List publicKey;

  const Ed25519KeyPairBytes({
    required this.privateSeed,
    required this.publicKey,
  });
}

/// An X25519 key-exchange keypair as raw bytes (32-byte private scalar,
/// 32-byte public key).
class X25519KeyPairBytes {
  final Uint8List privateKey;
  final Uint8List publicKey;

  const X25519KeyPairBytes({required this.privateKey, required this.publicKey});
}

/// MS03 crypto primitives (mirrors the backend `CryptoUtils`):
/// Ed25519 signatures, X25519 key agreement, HKDF-SHA256 key derivation and
/// AES-256-GCM authenticated encryption.
///
/// All primitives come from `package:cryptography`; this class only adapts
/// them to the raw-bytes wire formats used by the RedPanda protocol.
class CryptoUtils {
  CryptoUtils._();

  /// Ed25519/X25519 keys are 32 bytes each.
  static const int keyLength = 32;

  /// Ed25519 signatures are always 64 bytes (no DER encoding).
  static const int signatureLength = 64;

  /// AES-256-GCM: 32-byte key, 12-byte nonce, 16-byte tag.
  static const int aesKeyLength = 32;
  static const int gcmNonceLength = 12;
  static const int gcmTagLength = 16;

  static final c.Ed25519 _ed25519 = c.Ed25519();
  static final c.X25519 _x25519 = c.X25519();
  static final c.AesGcm _aesGcm = c.AesGcm.with256bits();

  static final Random _random = Random.secure();

  // ---------------------------------------------------------------------
  // Ed25519
  // ---------------------------------------------------------------------

  /// Generates a new random Ed25519 signing keypair.
  static Future<Ed25519KeyPairBytes> generateSigningKeypair() {
    return signingKeypairFromSeed(randomBytes(keyLength));
  }

  /// Restores an Ed25519 keypair from its 32-byte private seed.
  static Future<Ed25519KeyPairBytes> signingKeypairFromSeed(
    List<int> seed,
  ) async {
    if (seed.length != keyLength) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'Ed25519 seed must be $keyLength bytes',
      );
    }
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return Ed25519KeyPairBytes(
      privateSeed: Uint8List.fromList(seed),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Signs [message] with the Ed25519 [privateSeed]; returns the 64-byte
  /// signature.
  static Future<Uint8List> sign(
    List<int> privateSeed,
    List<int> message,
  ) async {
    final keyPair = await _ed25519.newKeyPairFromSeed(privateSeed);
    final signature = await _ed25519.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies a 64-byte Ed25519 [signature] over [message] against the
  /// 32-byte verify key [publicKey]. Returns false for any invalid input
  /// instead of throwing.
  static Future<bool> verify(
    List<int> publicKey,
    List<int> message,
    List<int> signature,
  ) async {
    if (publicKey.length != keyLength || signature.length != signatureLength) {
      return false;
    }
    try {
      return await _ed25519.verify(
        message,
        signature: c.Signature(
          signature,
          publicKey: c.SimplePublicKey(publicKey, type: c.KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // X25519
  // ---------------------------------------------------------------------

  /// Generates a new random X25519 encryption keypair.
  static Future<X25519KeyPairBytes> generateEncryptionKeypair() {
    return encryptionKeypairFromSeed(randomBytes(keyLength));
  }

  /// Restores an X25519 keypair from its 32-byte private key.
  static Future<X25519KeyPairBytes> encryptionKeypairFromSeed(
    List<int> seed,
  ) async {
    if (seed.length != keyLength) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'X25519 private key must be $keyLength bytes',
      );
    }
    final keyPair = await _x25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return X25519KeyPairBytes(
      privateKey: Uint8List.fromList(seed),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// X25519 key agreement: returns the 32-byte shared secret between our
  /// [privateKey] and the peer's [peerPublicKey].
  static Future<Uint8List> x25519(
    List<int> privateKey,
    List<int> peerPublicKey,
  ) async {
    final keyPair = await _x25519.newKeyPairFromSeed(privateKey);
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: c.SimplePublicKey(
        peerPublicKey,
        type: c.KeyPairType.x25519,
      ),
    );
    return Uint8List.fromList(await shared.extractBytes());
  }

  // ---------------------------------------------------------------------
  // HKDF-SHA256
  // ---------------------------------------------------------------------

  /// HKDF-SHA256: derives [length] bytes from the input key material [ikm]
  /// with the given [salt] and ASCII [info] string.
  static Future<Uint8List> hkdfSha256(
    List<int> ikm,
    List<int> salt,
    String info,
    int length,
  ) async {
    final hkdf = c.Hkdf(hmac: c.Hmac.sha256(), outputLength: length);
    final key = await hkdf.deriveKey(
      secretKey: c.SecretKey(ikm),
      nonce: salt,
      info: ascii.encode(info),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  // ---------------------------------------------------------------------
  // AES-256-GCM
  // ---------------------------------------------------------------------

  /// AES-256-GCM encryption. Returns `ciphertext || 16-byte tag`.
  static Future<Uint8List> aesGcmEncrypt(
    List<int> key,
    List<int> nonce,
    List<int> plaintext,
    List<int> aad,
  ) async {
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: c.SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final out = Uint8List(box.cipherText.length + box.mac.bytes.length);
    out.setRange(0, box.cipherText.length, box.cipherText);
    out.setRange(box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  /// AES-256-GCM decryption of `ciphertext || 16-byte tag`.
  ///
  /// Throws [GcmAuthenticationException] if the tag does not verify (tampered
  /// ciphertext, wrong key/nonce or wrong AAD).
  static Future<Uint8List> aesGcmDecrypt(
    List<int> key,
    List<int> nonce,
    List<int> ciphertextWithTag,
    List<int> aad,
  ) async {
    if (ciphertextWithTag.length < gcmTagLength) {
      throw GcmAuthenticationException(
        'ciphertext too short for GCM tag: ${ciphertextWithTag.length} bytes',
      );
    }
    final cipherText = ciphertextWithTag.sublist(
      0,
      ciphertextWithTag.length - gcmTagLength,
    );
    final tag = ciphertextWithTag.sublist(
      ciphertextWithTag.length - gcmTagLength,
    );
    try {
      final plaintext = await _aesGcm.decrypt(
        c.SecretBox(cipherText, nonce: nonce, mac: c.Mac(tag)),
        secretKey: c.SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(plaintext);
    } on c.SecretBoxAuthenticationError {
      throw GcmAuthenticationException('GCM authentication failed');
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// [count] cryptographically secure random bytes.
  static Uint8List randomBytes(int count) {
    return Uint8List.fromList(
      List<int>.generate(count, (_) => _random.nextInt(256)),
    );
  }

  /// Constant-time byte comparison (no early exit on the first differing
  /// byte), for MAC/secret comparisons.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Lexicographic unsigned byte comparison (like Java's
  /// `Arrays.compareUnsigned`), used to sort verify keys for the TCP v23
  /// HKDF salt.
  static int compareUnsigned(List<int> a, List<int> b) {
    final minLength = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLength; i++) {
      final cmp = (a[i] & 0xff).compareTo(b[i] & 0xff);
      if (cmp != 0) return cmp;
    }
    return a.length.compareTo(b.length);
  }
}

/// Thrown when an AES-GCM tag fails to verify — the ciphertext was tampered
/// with or encrypted with different key/nonce/AAD.
class GcmAuthenticationException implements Exception {
  final String message;
  GcmAuthenticationException(this.message);

  @override
  String toString() => 'GcmAuthenticationException: $message';
}
