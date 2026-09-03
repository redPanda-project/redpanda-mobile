// This is a generated file - do not edit.
//
// Generated from outbound.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'outbound.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'outbound.pbenum.dart';

/// MS03 signing-byte format (master spec §8) for all signed outbound commands:
///   v2 (current):  signature = Ed25519 (64 bytes) over [0x02 | CMD_BYTE | fields | timestamp | nonce]
///                  oh_auth_public_key = 32-byte Ed25519 verify key
///   v1 (legacy):   signature = DER ECDSA (brainpool) over [CMD_BYTE | fields | timestamp | nonce]
///                  oh_auth_public_key = 65-byte brainpool key — deprecated; still accepted during
///                  the transition phase and removed once protocol-v22 support is dropped
class RegisterOhRequest extends $pb.GeneratedMessage {
  factory RegisterOhRequest({
    $core.List<$core.int>? ohId,
    $core.List<$core.int>? ohAuthPublicKey,
    $fixnum.Int64? requestedExpiresAt,
    $fixnum.Int64? timestampMs,
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (ohId != null) result.ohId = ohId;
    if (ohAuthPublicKey != null) result.ohAuthPublicKey = ohAuthPublicKey;
    if (requestedExpiresAt != null)
      result.requestedExpiresAt = requestedExpiresAt;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (nonce != null) result.nonce = nonce;
    if (signature != null) result.signature = signature;
    return result;
  }

  RegisterOhRequest._();

  factory RegisterOhRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterOhRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterOhRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ohAuthPublicKey', $pb.PbFieldType.OY)
    ..aInt64(3, _omitFieldNames ? '' : 'requestedExpiresAt')
    ..aInt64(4, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterOhRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterOhRequest copyWith(void Function(RegisterOhRequest) updates) =>
      super.copyWith((message) => updates(message as RegisterOhRequest))
          as RegisterOhRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterOhRequest create() => RegisterOhRequest._();
  @$core.override
  RegisterOhRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterOhRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterOhRequest>(create);
  static RegisterOhRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOhId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOhId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ohAuthPublicKey => $_getN(1);
  @$pb.TagNumber(2)
  set ohAuthPublicKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOhAuthPublicKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearOhAuthPublicKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get requestedExpiresAt => $_getI64(2);
  @$pb.TagNumber(3)
  set requestedExpiresAt($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestedExpiresAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestedExpiresAt() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimestampMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get nonce => $_getN(4);
  @$pb.TagNumber(5)
  set nonce($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNonce() => $_has(4);
  @$pb.TagNumber(5)
  void clearNonce() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get signature => $_getN(5);
  @$pb.TagNumber(6)
  set signature($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSignature() => $_has(5);
  @$pb.TagNumber(6)
  void clearSignature() => $_clearField(6);
}

class RegisterOhResponse extends $pb.GeneratedMessage {
  factory RegisterOhResponse({
    Status? status,
    $fixnum.Int64? serverTimeMs,
    $fixnum.Int64? expiresAtMs,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (serverTimeMs != null) result.serverTimeMs = serverTimeMs;
    if (expiresAtMs != null) result.expiresAtMs = expiresAtMs;
    return result;
  }

  RegisterOhResponse._();

  factory RegisterOhResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterOhResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterOhResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..aE<Status>(1, _omitFieldNames ? '' : 'status', enumValues: Status.values)
    ..aInt64(2, _omitFieldNames ? '' : 'serverTimeMs')
    ..aInt64(3, _omitFieldNames ? '' : 'expiresAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterOhResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterOhResponse copyWith(void Function(RegisterOhResponse) updates) =>
      super.copyWith((message) => updates(message as RegisterOhResponse))
          as RegisterOhResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterOhResponse create() => RegisterOhResponse._();
  @$core.override
  RegisterOhResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterOhResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterOhResponse>(create);
  static RegisterOhResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerTimeMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expiresAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set expiresAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpiresAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpiresAtMs() => $_clearField(3);
}

class FetchRequest extends $pb.GeneratedMessage {
  factory FetchRequest({
    $core.List<$core.int>? ohId,
    $core.int? limit,
    $fixnum.Int64? cursor,
    $fixnum.Int64? timestampMs,
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (ohId != null) result.ohId = ohId;
    if (limit != null) result.limit = limit;
    if (cursor != null) result.cursor = cursor;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (nonce != null) result.nonce = nonce;
    if (signature != null) result.signature = signature;
    return result;
  }

  FetchRequest._();

  factory FetchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FetchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FetchRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'cursor', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(4, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FetchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FetchRequest copyWith(void Function(FetchRequest) updates) =>
      super.copyWith((message) => updates(message as FetchRequest))
          as FetchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FetchRequest create() => FetchRequest._();
  @$core.override
  FetchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FetchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FetchRequest>(create);
  static FetchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOhId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOhId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get cursor => $_getI64(2);
  @$pb.TagNumber(3)
  set cursor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCursor() => $_has(2);
  @$pb.TagNumber(3)
  void clearCursor() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimestampMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get nonce => $_getN(4);
  @$pb.TagNumber(5)
  set nonce($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNonce() => $_has(4);
  @$pb.TagNumber(5)
  void clearNonce() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get signature => $_getN(5);
  @$pb.TagNumber(6)
  set signature($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSignature() => $_has(5);
  @$pb.TagNumber(6)
  void clearSignature() => $_clearField(6);
}

class MailItem extends $pb.GeneratedMessage {
  factory MailItem({
    $core.List<$core.int>? messageId,
    $fixnum.Int64? receivedAtMs,
    $core.List<$core.int>? payload,
    $fixnum.Int64? sequenceId,
    $core.List<$core.int>? sessionTag,
  }) {
    final result = create();
    if (messageId != null) result.messageId = messageId;
    if (receivedAtMs != null) result.receivedAtMs = receivedAtMs;
    if (payload != null) result.payload = payload;
    if (sequenceId != null) result.sequenceId = sequenceId;
    if (sessionTag != null) result.sessionTag = sessionTag;
    return result;
  }

  MailItem._();

  factory MailItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MailItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MailItem',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'receivedAtMs')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'sequenceId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'sessionTag', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MailItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MailItem copyWith(void Function(MailItem) updates) =>
      super.copyWith((message) => updates(message as MailItem)) as MailItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MailItem create() => MailItem._();
  @$core.override
  MailItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MailItem getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MailItem>(create);
  static MailItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get receivedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set receivedAtMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReceivedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearReceivedAtMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get payload => $_getN(2);
  @$pb.TagNumber(3)
  set payload($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPayload() => $_has(2);
  @$pb.TagNumber(3)
  void clearPayload() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sequenceId => $_getI64(3);
  @$pb.TagNumber(4)
  set sequenceId($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSequenceId() => $_has(3);
  @$pb.TagNumber(4)
  void clearSequenceId() => $_clearField(4);

  /// MS05: 16-byte session tag from a reverse-garlic reply (CMD_DELIVER_TAGGED), letting the
  /// client correlate the reply with a conversation. Empty for direct messages and untagged
  /// garlic delivers (backward compatible).
  @$pb.TagNumber(5)
  $core.List<$core.int> get sessionTag => $_getN(4);
  @$pb.TagNumber(5)
  set sessionTag($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSessionTag() => $_has(4);
  @$pb.TagNumber(5)
  void clearSessionTag() => $_clearField(5);
}

class FetchResponse extends $pb.GeneratedMessage {
  factory FetchResponse({
    Status? status,
    $fixnum.Int64? nextCursor,
    $core.Iterable<MailItem>? items,
    $fixnum.Int64? serverTimeMs,
    $core.bool? mailboxOverflow,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (nextCursor != null) result.nextCursor = nextCursor;
    if (items != null) result.items.addAll(items);
    if (serverTimeMs != null) result.serverTimeMs = serverTimeMs;
    if (mailboxOverflow != null) result.mailboxOverflow = mailboxOverflow;
    return result;
  }

  FetchResponse._();

  factory FetchResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FetchResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FetchResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..aE<Status>(1, _omitFieldNames ? '' : 'status', enumValues: Status.values)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'nextCursor', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<MailItem>(3, _omitFieldNames ? '' : 'items',
        subBuilder: MailItem.create)
    ..aInt64(4, _omitFieldNames ? '' : 'serverTimeMs')
    ..aOB(5, _omitFieldNames ? '' : 'mailboxOverflow')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FetchResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FetchResponse copyWith(void Function(FetchResponse) updates) =>
      super.copyWith((message) => updates(message as FetchResponse))
          as FetchResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FetchResponse create() => FetchResponse._();
  @$core.override
  FetchResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FetchResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FetchResponse>(create);
  static FetchResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get nextCursor => $_getI64(1);
  @$pb.TagNumber(2)
  set nextCursor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNextCursor() => $_has(1);
  @$pb.TagNumber(2)
  void clearNextCursor() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<MailItem> get items => $_getList(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get serverTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasServerTimeMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearServerTimeMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get mailboxOverflow => $_getBF(4);
  @$pb.TagNumber(5)
  set mailboxOverflow($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMailboxOverflow() => $_has(4);
  @$pb.TagNumber(5)
  void clearMailboxOverflow() => $_clearField(5);
}

class AckFetchRequest extends $pb.GeneratedMessage {
  factory AckFetchRequest({
    $core.List<$core.int>? ohId,
    $fixnum.Int64? ackedSequenceId,
    $fixnum.Int64? timestampMs,
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (ohId != null) result.ohId = ohId;
    if (ackedSequenceId != null) result.ackedSequenceId = ackedSequenceId;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (nonce != null) result.nonce = nonce;
    if (signature != null) result.signature = signature;
    return result;
  }

  AckFetchRequest._();

  factory AckFetchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AckFetchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AckFetchRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'ackedSequenceId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckFetchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckFetchRequest copyWith(void Function(AckFetchRequest) updates) =>
      super.copyWith((message) => updates(message as AckFetchRequest))
          as AckFetchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AckFetchRequest create() => AckFetchRequest._();
  @$core.override
  AckFetchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AckFetchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AckFetchRequest>(create);
  static AckFetchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOhId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOhId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get ackedSequenceId => $_getI64(1);
  @$pb.TagNumber(2)
  set ackedSequenceId($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAckedSequenceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAckedSequenceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get nonce => $_getN(3);
  @$pb.TagNumber(4)
  set nonce($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNonce() => $_has(3);
  @$pb.TagNumber(4)
  void clearNonce() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get signature => $_getN(4);
  @$pb.TagNumber(5)
  set signature($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSignature() => $_has(4);
  @$pb.TagNumber(5)
  void clearSignature() => $_clearField(5);
}

class AckFetchResponse extends $pb.GeneratedMessage {
  factory AckFetchResponse({
    Status? status,
    $fixnum.Int64? serverTimeMs,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (serverTimeMs != null) result.serverTimeMs = serverTimeMs;
    return result;
  }

  AckFetchResponse._();

  factory AckFetchResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AckFetchResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AckFetchResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..aE<Status>(1, _omitFieldNames ? '' : 'status', enumValues: Status.values)
    ..aInt64(2, _omitFieldNames ? '' : 'serverTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckFetchResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckFetchResponse copyWith(void Function(AckFetchResponse) updates) =>
      super.copyWith((message) => updates(message as AckFetchResponse))
          as AckFetchResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AckFetchResponse create() => AckFetchResponse._();
  @$core.override
  AckFetchResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AckFetchResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AckFetchResponse>(create);
  static AckFetchResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerTimeMs() => $_clearField(2);
}

/// MS02b: optional response to a FlaschenpostPut deposit (command 158). Only sent to light
/// clients that set FlaschenpostPut.want_response, so existing clients never see it.
///   OK             — deposited into a locally registered OH, or accepted for best-effort
///                    forwarding toward the OH host node (MS02b)
///   NOT_FOUND      — oh_id not registered here and forwarding not possible (hop limit)
///   QUOTA_EXCEEDED — mailbox full (item cap or byte quota); deposit rejected, nothing displaced
///   BAD_REQUEST    — item exceeds the per-item size limit
class FlaschenpostPutResponse extends $pb.GeneratedMessage {
  factory FlaschenpostPutResponse({
    Status? status,
    $fixnum.Int64? serverTimeMs,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (serverTimeMs != null) result.serverTimeMs = serverTimeMs;
    return result;
  }

  FlaschenpostPutResponse._();

  factory FlaschenpostPutResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FlaschenpostPutResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FlaschenpostPutResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..aE<Status>(1, _omitFieldNames ? '' : 'status', enumValues: Status.values)
    ..aInt64(2, _omitFieldNames ? '' : 'serverTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FlaschenpostPutResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FlaschenpostPutResponse copyWith(
          void Function(FlaschenpostPutResponse) updates) =>
      super.copyWith((message) => updates(message as FlaschenpostPutResponse))
          as FlaschenpostPutResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FlaschenpostPutResponse create() => FlaschenpostPutResponse._();
  @$core.override
  FlaschenpostPutResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FlaschenpostPutResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FlaschenpostPutResponse>(create);
  static FlaschenpostPutResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerTimeMs() => $_clearField(2);
}

/// MS02b: DHT announce record mapping an OH to its host node. Stored as KadContent signed by a
/// keypair deterministically derived from the oh_id (domain tag "redpanda.oh.announce.v1"), so
/// anyone who knows the oh_id can compute the lookup key — and only they can. The serialized
/// record is padded to a fixed size so record size does not reveal which OH is announced.
class OhNodeRecord extends $pb.GeneratedMessage {
  factory OhNodeRecord({
    $core.List<$core.int>? ohIdHash,
    $core.List<$core.int>? nodeId,
    $core.String? endpoint,
    $fixnum.Int64? announcedAtMs,
    $core.List<$core.int>? padding,
  }) {
    final result = create();
    if (ohIdHash != null) result.ohIdHash = ohIdHash;
    if (nodeId != null) result.nodeId = nodeId;
    if (endpoint != null) result.endpoint = endpoint;
    if (announcedAtMs != null) result.announcedAtMs = announcedAtMs;
    if (padding != null) result.padding = padding;
    return result;
  }

  OhNodeRecord._();

  factory OhNodeRecord.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OhNodeRecord.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OhNodeRecord',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohIdHash', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'endpoint')
    ..aInt64(4, _omitFieldNames ? '' : 'announcedAtMs')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'padding', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OhNodeRecord clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OhNodeRecord copyWith(void Function(OhNodeRecord) updates) =>
      super.copyWith((message) => updates(message as OhNodeRecord))
          as OhNodeRecord;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OhNodeRecord create() => OhNodeRecord._();
  @$core.override
  OhNodeRecord createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OhNodeRecord getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OhNodeRecord>(create);
  static OhNodeRecord? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohIdHash => $_getN(0);
  @$pb.TagNumber(1)
  set ohIdHash($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOhIdHash() => $_has(0);
  @$pb.TagNumber(1)
  void clearOhIdHash() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get nodeId => $_getN(1);
  @$pb.TagNumber(2)
  set nodeId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearNodeId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get endpoint => $_getSZ(2);
  @$pb.TagNumber(3)
  set endpoint($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEndpoint() => $_has(2);
  @$pb.TagNumber(3)
  void clearEndpoint() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get announcedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set announcedAtMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAnnouncedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearAnnouncedAtMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get padding => $_getN(4);
  @$pb.TagNumber(5)
  set padding($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPadding() => $_has(4);
  @$pb.TagNumber(5)
  void clearPadding() => $_clearField(5);
}

/// MS06: R-ACK (routing acknowledgment) payload. Generated by the node that makes the final
/// deposit decision for a CMD_DELIVER_ACKED garlic deliver and sent back through the
/// sender-chosen return-path hops as a standard MS04 onion, innermost layer =
/// CMD_DELIVER_TAGGED into the sender's own OH mailbox. The sender correlates the R-ACK with
/// its message via the ack session tag on the MailItem (chosen by the sender per message) —
/// deliberately no message_id field: the mailbox UUID is server-generated at deposit time and
/// meaningless to the sender. R-ACKs are a routing hint, not proof of delivery: the final
/// return-path hop and the OH host could forge or drop them (accepted, see milestone spec).
class RoutingAck extends $pb.GeneratedMessage {
  factory RoutingAck({
    $fixnum.Int64? timestampMs,
    $core.int? status,
  }) {
    final result = create();
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (status != null) result.status = status;
    return result;
  }

  RoutingAck._();

  factory RoutingAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RoutingAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RoutingAck',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'timestampMs')
    ..aI(2, _omitFieldNames ? '' : 'status', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RoutingAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RoutingAck copyWith(void Function(RoutingAck) updates) =>
      super.copyWith((message) => updates(message as RoutingAck)) as RoutingAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RoutingAck create() => RoutingAck._();
  @$core.override
  RoutingAck createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RoutingAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RoutingAck>(create);
  static RoutingAck? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get timestampMs => $_getI64(0);
  @$pb.TagNumber(1)
  set timestampMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestampMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestampMs() => $_clearField(1);

  /// 0 = stored, 1 = mailbox_full (quota), 2 = handle_expired (OH unknown/expired at the final
  /// station), 3 = rejected (bad request, e.g. oversized payload). Always set explicitly.
  @$pb.TagNumber(2)
  $core.int get status => $_getIZ(1);
  @$pb.TagNumber(2)
  set status($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);
}

class RevokeOhRequest extends $pb.GeneratedMessage {
  factory RevokeOhRequest({
    $core.List<$core.int>? ohId,
    $fixnum.Int64? timestampMs,
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (ohId != null) result.ohId = ohId;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (nonce != null) result.nonce = nonce;
    if (signature != null) result.signature = signature;
    return result;
  }

  RevokeOhRequest._();

  factory RevokeOhRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeOhRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeOhRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeOhRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeOhRequest copyWith(void Function(RevokeOhRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeOhRequest))
          as RevokeOhRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeOhRequest create() => RevokeOhRequest._();
  @$core.override
  RevokeOhRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeOhRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeOhRequest>(create);
  static RevokeOhRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOhId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOhId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nonce => $_getN(2);
  @$pb.TagNumber(3)
  set nonce($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNonce() => $_has(2);
  @$pb.TagNumber(3)
  void clearNonce() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get signature => $_getN(3);
  @$pb.TagNumber(4)
  set signature($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSignature() => $_has(3);
  @$pb.TagNumber(4)
  void clearSignature() => $_clearField(4);
}

class RevokeOhResponse extends $pb.GeneratedMessage {
  factory RevokeOhResponse({
    Status? status,
    $fixnum.Int64? serverTimeMs,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (serverTimeMs != null) result.serverTimeMs = serverTimeMs;
    return result;
  }

  RevokeOhResponse._();

  factory RevokeOhResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeOhResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeOhResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..aE<Status>(1, _omitFieldNames ? '' : 'status', enumValues: Status.values)
    ..aInt64(2, _omitFieldNames ? '' : 'serverTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeOhResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeOhResponse copyWith(void Function(RevokeOhResponse) updates) =>
      super.copyWith((message) => updates(message as RevokeOhResponse))
          as RevokeOhResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeOhResponse create() => RevokeOhResponse._();
  @$core.override
  RevokeOhResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeOhResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeOhResponse>(create);
  static RevokeOhResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerTimeMs() => $_clearField(2);
}

/// Connection-Notify (T38): opt-in real-time "new mail" signal over the existing peer connection.
/// Subscribe proves OH ownership exactly like FetchRequest — Ed25519 signature verified against the
/// oh_auth_public_key stored at register, same OutboundAuth timestamp/replay handling. The node then
/// binds oh_id → this peer connection (in-memory only, dropped on disconnect). On every successful
/// deposit into a subscribed mailbox the node sends a one-way Notify carrying only the oh_id; the
/// client reacts with a normal signed FetchRequest (cursor/ack/dedup/decrypt unchanged).
///   Signing bytes: [CMD_BYTE=159 | oh_id | timestamp_ms(8) | nonce]  (0x02 version prefix applied
///   by OutboundAuth, like every signed outbound command).
class SubscribeRequest extends $pb.GeneratedMessage {
  factory SubscribeRequest({
    $core.List<$core.int>? ohId,
    $fixnum.Int64? timestampMs,
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (ohId != null) result.ohId = ohId;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (nonce != null) result.nonce = nonce;
    if (signature != null) result.signature = signature;
    return result;
  }

  SubscribeRequest._();

  factory SubscribeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SubscribeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SubscribeRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeRequest copyWith(void Function(SubscribeRequest) updates) =>
      super.copyWith((message) => updates(message as SubscribeRequest))
          as SubscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SubscribeRequest create() => SubscribeRequest._();
  @$core.override
  SubscribeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SubscribeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SubscribeRequest>(create);
  static SubscribeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOhId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOhId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nonce => $_getN(2);
  @$pb.TagNumber(3)
  set nonce($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNonce() => $_has(2);
  @$pb.TagNumber(3)
  void clearNonce() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get signature => $_getN(3);
  @$pb.TagNumber(4)
  set signature($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSignature() => $_has(3);
  @$pb.TagNumber(4)
  void clearSignature() => $_clearField(4);
}

class SubscribeResponse extends $pb.GeneratedMessage {
  factory SubscribeResponse({
    Status? status,
    $fixnum.Int64? serverTimeMs,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (serverTimeMs != null) result.serverTimeMs = serverTimeMs;
    return result;
  }

  SubscribeResponse._();

  factory SubscribeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SubscribeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SubscribeResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..aE<Status>(1, _omitFieldNames ? '' : 'status', enumValues: Status.values)
    ..aInt64(2, _omitFieldNames ? '' : 'serverTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeResponse copyWith(void Function(SubscribeResponse) updates) =>
      super.copyWith((message) => updates(message as SubscribeResponse))
          as SubscribeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SubscribeResponse create() => SubscribeResponse._();
  @$core.override
  SubscribeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SubscribeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SubscribeResponse>(create);
  static SubscribeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerTimeMs() => $_clearField(2);
}

/// One-way node → client (command 161). Carries ONLY the oh_id — no payload, no metadata, no
/// sequence id: the client already has a fully signed fetch path and uses it to learn what changed.
class Notify extends $pb.GeneratedMessage {
  factory Notify({
    $core.List<$core.int>? ohId,
  }) {
    final result = create();
    if (ohId != null) result.ohId = ohId;
    return result;
  }

  Notify._();

  factory Notify.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Notify.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Notify',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.outbound.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Notify clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Notify copyWith(void Function(Notify) updates) =>
      super.copyWith((message) => updates(message as Notify)) as Notify;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Notify create() => Notify._();
  @$core.override
  Notify createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Notify getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Notify>(create);
  static Notify? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOhId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOhId() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
