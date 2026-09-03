import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart' as pb;
import 'package:redpanda_light_client/src/generated/outbound.pb.dart'
    as outbound_pb;

/// The R-ACK payload deposited into the sender's OH mailbox (Frontend MS06).
///
/// Wire format is owned by the vendored backend schema
/// (`protos/outbound.proto`, message `RoutingAck`) — this class is a thin,
/// `int`-typed view over the generated `outbound_pb.RoutingAck` so that call
/// sites do not have to deal with `Int64`:
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
/// `ack_session_tag` that arrives as `MailItem.session_tag` on the R-ACK item.
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
    final outbound_pb.RoutingAck decoded;
    try {
      decoded = outbound_pb.RoutingAck.fromBuffer(bytes);
    } on pb.InvalidProtocolBufferException catch (e) {
      throw FormatException('RoutingAck: ${e.message}');
    }
    return RoutingAck(
      timestampMs: decoded.timestampMs.toInt(),
      status: decoded.status,
    );
  }

  /// Encodes this ack to proto3 binary form (used by tests; the reference
  /// producer is the backend `RoutingAckSender`).
  Uint8List encode() => toProto().writeToBuffer();

  /// The generated protobuf message backing this ack.
  outbound_pb.RoutingAck toProto() =>
      outbound_pb.RoutingAck(timestampMs: Int64(timestampMs), status: status);
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
