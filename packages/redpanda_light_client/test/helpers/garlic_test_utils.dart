import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/return_path.dart';

/// The innermost deposit of a peeled garlic packet: the target OH mailbox id
/// and the delivered payload.
class GarlicDeposit {
  final Uint8List ohId;
  final Uint8List payload;
  final int hopCount;
  const GarlicDeposit(this.ohId, this.payload, this.hopCount);
}

/// Peels every forward layer of a submitted 2048-byte garlic [packet] with the
/// known [hops] (relay-side view) and returns the innermost deposit — handling
/// CMD_DELIVER, CMD_DELIVER_TAGGED and CMD_DELIVER_ACKED. Returns null when the
/// innermost layer is a CMD_RECORD_STORE / CMD_RECORD_LOOKUP (a T44 rendezvous
/// packet, not a mailbox deposit) so a mock can simply ignore those. Fails if a
/// layer is addressed to an unknown hop. Mirrors what the backend relays do end
/// to end, so a scripted single-node mock can extract the deposit a client sent
/// over garlic (T45: sends are garlic-only now).
Future<GarlicDeposit?> peelGarlicDeposit(
  Uint8List packet,
  List<TestHop> hops,
) async {
  var hopCount = 0;
  while (true) {
    final parsed = ParsedPacket.parse(packet);
    final hop = hops.firstWhere(
      (h) => _hex(h.nodeId) == _hex(parsed.nextHop),
      orElse: () => fail('garlic next_hop is not one of the known relays'),
    );
    hopCount++;
    final plaintext = await parsed.decryptLayer(hop.keys.privateKey);
    final cmd = plaintext[0];
    if (cmd == GarlicBuilder.cmdForward) {
      packet = GarlicBuilder.buildPacket(
        plaintext.sublist(1, 21),
        plaintext.sublist(21),
      );
      continue;
    }
    var offset = 1;
    final ohId = Uint8List.fromList(plaintext.sublist(offset, offset += 20));
    if (cmd == GarlicBuilder.cmdDeliverTagged) {
      offset += GarlicBuilder.sessionTagLength; // skip session tag
    } else if (cmd == GarlicBuilder.cmdDeliverAcked) {
      final tagLen = plaintext[offset++];
      offset += tagLen; // skip optional session tag
      final hopN = plaintext[offset + 36]; // return-path hop_count byte
      offset += ReturnPathBlock.serializedLength(hopN);
    } else if (cmd == GarlicBuilder.cmdRecordStore ||
        cmd == GarlicBuilder.cmdRecordLookup) {
      return null; // T44 rendezvous packet, not a mailbox deposit
    } else if (cmd != GarlicBuilder.cmdDeliver) {
      fail('unexpected garlic deliver command $cmd');
    }
    final payloadLen = ByteData.sublistView(
      Uint8List.fromList(plaintext),
    ).getUint32(offset);
    offset += 4;
    final payload = Uint8List.fromList(
      plaintext.sublist(offset, offset + payloadLen),
    );
    return GarlicDeposit(ohId, payload, hopCount);
  }
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

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
