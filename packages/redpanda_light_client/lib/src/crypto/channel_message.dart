import 'dart:convert';
import 'dart:typed_data';

/// The inner plaintext of a message-format-v2 payload.
///
/// Wire format (MS03 message-format-v2 spec):
///
/// ```
/// ChannelMessage {
///   bytes  message_id   = 1;  // 16 random bytes, stable across retries
///   int64  timestamp_ms = 2;
///   string content      = 3;
///   bytes  reply_path   = 5;  // MS05: serialized ReverseGarlicBlock (optional)
/// }
/// ```
///
/// Field 5 matches the master-spec MS05 protobuf sketch (`reply_path = 5`);
/// field 4 stays unused (the master sketch reserves 3/4 for iv/timestamp,
/// which this client carries elsewhere). `reply_path` is opaque bytes here —
/// the RGB layout lives in `domain/reverse_garlic_block.dart`.
///
/// This is a hand-rolled encoder/decoder that is **wire-compatible with
/// proto3** for exactly these three fields. We do not run `protoc` against a
/// `ChannelMessage` message here because the committed generated protobuf
/// files in `lib/src/generated/` were post-processed by hand (Status enum
/// inlined, `fromJson` factories stripped) and are not reproducible by a plain
/// regeneration with the protoc compiler available in this environment;
/// regenerating would produce a large, unrelated diff and overwrite those
/// hand edits. The encoding below follows the proto3 binary spec precisely:
///
/// - field 1 (message_id): wire type 2 (length-delimited), tag byte `0x0A`
/// - field 2 (timestamp_ms): wire type 0 (varint), tag byte `0x10`,
///   value encoded as a proto3 `int64` (two's-complement, 64-bit varint)
/// - field 3 (content): wire type 2 (length-delimited), tag byte `0x1A`,
///   value is the UTF-8 bytes of the string
///
/// Because it is real proto3 wire format, a future drop-in replacement with a
/// generated `ChannelMessage` class (same field numbers/types) reads and
/// writes byte-identical buffers — no migration needed.
class ChannelMessage {
  /// 16 random bytes that identify this logical message. Stable across
  /// re-sends/retries so the receiver can deduplicate.
  final Uint8List messageId;

  /// Sender-side send time in milliseconds since the Unix epoch.
  final int timestampMs;

  /// The plaintext message content.
  final String content;

  /// MS05: serialized ReverseGarlicBlock the sender attached so the receiver
  /// can reply via reverse garlic. Null/empty when no reply path travels.
  final Uint8List? replyPath;

  const ChannelMessage({
    required this.messageId,
    required this.timestampMs,
    required this.content,
    this.replyPath,
  });

  /// Encodes this message to its proto3-compatible binary representation.
  Uint8List encode() {
    final out = BytesBuilder();

    // field 1: message_id (length-delimited)
    if (messageId.isNotEmpty) {
      out.addByte(0x0A); // (1 << 3) | 2
      _writeVarint(out, messageId.length);
      out.add(messageId);
    }

    // field 2: timestamp_ms (varint, proto3 int64)
    if (timestampMs != 0) {
      out.addByte(0x10); // (2 << 3) | 0
      _writeVarint(out, timestampMs);
    }

    // field 3: content (length-delimited UTF-8)
    final contentBytes = utf8.encode(content);
    if (contentBytes.isNotEmpty) {
      out.addByte(0x1A); // (3 << 3) | 2
      _writeVarint(out, contentBytes.length);
      out.add(contentBytes);
    }

    // field 5: reply_path (length-delimited, MS05)
    final replyPathBytes = replyPath;
    if (replyPathBytes != null && replyPathBytes.isNotEmpty) {
      out.addByte(0x2A); // (5 << 3) | 2
      _writeVarint(out, replyPathBytes.length);
      out.add(replyPathBytes);
    }

    return out.toBytes();
  }

  /// Decodes a [ChannelMessage] from its proto3-compatible binary form.
  ///
  /// Unknown fields are skipped (forward compatibility). Throws
  /// [FormatException] on truncated or malformed input.
  factory ChannelMessage.decode(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    var offset = 0;

    Uint8List messageId = Uint8List(0);
    int timestampMs = 0;
    String content = '';
    Uint8List? replyPath;

    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (offset >= data.length) {
          throw const FormatException('ChannelMessage: truncated varint');
        }
        final b = data[offset++];
        result |= (b & 0x7F) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
        if (shift > 63) {
          throw const FormatException('ChannelMessage: varint too long');
        }
      }
      return result;
    }

    while (offset < data.length) {
      final tag = readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;

      switch (fieldNumber) {
        case 1: // message_id
          if (wireType != 2) {
            throw const FormatException('ChannelMessage: bad wire type for #1');
          }
          final len = readVarint();
          if (offset + len > data.length) {
            throw const FormatException('ChannelMessage: truncated message_id');
          }
          messageId = Uint8List.sublistView(data, offset, offset + len);
          offset += len;
          break;
        case 2: // timestamp_ms
          if (wireType != 0) {
            throw const FormatException('ChannelMessage: bad wire type for #2');
          }
          timestampMs = readVarint();
          break;
        case 3: // content
          if (wireType != 2) {
            throw const FormatException('ChannelMessage: bad wire type for #3');
          }
          final len = readVarint();
          if (offset + len > data.length) {
            throw const FormatException('ChannelMessage: truncated content');
          }
          content = utf8.decode(data.sublist(offset, offset + len));
          offset += len;
          break;
        case 5: // reply_path (MS05)
          if (wireType != 2) {
            throw const FormatException('ChannelMessage: bad wire type for #5');
          }
          final replyLen = readVarint();
          if (offset + replyLen > data.length) {
            throw const FormatException('ChannelMessage: truncated reply_path');
          }
          replyPath = Uint8List.fromList(
            data.sublist(offset, offset + replyLen),
          );
          offset += replyLen;
          break;
        default:
          // Unknown field — skip according to wire type.
          _skipField(
            data,
            wireType,
            () => offset,
            (v) => offset = v,
            readVarint,
          );
          break;
      }
    }

    return ChannelMessage(
      messageId: Uint8List.fromList(messageId),
      timestampMs: timestampMs,
      content: content,
      replyPath: replyPath,
    );
  }

  static void _writeVarint(BytesBuilder out, int value) {
    // Treat as unsigned 64-bit (proto3 int64 negatives are 10-byte varints,
    // but our timestamps and lengths are always non-negative).
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

  static void _skipField(
    Uint8List data,
    int wireType,
    int Function() getOffset,
    void Function(int) setOffset,
    int Function() readVarint,
  ) {
    switch (wireType) {
      case 0: // varint
        readVarint();
        break;
      case 1: // 64-bit
        setOffset(getOffset() + 8);
        break;
      case 2: // length-delimited
        final len = readVarint();
        setOffset(getOffset() + len);
        break;
      case 5: // 32-bit
        setOffset(getOffset() + 4);
        break;
      default:
        throw FormatException('ChannelMessage: unknown wire type $wireType');
    }
  }
}
