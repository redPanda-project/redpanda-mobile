import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:hex/hex.dart';

/// Describes an Outbound Handle (OH) endpoint on a Full Node.
///
/// Contains the information needed for a peer to send messages to this OH:
/// - [serverEndpoint]: host:port of the OH-hosting Full Node
/// - [handleId]: 20-byte unique identifier for the mailbox
/// - [authPublicKey]: 65-byte uncompressed EC public key (brainpoolp256r1)
class OHDescriptor extends Equatable {
  final String serverEndpoint;
  final List<int> handleId;
  final List<int> authPublicKey;

  const OHDescriptor({
    required this.serverEndpoint,
    required this.handleId,
    required this.authPublicKey,
  });

  /// Serializes to a JSON-compatible map for embedding in QR codes.
  Map<String, dynamic> toJsonMap() {
    return {
      'ep': serverEndpoint,
      'id': HEX.encode(handleId),
      'pk': HEX.encode(authPublicKey),
    };
  }

  /// Serializes to a JSON string.
  String toJson() => jsonEncode(toJsonMap());

  /// Deserializes from a JSON-compatible map.
  factory OHDescriptor.fromJsonMap(Map<String, dynamic> map) {
    final serverEndpoint = map['ep'] as String;
    final handleId = HEX.decode(map['id'] as String);
    if (handleId.length != 20) {
      throw FormatException(
        'Invalid OHDescriptor.handleId length: expected 20 bytes, got ${handleId.length}',
      );
    }
    final authPublicKey = HEX.decode(map['pk'] as String);
    if (authPublicKey.length != 65) {
      throw FormatException(
        'Invalid OHDescriptor.authPublicKey length: expected 65 bytes, got ${authPublicKey.length}',
      );
    }
    return OHDescriptor(
      serverEndpoint: serverEndpoint,
      handleId: handleId,
      authPublicKey: authPublicKey,
    );
  }

  /// Deserializes from a JSON string.
  factory OHDescriptor.fromJson(String jsonStr) {
    return OHDescriptor.fromJsonMap(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }

  @override
  List<Object?> get props => [serverEndpoint, handleId, authPublicKey];
}
