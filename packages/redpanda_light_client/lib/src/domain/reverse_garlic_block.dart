import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart' as pb_runtime;
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/generated/client/reverse_garlic_block.pb.dart'
    as client_pb;

/// A Reverse Garlic Block (MS05): the reply-path descriptor Alice attaches
/// to an outgoing message so Bob can route a reply to her OH mailbox without
/// learning her network location.
///
/// Per master-spec Decision 6 (Backend-MS05), the RGB carries **hop
/// descriptors** instead of pre-encrypted onion layers: pre-encrypted
/// SURB-style layers cannot transport Bob's reply payload through the
/// stateless MS04 relays (every layer is GCM-authenticated). Bob builds the
/// reply as a standard MS04 onion over the hops Alice picked, with a
/// `CMD_DELIVER_TAGGED (0x03)` innermost layer carrying the session tag.
///
/// Wire format: `protos/client/reverse_garlic_block.proto` (Frontend-MS05,
/// TD098/T142); this class is a validated view over the generated
/// `client_pb.ReverseGarlicBlock`. `version` and `expiry_ts` have explicit
/// presence there because the original hand-written encoder always wrote
/// them, even as 0 — the bytes must stay identical for deployed clients
/// (`test/unit/client_protos_roundtrip_test.dart` pins them).
///
/// The serialized block travels channel-encrypted inside the
/// `ChannelMessage.reply_path` field — only the channel partner reads it.
class ReverseGarlicBlock {
  /// The only supported RGB version.
  static const int currentVersion = 1;

  /// Random session tags are exactly this many bytes (backend
  /// `FlaschenpostV2.SESSION_TAG_LEN`).
  static const int sessionTagLength = GarlicBuilder.sessionTagLength;

  final int version;

  /// Unix ms after which the RGB must not be used anymore.
  final int expiryTs;

  /// 16 random bytes; the recipient stores tag → channel and enforces
  /// single-use.
  final Uint8List sessionTag;

  /// 20-byte KademliaId of the issuer's OH mailbox (the reply destination).
  final Uint8List ohId;

  /// Return-path relay hops, outermost first (the responder's onion visits
  /// `hops[0]` first).
  final List<GarlicHop> hops;

  ReverseGarlicBlock({
    this.version = currentVersion,
    required this.expiryTs,
    required List<int> sessionTag,
    required List<int> ohId,
    required this.hops,
  }) : sessionTag = Uint8List.fromList(sessionTag),
       ohId = Uint8List.fromList(ohId) {
    if (version != currentVersion) {
      throw FormatException('ReverseGarlicBlock: unsupported version $version');
    }
    if (this.sessionTag.length != sessionTagLength) {
      throw FormatException(
        'ReverseGarlicBlock: session_tag must be $sessionTagLength bytes, '
        'got ${this.sessionTag.length}',
      );
    }
    if (this.ohId.length != GarlicHop.nodeIdLength) {
      throw FormatException(
        'ReverseGarlicBlock: oh_id must be ${GarlicHop.nodeIdLength} bytes, '
        'got ${this.ohId.length}',
      );
    }
    if (hops.isEmpty) {
      throw const FormatException('ReverseGarlicBlock: need at least one hop');
    }
  }

  /// True when the RGB must no longer be used ([nowMs] defaults to now).
  bool isExpired([int? nowMs]) =>
      (nowMs ?? DateTime.now().millisecondsSinceEpoch) >= expiryTs;

  /// Lowercase hex of [sessionTag] (lookup key of the session tag store).
  String get sessionTagHex => _hexEncode(sessionTag);

  /// Encodes this block to its proto3 binary representation.
  Uint8List serialize() => client_pb.ReverseGarlicBlock(
    version: version,
    expiryTs: Int64(expiryTs),
    sessionTag: sessionTag,
    ohId: ohId,
    hops: [
      for (final hop in hops)
        client_pb.RgbHop(kadId: hop.nodeId, encPub: hop.encryptionPublicKey),
    ],
  ).writeToBuffer();

  /// Decodes a block from its proto3 binary form.
  ///
  /// Unknown fields are skipped (forward compatibility). Throws
  /// [FormatException] on truncated or malformed input, an unsupported
  /// version or invalid field lengths. A known field with the wrong wire type
  /// is skipped like an unknown one (protobuf runtime behaviour) and then
  /// fails the presence/length validation below.
  factory ReverseGarlicBlock.deserialize(List<int> bytes) {
    final client_pb.ReverseGarlicBlock pb;
    try {
      pb = client_pb.ReverseGarlicBlock.fromBuffer(bytes);
    } on pb_runtime.InvalidProtocolBufferException catch (e) {
      throw FormatException('ReverseGarlicBlock: ${e.message}');
    }
    if (!pb.hasSessionTag() || !pb.hasOhId()) {
      throw const FormatException(
        'ReverseGarlicBlock: missing session_tag or oh_id',
      );
    }
    return ReverseGarlicBlock(
      version: pb.version,
      expiryTs: pb.expiryTs.toInt(),
      sessionTag: pb.sessionTag,
      ohId: pb.ohId,
      hops: [for (final hop in pb.hops) _toHop(hop)],
    );
  }

  static GarlicHop _toHop(client_pb.RgbHop hop) {
    if (!hop.hasKadId() || !hop.hasEncPub()) {
      throw const FormatException('ReverseGarlicBlock: incomplete hop');
    }
    try {
      return GarlicHop(nodeId: hop.kadId, encryptionPublicKey: hop.encPub);
    } on ArgumentError catch (e) {
      throw FormatException('ReverseGarlicBlock: invalid hop: ${e.message}');
    }
  }

  static String _hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
