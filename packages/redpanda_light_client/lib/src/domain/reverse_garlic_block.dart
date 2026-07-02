import 'dart:typed_data';

import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';

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
/// Wire format: proto3-compatible binary, hand-rolled like
/// `crypto/channel_message.dart` (the committed generated protobuf files are
/// hand-maintained and not regenerated). Field layout (Frontend-MS05):
///
/// ```
/// ReverseGarlicBlock {
///   uint32 version     = 1;  // 1
///   int64  expiry_ts   = 2;  // Unix ms — Bob must not use the RGB after this
///   bytes  session_tag = 3;  // 16 random bytes, correlates the reply
///   bytes  oh_id       = 4;  // 20-byte KademliaId of Alice's OH mailbox
///   repeated RgbHop hops = 5;
/// }
/// RgbHop {
///   bytes kad_id  = 1;  // 20-byte KademliaId of the relay
///   bytes enc_pub = 2;  // 32-byte X25519 encryption public key
/// }
/// ```
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

  /// Encodes this block to its proto3-compatible binary representation.
  Uint8List serialize() {
    final out = BytesBuilder();

    // field 1: version (varint)
    out.addByte(0x08); // (1 << 3) | 0
    _writeVarint(out, version);

    // field 2: expiry_ts (varint, proto3 int64; always non-negative here)
    out.addByte(0x10); // (2 << 3) | 0
    _writeVarint(out, expiryTs);

    // field 3: session_tag (length-delimited)
    out.addByte(0x1A); // (3 << 3) | 2
    _writeVarint(out, sessionTag.length);
    out.add(sessionTag);

    // field 4: oh_id (length-delimited)
    out.addByte(0x22); // (4 << 3) | 2
    _writeVarint(out, ohId.length);
    out.add(ohId);

    // field 5: hops (repeated embedded message)
    for (final hop in hops) {
      final hopBytes = BytesBuilder()
        ..addByte(0x0A) // RgbHop field 1: kad_id
        ..addByte(hop.nodeId.length)
        ..add(hop.nodeId)
        ..addByte(0x12) // RgbHop field 2: enc_pub
        ..addByte(hop.encryptionPublicKey.length)
        ..add(hop.encryptionPublicKey);
      out.addByte(0x2A); // (5 << 3) | 2
      _writeVarint(out, hopBytes.length);
      out.add(hopBytes.toBytes());
    }

    return out.toBytes();
  }

  /// Decodes a block from its proto3-compatible binary form.
  ///
  /// Unknown fields are skipped (forward compatibility). Throws
  /// [FormatException] on truncated or malformed input, an unsupported
  /// version or invalid field lengths.
  factory ReverseGarlicBlock.deserialize(List<int> bytes) {
    final reader = _ProtoReader(Uint8List.fromList(bytes));

    var version = 0;
    var expiryTs = 0;
    Uint8List? sessionTag;
    Uint8List? ohId;
    final hops = <GarlicHop>[];

    while (!reader.isDone) {
      final tag = reader.readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;
      switch (fieldNumber) {
        case 1:
          reader.expectWireType(wireType, 0, 'version');
          version = reader.readVarint();
          break;
        case 2:
          reader.expectWireType(wireType, 0, 'expiry_ts');
          expiryTs = reader.readVarint();
          break;
        case 3:
          reader.expectWireType(wireType, 2, 'session_tag');
          sessionTag = reader.readBytes();
          break;
        case 4:
          reader.expectWireType(wireType, 2, 'oh_id');
          ohId = reader.readBytes();
          break;
        case 5:
          reader.expectWireType(wireType, 2, 'hops');
          hops.add(_readHop(_ProtoReader(reader.readBytes())));
          break;
        default:
          reader.skipField(wireType);
          break;
      }
    }

    if (sessionTag == null || ohId == null) {
      throw const FormatException(
        'ReverseGarlicBlock: missing session_tag or oh_id',
      );
    }
    return ReverseGarlicBlock(
      version: version,
      expiryTs: expiryTs,
      sessionTag: sessionTag,
      ohId: ohId,
      hops: hops,
    );
  }

  static GarlicHop _readHop(_ProtoReader reader) {
    Uint8List? kadId;
    Uint8List? encPub;
    while (!reader.isDone) {
      final tag = reader.readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;
      switch (fieldNumber) {
        case 1:
          reader.expectWireType(wireType, 2, 'hop kad_id');
          kadId = reader.readBytes();
          break;
        case 2:
          reader.expectWireType(wireType, 2, 'hop enc_pub');
          encPub = reader.readBytes();
          break;
        default:
          reader.skipField(wireType);
          break;
      }
    }
    if (kadId == null || encPub == null) {
      throw const FormatException('ReverseGarlicBlock: incomplete hop');
    }
    try {
      return GarlicHop(nodeId: kadId, encryptionPublicKey: encPub);
    } on ArgumentError catch (e) {
      throw FormatException('ReverseGarlicBlock: invalid hop: ${e.message}');
    }
  }

  static void _writeVarint(BytesBuilder out, int value) {
    var v = value;
    while (true) {
      final byte = v & 0x7F;
      v = v >>> 7;
      if (v == 0) {
        out.addByte(byte);
        break;
      }
      out.addByte(byte | 0x80);
    }
  }

  static String _hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Minimal proto3 wire-format reader for [ReverseGarlicBlock.deserialize].
class _ProtoReader {
  final Uint8List _data;
  int _offset = 0;

  _ProtoReader(this._data);

  bool get isDone => _offset >= _data.length;

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_offset >= _data.length) {
        throw const FormatException('ReverseGarlicBlock: truncated varint');
      }
      final b = _data[_offset++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) {
        throw const FormatException('ReverseGarlicBlock: varint too long');
      }
    }
    return result;
  }

  Uint8List readBytes() {
    final len = readVarint();
    if (_offset + len > _data.length) {
      throw const FormatException('ReverseGarlicBlock: truncated bytes field');
    }
    final view = Uint8List.fromList(_data.sublist(_offset, _offset + len));
    _offset += len;
    return view;
  }

  void expectWireType(int actual, int expected, String field) {
    if (actual != expected) {
      throw FormatException('ReverseGarlicBlock: bad wire type for $field');
    }
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        _offset += 8;
        break;
      case 2:
        readBytes();
        break;
      case 5:
        _offset += 4;
        break;
      default:
        throw FormatException(
          'ReverseGarlicBlock: unknown wire type $wireType',
        );
    }
  }
}
