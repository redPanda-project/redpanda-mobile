import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart' as pb_runtime;
import 'package:redpanda_light_client/src/generated/client/channel_message.pb.dart'
    as client_pb;

/// The inner plaintext of a message-format-v2 payload.
///
/// Wire format: `protos/client/channel_message.proto` (MS03
/// message-format-v2, extended by MS05/MS06/MS08/T21).
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
/// The schema is `protos/client/channel_message.proto` (TD098/T142); this
/// class is an `int`/nullable view over the generated
/// `client_pb.ChannelMessage`. [encode] sets only non-default fields: the
/// protobuf-dart runtime writes an explicitly set default (`content = ''` →
/// `1a 00`), the hand-written encoder this replaced did not, and the bytes
/// must stay identical for deployed clients
/// (`test/unit/client_protos_roundtrip_test.dart` pins them).
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

  /// True when this message announces a new counterpart mailbox (T21 failover).
  bool get isOhUpdate => ohUpdate != null && ohUpdate!.isNotEmpty;

  /// Encodes this message to its proto3 binary representation.
  Uint8List encode() {
    final pb = client_pb.ChannelMessage();
    if (messageId.isNotEmpty) pb.messageId = messageId;
    if (timestampMs != 0) pb.timestampMs = Int64(timestampMs);
    if (content.isNotEmpty) pb.content = content;
    if (_isSet(replyPath)) pb.replyPath = replyPath!;
    if (_isSet(ackMessageId)) pb.ackMessageId = ackMessageId!;
    if (_isSet(groupHandshake)) pb.groupHandshake = groupHandshake!;
    if (_isSet(groupControl)) pb.groupControl = groupControl!;
    if (_isSet(ohUpdate)) pb.ohUpdate = ohUpdate!;
    return pb.writeToBuffer();
  }

  /// Decodes a [ChannelMessage] from its proto3 binary form.
  ///
  /// Unknown fields are skipped (forward compatibility). Throws
  /// [FormatException] on truncated or malformed input.
  ///
  /// Two deliberate leniencies against the hand-rolled decoder this replaced
  /// (same reasoning as `RoutingAck.decode`): a known field with the wrong
  /// wire type is skipped like an unknown field instead of throwing, and
  /// malformed UTF-8 in `content` decodes with U+FFFD instead of throwing.
  /// The bytes only ever come out of a successful AEAD decryption, i.e. from
  /// the channel partner, whose own encoder emits canonical proto3.
  factory ChannelMessage.decode(List<int> bytes) {
    final client_pb.ChannelMessage pb;
    try {
      pb = client_pb.ChannelMessage.fromBuffer(bytes);
    } on pb_runtime.InvalidProtocolBufferException catch (e) {
      throw FormatException('ChannelMessage: ${e.message}');
    }
    return ChannelMessage(
      messageId: Uint8List.fromList(pb.messageId),
      timestampMs: pb.timestampMs.toInt(),
      content: pb.content,
      replyPath: pb.hasReplyPath() ? Uint8List.fromList(pb.replyPath) : null,
      ackMessageId: pb.hasAckMessageId()
          ? Uint8List.fromList(pb.ackMessageId)
          : null,
      groupHandshake: pb.hasGroupHandshake()
          ? Uint8List.fromList(pb.groupHandshake)
          : null,
      groupControl: pb.hasGroupControl()
          ? Uint8List.fromList(pb.groupControl)
          : null,
      ohUpdate: pb.hasOhUpdate() ? Uint8List.fromList(pb.ohUpdate) : null,
    );
  }

  static bool _isSet(Uint8List? field) => field != null && field.isNotEmpty;
}
