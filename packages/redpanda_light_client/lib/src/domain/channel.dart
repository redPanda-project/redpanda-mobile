import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:pointycastle/export.dart';
import 'package:hex/hex.dart';

import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

/// Represents a secure communication channel.
///
/// A channel is defined by a shared set of keys:
/// - [encryptionKey]: AES-256 key for content encryption.
/// - [authenticationKey]: Key for signing/verification.
/// - [peerOhDescriptor]: Optional OH descriptor of the peer (for sending messages to them).
class Channel extends Equatable {
  final String label;
  final List<int> encryptionKey;
  final List<int> authenticationKey;
  final OHDescriptor? peerOhDescriptor;

  const Channel({
    required this.label,
    required this.encryptionKey,
    required this.authenticationKey,
    this.peerOhDescriptor,
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

  /// Creates a copy of this channel with the given fields replaced.
  Channel copyWith({OHDescriptor? peerOhDescriptor}) {
    return Channel(
      label: label,
      encryptionKey: encryptionKey,
      authenticationKey: authenticationKey,
      peerOhDescriptor: peerOhDescriptor ?? this.peerOhDescriptor,
    );
  }

  /// Serializes the channel to a JSON string, suitable for QR codes.
  /// Produces v2 format if [peerOhDescriptor] is present, v1 otherwise.
  String toJson() {
    final map = <String, dynamic>{
      'l': label,
      'k_enc': HEX.encode(encryptionKey),
      'k_auth': HEX.encode(authenticationKey),
    };

    if (peerOhDescriptor != null) {
      map['oh'] = peerOhDescriptor!.toJsonMap();
      map['v'] = 2;
    } else {
      map['v'] = 1;
    }

    return jsonEncode(map);
  }

  /// Deserializes a channel from a JSON string.
  /// Supports both v1 and v2 formats.
  factory Channel.fromJson(String jsonStr) {
    final Map<String, dynamic> map = jsonDecode(jsonStr);
    final version = map['v'] as int?;

    if (version != 1 && version != 2) {
      throw FormatException('Unsupported channel version: $version');
    }

    OHDescriptor? ohDescriptor;
    if (version == 2 && map['oh'] != null) {
      ohDescriptor = OHDescriptor.fromJsonMap(
        map['oh'] as Map<String, dynamic>,
      );
    }

    return Channel(
      label: map['l'] as String,
      encryptionKey: HEX.decode(map['k_enc'] as String),
      authenticationKey: HEX.decode(map['k_auth'] as String),
      peerOhDescriptor: ohDescriptor,
    );
  }

  String get id {
    final digest = sha256.convert([...encryptionKey, ...authenticationKey]);
    return HEX.encode(digest.bytes);
  }

  @override
  List<Object?> get props => [
    label,
    encryptionKey,
    authenticationKey,
    peerOhDescriptor,
  ];
}
