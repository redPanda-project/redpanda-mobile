import 'dart:typed_data';
import 'package:bs58/bs58.dart';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';

/// A 160-bit identifier used in the RedPanda Kademlia DHT.
/// KademliaId in the Java implementation.
///
/// Since MS03 the id is derived from the **32-byte Ed25519 verify key**
/// (master spec Decision 2): the first 20 bytes of `SHA-256(verifyKey)`.
class NodeId extends Equatable {
  static const int length = 20; // 160 bits = 20 bytes (Kademlia standard)
  final Uint8List bytes;

  const NodeId(this.bytes) : assert(bytes.length == length);

  factory NodeId.fromHex(String hexString) {
    return NodeId(Uint8List.fromList(HEX.decode(hexString)));
  }

  factory NodeId.random() {
    return NodeId(CryptoUtils.randomBytes(length));
  }

  /// Derives the id from our own identity keypair.
  factory NodeId.fromPublicKey(KeyPair keys) {
    return NodeId.fromVerifyKey(keys.verifyKeyBytes);
  }

  /// Derives the id from a 32-byte Ed25519 verify key.
  factory NodeId.fromVerifyKey(List<int> verifyKey) {
    final hash = sha256.convert(verifyKey).bytes;
    return NodeId(Uint8List.fromList(hash.sublist(0, length)));
  }

  /// Derives the id from a 64-byte public export
  /// `[32 verifyKey][32 encryptionPubKey]` — only the verify key is hashed.
  factory NodeId.fromPublicKeyBytes(Uint8List publicExport) {
    if (publicExport.length != KeyPair.publicKeyLength) {
      throw ArgumentError.value(
        publicExport.length,
        'publicExport',
        'expected ${KeyPair.publicKeyLength}-byte public export',
      );
    }
    return NodeId.fromVerifyKey(publicExport.sublist(0, 32));
  }

  String toHex() => HEX.encode(bytes);

  String toBase58() => base58.encode(bytes);

  @override
  List<Object> get props => [bytes];

  @override
  String toString() => toHex();
}
