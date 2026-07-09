import 'dart:typed_data';

/// The R-ACK payload deposited into the sender's OH mailbox (Frontend MS06).
///
/// Wire format (master spec, Decisions Backend-MS06, Decision 3 — mirrors the
/// backend `outbound.proto` `RoutingAck`):
///
/// ```
/// RoutingAck {
///   int64  timestamp_ms = 1;  // deposit decision time on the acking node
///   uint32 status       = 2;  // always set explicitly
/// }
/// ```
///
/// There is deliberately **no** `message_id`: the mailbox UUID is created
/// server-side and means nothing to the sender — correlation runs over the
/// `ack_session_tag` that arrives as `MailItem.session_tag` on the R-ACK
/// item. Hand-rolled proto3 decoding for the same reason as
/// `ChannelMessage`: the committed generated protobuf files are
/// hand-post-processed and not regenerable here.
class RoutingAck {
  /// Deposit decision timestamp on the acking node (its clock).
  final int timestampMs;

  /// Deposit outcome, one of the `status*` constants.
  final int status;

  const RoutingAck({required this.timestampMs, required this.status});

  /// The message was stored in the recipient's OH mailbox.
  static const int statusStored = 0;

  /// The recipient's mailbox rejected the deposit (reject-new, MS02b).
  static const int statusMailboxFull = 1;

  /// The OH handle is expired or could not be resolved at the hop limit.
  static const int statusHandleExpired = 2;

  /// The deposit was rejected for another reason (e.g. size).
  static const int statusRejected = 3;

  /// Decodes a [RoutingAck] from its proto3 binary form. Unknown fields are
  /// skipped. Throws [FormatException] on malformed input.
  factory RoutingAck.decode(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    var offset = 0;

    int timestampMs = 0;
    int status = 0;

    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (offset >= data.length) {
          throw const FormatException('RoutingAck: truncated varint');
        }
        final b = data[offset++];
        result |= (b & 0x7F) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
        if (shift > 63) {
          throw const FormatException('RoutingAck: varint too long');
        }
      }
      return result;
    }

    while (offset < data.length) {
      final tag = readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;

      switch (fieldNumber) {
        case 1: // timestamp_ms
          if (wireType != 0) {
            throw const FormatException('RoutingAck: bad wire type for #1');
          }
          timestampMs = readVarint();
          break;
        case 2: // status
          if (wireType != 0) {
            throw const FormatException('RoutingAck: bad wire type for #2');
          }
          status = readVarint();
          break;
        default:
          switch (wireType) {
            case 0:
              readVarint();
              break;
            case 1:
              offset += 8;
              break;
            case 2:
              final len = readVarint();
              offset += len;
              break;
            case 5:
              offset += 4;
              break;
            default:
              throw FormatException('RoutingAck: unknown wire type $wireType');
          }
          break;
      }
    }

    return RoutingAck(timestampMs: timestampMs, status: status);
  }

  /// Encodes this ack to proto3 binary form (used by tests; the reference
  /// producer is the backend `RoutingAckSender`).
  Uint8List encode() {
    final out = BytesBuilder();
    if (timestampMs != 0) {
      out.addByte(0x08); // (1 << 3) | 0
      _writeVarint(out, timestampMs);
    }
    if (status != 0) {
      out.addByte(0x10); // (2 << 3) | 0
      _writeVarint(out, status);
    }
    return out.toBytes();
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
}

/// Routing-layer delivery feedback for one outgoing message (Frontend MS06),
/// emitted by the network client so the app layer can update the message
/// status and trigger a re-send on timeout.
class RoutingAckUpdate {
  /// Channel the acknowledged message belongs to.
  final String channelId;

  /// Stable network-level message id (hex) of the acknowledged message.
  final String messageIdHex;

  /// Deposit outcome ([RoutingAck.status]); null when [timedOut].
  final int? status;

  /// Milliseconds between the send and the fetch of the R-ACK (local clock
  /// on both ends — includes the mailbox polling delay); null on timeout.
  final int? latencyMs;

  /// True when no R-ACK arrived within the ack timeout — the involved hops
  /// were scored down and the app should re-send over fresh hops.
  final bool timedOut;

  /// MS08: the group member this delivery targeted (hex member id) —
  /// group fan-outs request one R-ACK per recipient. Null for 1:1 sends.
  final String? memberIdHex;

  const RoutingAckUpdate.ack({
    required this.channelId,
    required this.messageIdHex,
    required int this.status,
    required int this.latencyMs,
    this.memberIdHex,
  }) : timedOut = false;

  const RoutingAckUpdate.timeout({
    required this.channelId,
    required this.messageIdHex,
    this.memberIdHex,
  }) : status = null,
       latencyMs = null,
       timedOut = true;
}

/// Application-layer delivery confirmation (Channel-ACK, Frontend MS06):
/// the channel partner received and decrypted the message.
class ChannelAckUpdate {
  /// Channel the acknowledged message belongs to.
  final String channelId;

  /// Network-level message id (hex) of the acknowledged message.
  final String messageIdHex;

  /// The partner's receive timestamp (their clock).
  final int timestampMs;

  /// MS08: the group member that confirmed receipt (hex member id).
  /// Null for 1:1 acks.
  final String? memberIdHex;

  const ChannelAckUpdate({
    required this.channelId,
    required this.messageIdHex,
    required this.timestampMs,
    this.memberIdHex,
  });
}
