import 'dart:convert';
import 'dart:typed_data';

/// The inner plaintext of a message-format-v2 payload.
///
/// Wire format (MS03 message-format-v2 spec):
///
/// ```
/// ChannelMessage {
///   bytes  message_id      = 1;  // 16 random bytes, stable across retries
///   int64  timestamp_ms    = 2;
///   string content         = 3;
///   bytes  reply_path      = 5;  // MS05: serialized ReverseGarlicBlock (optional)
///   bytes  ack_message_id  = 6;  // MS06: Channel-ACK for this message id (optional)
///   bytes  group_handshake = 7;  // MS08: serialized GroupHandshake (1:1 only, optional)
///   bytes  group_control   = 8;  // MS08: serialized GroupControl (groups only, optional)
///   bytes  oh_update       = 9;  // T21: UTF-8 OHDescriptor JSON (OH failover, optional)
/// }
/// ```
///
/// A message with a non-empty `ack_message_id` is a **Channel-ACK**
/// (Frontend MS06): it confirms receipt of the referenced message and
/// carries no content; the receiver updates the message status instead of
/// showing it.
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

  /// MS06: the message id this message acknowledges (Channel-ACK).
  /// Null/empty for regular messages.
  final Uint8List? ackMessageId;

  /// MS08: serialized GroupHandshake riding a 1:1 channel (Decision 8).
  /// Null/empty for regular messages; the layout lives in
  /// `crypto/group_control.dart`.
  final Uint8List? groupHandshake;

  /// MS08: serialized GroupControl riding a group message (e.g. a rename).
  /// Null/empty for regular messages.
  final Uint8List? groupControl;

  /// T21: UTF-8 encoded OHDescriptor JSON announcing the sender's NEW own
  /// mailbox after an OH failover. Null/empty for regular messages. The
  /// authenticity check is the ratchet decryption itself — only the channel
  /// partner holds the message keys.
  final Uint8List? ohUpdate;

  const ChannelMessage({
    required this.messageId,
    required this.timestampMs,
    required this.content,
    this.replyPath,
    this.ackMessageId,
    this.groupHandshake,
    this.groupControl,
    this.ohUpdate,
  });

  /// True when this message is a Channel-ACK (MS06).
  bool get isChannelAck => ackMessageId != null && ackMessageId!.isNotEmpty;

  /// True when this message carries a group handshake (MS08).
  bool get isGroupHandshake =>
      groupHandshake != null && groupHandshake!.isNotEmpty;

  /// True when this message carries a group control action (MS08).
  bool get isGroupControl => groupControl != null && groupControl!.isNotEmpty;

  /// True when this message announces a new peer mailbox (T21 failover).
  bool get isOhUpdate => ohUpdate != null && ohUpdate!.isNotEmpty;

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

    // field 6: ack_message_id (length-delimited, MS06)
    final ackBytes = ackMessageId;
    if (ackBytes != null && ackBytes.isNotEmpty) {
      out.addByte(0x32); // (6 << 3) | 2
      _writeVarint(out, ackBytes.length);
      out.add(ackBytes);
    }

    // field 7: group_handshake (length-delimited, MS08)
    final handshakeBytes = groupHandshake;
    if (handshakeBytes != null && handshakeBytes.isNotEmpty) {
      out.addByte(0x3A); // (7 << 3) | 2
      _writeVarint(out, handshakeBytes.length);
      out.add(handshakeBytes);
    }

    // field 8: group_control (length-delimited, MS08)
    final controlBytes = groupControl;
    if (controlBytes != null && controlBytes.isNotEmpty) {
      out.addByte(0x42); // (8 << 3) | 2
      _writeVarint(out, controlBytes.length);
      out.add(controlBytes);
    }

    // field 9: oh_update (length-delimited, T21)
    final ohUpdateBytes = ohUpdate;
    if (ohUpdateBytes != null && ohUpdateBytes.isNotEmpty) {
      out.addByte(0x4A); // (9 << 3) | 2
      _writeVarint(out, ohUpdateBytes.length);
      out.add(ohUpdateBytes);
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
    Uint8List? ackMessageId;
    Uint8List? groupHandshake;
    Uint8List? groupControl;
    Uint8List? ohUpdate;

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
        case 6: // ack_message_id (MS06)
          if (wireType != 2) {
            throw const FormatException('ChannelMessage: bad wire type for #6');
          }
          final ackLen = readVarint();
          if (offset + ackLen > data.length) {
            throw const FormatException(
              'ChannelMessage: truncated ack_message_id',
            );
          }
          ackMessageId = Uint8List.fromList(
            data.sublist(offset, offset + ackLen),
          );
          offset += ackLen;
          break;
        case 7: // group_handshake (MS08)
          if (wireType != 2) {
            throw const FormatException('ChannelMessage: bad wire type for #7');
          }
          final handshakeLen = readVarint();
          if (offset + handshakeLen > data.length) {
            throw const FormatException(
              'ChannelMessage: truncated group_handshake',
            );
          }
          groupHandshake = Uint8List.fromList(
            data.sublist(offset, offset + handshakeLen),
          );
          offset += handshakeLen;
          break;
        case 8: // group_control (MS08)
          if (wireType != 2) {
            throw const FormatException('ChannelMessage: bad wire type for #8');
          }
          final controlLen = readVarint();
          if (offset + controlLen > data.length) {
            throw const FormatException(
              'ChannelMessage: truncated group_control',
            );
          }
          groupControl = Uint8List.fromList(
            data.sublist(offset, offset + controlLen),
          );
          offset += controlLen;
          break;
        case 9: // oh_update (T21)
          if (wireType != 2) {
            throw const FormatException('ChannelMessage: bad wire type for #9');
          }
          final ohUpdateLen = readVarint();
          if (offset + ohUpdateLen > data.length) {
            throw const FormatException('ChannelMessage: truncated oh_update');
          }
          ohUpdate = Uint8List.fromList(
            data.sublist(offset, offset + ohUpdateLen),
          );
          offset += ohUpdateLen;
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
      ackMessageId: ackMessageId,
      groupHandshake: groupHandshake,
      groupControl: groupControl,
      ohUpdate: ohUpdate,
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
