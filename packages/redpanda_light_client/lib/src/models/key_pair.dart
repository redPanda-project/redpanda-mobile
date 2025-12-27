import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/api.dart'; // For KeyParameter/ParametersWithRandom

/// Represents an Ed25519 or X25519 key pair.
/// The RedPanda protocol primarily uses Ed25519 for identity and signing,
/// and converts to X25519 for encryption (or uses separate keys, checking docs).
class KeyPair {
  final ECPublicKey publicKey;
  final ECPrivateKey? privateKey;

  KeyPair({required this.publicKey, this.privateKey});

  factory KeyPair.generate() {
    final ecParams = ECDomainParameters('brainpoolp256r1');
    final keyParams = ECKeyGeneratorParameters(ecParams);

    final random = FortunaRandom();
    // Seed the random generator (INSECURE: using fixed seed for dev/test consistency for now)
    // In prod, use platform secure random source
    final seed = Uint8List.fromList(List.generate(32, (i) => i));
    random.seed(KeyParameter(seed));

    final generator = ECKeyGenerator();
    generator.init(ParametersWithRandom(keyParams, random));

    final pair = generator.generateKeyPair();
    return KeyPair(
      publicKey: pair.publicKey as ECPublicKey,
      privateKey: pair.privateKey as ECPrivateKey,
    );
  }

  Uint8List get publicKeyBytes {
    return publicKey.Q!.getEncoded(
      false,
    ); // false = uncompressed (0x04 + X + Y)
  }

  AsymmetricKeyPair<PublicKey, PrivateKey> asAsymmetricKeyPair() {
    return AsymmetricKeyPair(publicKey, privateKey!);
  }
}
