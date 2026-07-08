import 'dart:typed_data';

import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';

/// The return-path block of a `CMD_DELIVER_ACKED` deliver (Frontend MS06).
///
/// Binary format (master spec, Decisions Backend-MS06, Decision 2 — mirrors
/// the backend `ReturnPath.java`; no proto, it travels in the layer
/// plaintext):
///
/// ```
/// [20 ack_oh_id]        // sender's own OH mailbox for the R-ACK
/// [16 ack_session_tag]  // correlates the R-ACK item with the message
/// [1  hop_count 0..4]
/// [hop_count × (20 kademlia_id + 32 encryption_pub)]
/// ```
///
/// Hop descriptors, not pre-encrypted layers: the node with the final
/// deposit decision builds the R-ACK onion itself (pre-encrypted reply
/// layers cannot carry a payload through stateless GCM relays — the MS05
/// Decision 6 argument). `hop_count = 0` means the depositing node delivers
/// the R-ACK directly to the ack OH host.
class ReturnPathBlock {
  final Uint8List ackOhId;
  final Uint8List ackSessionTag;
  final List<GarlicHop> hops;

  static const int maxHops = 4;

  /// Maximum serialized size: 37 + 4 × 52 (backend
  /// `ReturnPath.MAX_SERIALIZED_LEN`).
  static const int maxSerializedLength = 37 + maxHops * hopLength;

  /// Bytes per hop descriptor: 20-byte KademliaId + 32-byte X25519 key.
  static const int hopLength = GarlicHop.nodeIdLength + 32;

  ReturnPathBlock({
    required List<int> ackOhId,
    required List<int> ackSessionTag,
    required this.hops,
  }) : ackOhId = Uint8List.fromList(ackOhId),
       ackSessionTag = Uint8List.fromList(ackSessionTag) {
    if (this.ackOhId.length != GarlicHop.nodeIdLength) {
      throw ArgumentError.value(
        this.ackOhId.length,
        'ackOhId',
        'ack_oh_id must be ${GarlicHop.nodeIdLength} bytes',
      );
    }
    if (this.ackSessionTag.length != GarlicBuilder.sessionTagLength) {
      throw ArgumentError.value(
        this.ackSessionTag.length,
        'ackSessionTag',
        'ack_session_tag must be ${GarlicBuilder.sessionTagLength} bytes',
      );
    }
    if (hops.length > maxHops) {
      throw ArgumentError.value(
        hops.length,
        'hops',
        'return path carries at most $maxHops hops',
      );
    }
  }

  /// Serialized size of a return path with [hopCount] hops (37 + 52·h).
  static int serializedLength(int hopCount) =>
      GarlicHop.nodeIdLength +
      GarlicBuilder.sessionTagLength +
      1 +
      hopCount * hopLength;

  Uint8List serialize() {
    final out = BytesBuilder()
      ..add(ackOhId)
      ..add(ackSessionTag)
      ..addByte(hops.length);
    for (final hop in hops) {
      out
        ..add(hop.nodeId)
        ..add(hop.encryptionPublicKey);
    }
    return out.toBytes();
  }

  /// Parses a serialized block; the counterpart of the backend
  /// `ReturnPath.parseExact` (used by tests). Throws [FormatException] on
  /// structural errors, including trailing bytes.
  factory ReturnPathBlock.deserialize(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    const minLength =
        GarlicHop.nodeIdLength + GarlicBuilder.sessionTagLength + 1;
    if (data.length < minLength) {
      throw const FormatException('ReturnPathBlock: truncated header');
    }
    var offset = 0;
    final ohId = data.sublist(offset, offset += GarlicHop.nodeIdLength);
    final tag = data.sublist(offset, offset += GarlicBuilder.sessionTagLength);
    final hopCount = data[offset++];
    if (hopCount > maxHops) {
      throw FormatException('ReturnPathBlock: hop_count $hopCount > $maxHops');
    }
    if (data.length != offset + hopCount * hopLength) {
      throw const FormatException('ReturnPathBlock: length mismatch');
    }
    final hops = <GarlicHop>[];
    for (var i = 0; i < hopCount; i++) {
      hops.add(
        GarlicHop(
          nodeId: data.sublist(offset, offset += GarlicHop.nodeIdLength),
          encryptionPublicKey: data.sublist(offset, offset += 32),
        ),
      );
    }
    return ReturnPathBlock(ackOhId: ohId, ackSessionTag: tag, hops: hops);
  }
}
