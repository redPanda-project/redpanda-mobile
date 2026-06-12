import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';

/// A test hop: X25519 keypair + KademliaId, the relay-side view.
class TestHop {
  final Uint8List nodeId;
  final X25519KeyPairBytes keys;
  TestHop(this.nodeId, this.keys);

  static Future<TestHop> generate(int seedByte) async => TestHop(
    Uint8List.fromList(List<int>.filled(20, seedByte)),
    await CryptoUtils.generateEncryptionKeypair(),
  );

  GarlicHop get asGarlicHop =>
      GarlicHop(nodeId: nodeId, encryptionPublicKey: keys.publicKey);
}

/// Parsed Flaschenpost v2 packet (relay view, format lock for the wire
/// layout of the backend `FlaschenpostV2.parse`).
class ParsedPacket {
  final int version;
  final Uint8List packetId;
  final Uint8List nextHop;
  final Uint8List nonce;
  final Uint8List ephemeralPub;
  final int ciphertextLength;
  final Uint8List ciphertext;

  ParsedPacket._({
    required this.version,
    required this.packetId,
    required this.nextHop,
    required this.nonce,
    required this.ephemeralPub,
    required this.ciphertextLength,
    required this.ciphertext,
  });

  /// Strict parse along the byte offsets of the master-spec Decision 1:
  /// [1 version][4 packet_id][20 next_hop][12 nonce][32 eph_pub][4 ct_len]
  /// [ct+tag][padding] — total exactly 2048 bytes.
  factory ParsedPacket.parse(Uint8List packet) {
    expect(packet.length, GarlicBuilder.packetSize);
    final view = ByteData.sublistView(packet);
    final ctLen = view.getUint32(69);
    expect(
      ctLen,
      inInclusiveRange(
        GarlicBuilder.minCiphertextLength,
        GarlicBuilder.maxCiphertextLength,
      ),
    );
    return ParsedPacket._(
      version: packet[0],
      packetId: Uint8List.sublistView(packet, 1, 5),
      nextHop: Uint8List.sublistView(packet, 5, 25),
      nonce: Uint8List.sublistView(packet, 25, 37),
      ephemeralPub: Uint8List.sublistView(packet, 37, 69),
      ciphertextLength: ctLen,
      ciphertext: Uint8List.sublistView(packet, 73, 73 + ctLen),
    );
  }

  /// Relay-side layer decryption (mirror of `FlaschenpostV2.decryptLayer`):
  /// key = HKDF-SHA256(X25519(hopPriv, eph_pub), salt=eph_pub,
  /// info="flaschenpost-v2"), AAD = next_hop.
  Future<Uint8List> decryptLayer(List<int> hopPrivateKey) async {
    final shared = await CryptoUtils.x25519(hopPrivateKey, ephemeralPub);
    final key = await CryptoUtils.hkdfSha256(
      shared,
      ephemeralPub,
      GarlicBuilder.hkdfInfo,
      CryptoUtils.aesKeyLength,
    );
    return CryptoUtils.aesGcmDecrypt(key, nonce, ciphertext, nextHop);
  }
}
