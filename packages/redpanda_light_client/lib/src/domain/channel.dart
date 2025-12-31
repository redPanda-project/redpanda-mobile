import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:pointycastle/export.dart';
import 'package:hex/hex.dart';

/// Represents a secure communication channel.
///
/// A channel is defined by a shared set of keys:
/// - [encryptionKey]: AES-256 key for content encryption.
/// - [authenticationKey]: Key for signing/verification (Implementation details TBD, currently treated as a shared secret or private key).
class Channel extends Equatable {
  final String label;
  final List<int> encryptionKey;
  final List<int>
  authenticationKey; // TODO: Decide if this is a shared private key or if we need a keypair.

  const Channel({
    required this.label,
    required this.encryptionKey,
    required this.authenticationKey,
  });

  /// Generates a new random channel.
  factory Channel.generate(String label) {
    final platformRandom = Random.secure();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => platformRandom.nextInt(256)),
    );

    final secureRandom = SecureRandom('Fortuna')..seed(KeyParameter(seed));

    // Generate 32 bytes (256 bits) for encryption key
    final encKey = secureRandom.nextBytes(32);

    // Generate 32 bytes for auth key (simplified for now)
    final authKey = secureRandom.nextBytes(32);

    return Channel(
      label: label,
      encryptionKey: encKey.toList(),
      authenticationKey: authKey.toList(),
    );
  }

  /// Serializes the channel to a JSON string, suitable for QR codes.
  String toJson() {
    return jsonEncode({
      'l': label,
      'k_enc': HEX.encode(encryptionKey),
      'k_auth': HEX.encode(authenticationKey),
      'v': 1, // Version
    });
  }

  /// Deserializes a channel from a JSON string.
  factory Channel.fromJson(String jsonStr) {
    final Map<String, dynamic> map = jsonDecode(jsonStr);

    if (map['v'] != 1) {
      throw FormatException('Unsupported channel version: ${map['v']}');
    }

    return Channel(
      label: map['l'] as String,
      encryptionKey: HEX.decode(map['k_enc'] as String),
      authenticationKey: HEX.decode(map['k_auth'] as String),
    );
  }

  // TODO: Add methods for deriving Channel ID
  String get id {
    final digest = sha256.convert([...encryptionKey, ...authenticationKey]);
    return HEX.encode(digest.bytes);
  }

  @override
  List<Object?> get props => [label, encryptionKey, authenticationKey];
}
