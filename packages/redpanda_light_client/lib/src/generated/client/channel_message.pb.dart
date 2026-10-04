// This is a generated file - do not edit.
//
// Generated from client/channel_message.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The inner plaintext of a channel message (MS03 message-format-v2).
/// Field 4 has never been used.
class ChannelMessage extends $pb.GeneratedMessage {
  factory ChannelMessage({
    $core.List<$core.int>? messageId,
    $fixnum.Int64? timestampMs,
    $core.String? content,
    $core.List<$core.int>? replyPath,
    $core.List<$core.int>? ackMessageId,
    $core.List<$core.int>? groupHandshake,
    $core.List<$core.int>? groupControl,
    $core.List<$core.int>? ohUpdate,
  }) {
    final result = ChannelMessage._();
    if (messageId != null) result.messageId = messageId;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (content != null) result.content = content;
    if (replyPath != null) result.replyPath = replyPath;
    if (ackMessageId != null) result.ackMessageId = ackMessageId;
    if (groupHandshake != null) result.groupHandshake = groupHandshake;
    if (groupControl != null) result.groupControl = groupControl;
    if (ohUpdate != null) result.ohUpdate = ohUpdate;
    return result;
  }

  ChannelMessage._();

  factory ChannelMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChannelMessage()..mergeFromBuffer(data, registry);
  factory ChannelMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChannelMessage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelMessage',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: ChannelMessage.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..aOS(3, _omitFieldNames ? '' : 'content')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'replyPath', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'ackMessageId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'groupHandshake', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        8, _omitFieldNames ? '' : 'groupControl', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        9, _omitFieldNames ? '' : 'ohUpdate', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMessage copyWith(void Function(ChannelMessage) updates) =>
      super.copyWith((message) => updates(message as ChannelMessage))
          as ChannelMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChannelMessage() / ChannelMessage.new instead')
  static ChannelMessage create() => ChannelMessage._();
  static $pb.GeneratedMessage $_createMessage() => ChannelMessage._();
  @$core.override
  ChannelMessage createEmptyInstance() => ChannelMessage._();
  @$core.pragma('dart2js:noInline')
  static ChannelMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelMessage>(
          ChannelMessage.$_createMessage);
  static ChannelMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get content => $_getSZ(2);
  @$pb.TagNumber(3)
  set content($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContent() => $_has(2);
  @$pb.TagNumber(3)
  void clearContent() => $_clearField(3);

  @$pb.TagNumber(5)
  $core.List<$core.int> get replyPath => $_getN(3);
  @$pb.TagNumber(5)
  set replyPath($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(5)
  $core.bool hasReplyPath() => $_has(3);
  @$pb.TagNumber(5)
  void clearReplyPath() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get ackMessageId => $_getN(4);
  @$pb.TagNumber(6)
  set ackMessageId($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(6)
  $core.bool hasAckMessageId() => $_has(4);
  @$pb.TagNumber(6)
  void clearAckMessageId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get groupHandshake => $_getN(5);
  @$pb.TagNumber(7)
  set groupHandshake($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(7)
  $core.bool hasGroupHandshake() => $_has(5);
  @$pb.TagNumber(7)
  void clearGroupHandshake() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get groupControl => $_getN(6);
  @$pb.TagNumber(8)
  set groupControl($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(8)
  $core.bool hasGroupControl() => $_has(6);
  @$pb.TagNumber(8)
  void clearGroupControl() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get ohUpdate => $_getN(7);
  @$pb.TagNumber(9)
  set ohUpdate($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(9)
  $core.bool hasOhUpdate() => $_has(7);
  @$pb.TagNumber(9)
  void clearOhUpdate() => $_clearField(9);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
