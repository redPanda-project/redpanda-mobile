import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:hex/hex.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

/// Represents a secure communication channel (key model v3, MS03).
///
/// A channel is defined by:
/// - [encryptionKey]: 32-byte AES-256 key for content encryption (shared).
/// - [authPublicKey]: 32-byte Ed25519 verify key of the channel creator
///   (shared; part of the channel identity).
/// - [authPrivateKey]: 32-byte Ed25519 private seed — present **only** on the
///   device that generated the channel. It is never serialized into the QR
///   code (master spec section 10): peers joining via QR hold only the public
///   key.
/// - [peerOhDescriptor]: Optional OH descriptor of the peer (for sending
///   messages to them).
///
/// The channel id is `SHA256(encryptionKey || authPublicKey)`, so both sides
/// derive the same id from the QR material alone.
class Channel extends Equatable {
  final String label;
  final List<int> encryptionKey;
  final List<int>? authPrivateKey;
  final List<int> authPublicKey;
  final OHDescriptor? peerOhDescriptor;

  const Channel({
    required this.label,
    required this.encryptionKey,
    required this.authPublicKey,
    this.authPrivateKey,
    this.peerOhDescriptor,
  });

  /// Generates a new random channel: a 32-byte AES-256 encryption key and an
  /// Ed25519 auth keypair. The generating device keeps the private seed.
  static Future<Channel> generate(String label) async {
    final encKey = CryptoUtils.randomBytes(32);
    final authKeys = await CryptoUtils.generateSigningKeypair();

    return Channel(
      label: label,
      encryptionKey: encKey.toList(),
      authPrivateKey: authKeys.privateSeed.toList(),
      authPublicKey: authKeys.publicKey.toList(),
    );
  }

  /// Creates a copy of this channel with the given fields replaced.
  Channel copyWith({OHDescriptor? peerOhDescriptor}) {
    return Channel(
      label: label,
      encryptionKey: encryptionKey,
      authPrivateKey: authPrivateKey,
      authPublicKey: authPublicKey,
      peerOhDescriptor: peerOhDescriptor ?? this.peerOhDescriptor,
    );
  }

  /// Serializes the channel to the v3 QR JSON.
  ///
  /// Contains only `K_enc` and public material — the auth **private** key
  /// never leaves the device (master spec section 10).
  String toJson() {
    final map = <String, dynamic>{
      'l': label,
      'k_enc': HEX.encode(encryptionKey),
      'k_auth_pub': HEX.encode(authPublicKey),
    };

    if (peerOhDescriptor != null) {
      map['oh'] = peerOhDescriptor!.toJsonMap();
    }
    map['v'] = 3;

    return jsonEncode(map);
  }

  /// Deserializes a channel from its v3 QR JSON.
  ///
  /// v1/v2 codes (pre-MS03 brainpool/shared-secret key model) are rejected:
  /// they are incompatible with the v23 protocol and both peers must
  /// re-create the channel with an updated app.
  factory Channel.fromJson(String jsonStr) {
    final Map<String, dynamic> map = jsonDecode(jsonStr);
    final version = map['v'] as int?;

    if (version != 3) {
      throw FormatException(
        'Unsupported channel version: $version (this app requires v3 codes; '
        'ask the peer to update their app and share a new QR code)',
      );
    }

    final encryptionKey = HEX.decode(map['k_enc'] as String);
    if (encryptionKey.length != 32) {
      throw FormatException(
        'Invalid k_enc length: expected 32 bytes, got ${encryptionKey.length}',
      );
    }
    final authPublicKey = HEX.decode(map['k_auth_pub'] as String);
    if (authPublicKey.length != 32) {
      throw FormatException(
        'Invalid k_auth_pub length: expected 32 bytes, '
        'got ${authPublicKey.length}',
      );
    }

    OHDescriptor? ohDescriptor;
    if (map['oh'] != null) {
      ohDescriptor = OHDescriptor.fromJsonMap(
        map['oh'] as Map<String, dynamic>,
      );
    }

    return Channel(
      label: map['l'] as String,
      encryptionKey: encryptionKey,
      authPublicKey: authPublicKey,
      peerOhDescriptor: ohDescriptor,
    );
  }

  /// Channel id: `SHA256(encryptionKey || authPublicKey)` as hex.
  String get id {
    final digest = sha256.convert([...encryptionKey, ...authPublicKey]);
    return HEX.encode(digest.bytes);
  }

  @override
  List<Object?> get props => [
    label,
    encryptionKey,
    authPrivateKey,
    authPublicKey,
    peerOhDescriptor,
  ];
}
