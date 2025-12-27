import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';

/// Represents a 256-bit identifier used in the RedPanda Kademlia DHT.
/// KademliaId in Java implementation.
class NodeId extends Equatable {
  static const int length = 20; // 160 bits = 20 bytes (Kademlia standard)
  final Uint8List bytes;

  const NodeId(this.bytes) : assert(bytes.length == length);

  factory NodeId.fromHex(String hexString) {
    return NodeId(Uint8List.fromList(HEX.decode(hexString)));
  }

  factory NodeId.random() {
    // Basic random implementation (not secure, but fine for ID gen)
    // For crypto keys we will use SecureRandom
    final secureRandom = SecureRandom("Fortuna")
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i))));

    return NodeId(secureRandom.nextBytes(length));
  }

  factory NodeId.fromPublicKey(KeyPair keys) {
    final pubKeyBytes = keys.publicKeyBytes;
    final digest = SHA256Digest();
    // KademliaId is computed from SINGLE SHA-256 of the uncompressed public key (65 bytes)
    final hash = digest.process(pubKeyBytes);

    return NodeId(hash.sublist(0, length));
  }

  String toHex() => HEX.encode(bytes);

  @override
  List<Object> get props => [bytes];

  @override
  String toString() => toHex();

  // TODO: Add distance calculation (XOR) if needed for routing logic
}
