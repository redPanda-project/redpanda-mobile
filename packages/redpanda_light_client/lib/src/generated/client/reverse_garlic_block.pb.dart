// This is a generated file - do not edit.
//
// Generated from client/reverse_garlic_block.proto.

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

/// MS05 reply-path descriptor (Frontend-MS05, backend Decision 6).
class ReverseGarlicBlock extends $pb.GeneratedMessage {
  factory ReverseGarlicBlock({
    $core.int? version,
    $fixnum.Int64? expiryTs,
    $core.List<$core.int>? sessionTag,
    $core.List<$core.int>? ohId,
    $core.Iterable<RgbHop>? hops,
  }) {
    final result = ReverseGarlicBlock._();
    if (version != null) result.version = version;
    if (expiryTs != null) result.expiryTs = expiryTs;
    if (sessionTag != null) result.sessionTag = sessionTag;
    if (ohId != null) result.ohId = ohId;
    if (hops != null) result.hops.addAll(hops);
    return result;
  }

  ReverseGarlicBlock._();

  factory ReverseGarlicBlock.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReverseGarlicBlock()..mergeFromBuffer(data, registry);
  factory ReverseGarlicBlock.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReverseGarlicBlock()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReverseGarlicBlock',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: ReverseGarlicBlock.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aInt64(2, _omitFieldNames ? '' : 'expiryTs')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'sessionTag', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..pPM<RgbHop>(5, _omitFieldNames ? '' : 'hops',
        subBuilder: RgbHop.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReverseGarlicBlock clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReverseGarlicBlock copyWith(void Function(ReverseGarlicBlock) updates) =>
      super.copyWith((message) => updates(message as ReverseGarlicBlock))
          as ReverseGarlicBlock;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReverseGarlicBlock() / ReverseGarlicBlock.new instead')
  static ReverseGarlicBlock create() => ReverseGarlicBlock._();
  static $pb.GeneratedMessage $_createMessage() => ReverseGarlicBlock._();
  @$core.override
  ReverseGarlicBlock createEmptyInstance() => ReverseGarlicBlock._();
  @$core.pragma('dart2js:noInline')
  static ReverseGarlicBlock getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReverseGarlicBlock>(
          ReverseGarlicBlock.$_createMessage);
  static ReverseGarlicBlock? _defaultInstance;

  /// `optional` (explicit presence) because the original encoder always
  /// writes fields 1 and 2, even when the value is 0; plain proto3 scalars
  /// would drop a 0 and change the bytes.
  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get expiryTs => $_getI64(1);
  @$pb.TagNumber(2)
  set expiryTs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExpiryTs() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiryTs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get sessionTag => $_getN(2);
  @$pb.TagNumber(3)
  set sessionTag($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessionTag() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionTag() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ohId => $_getN(3);
  @$pb.TagNumber(4)
  set ohId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOhId() => $_has(3);
  @$pb.TagNumber(4)
  void clearOhId() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<RgbHop> get hops => $_getList(4);
}

class RgbHop extends $pb.GeneratedMessage {
  factory RgbHop({
    $core.List<$core.int>? kadId,
    $core.List<$core.int>? encPub,
  }) {
    final result = RgbHop._();
    if (kadId != null) result.kadId = kadId;
    if (encPub != null) result.encPub = encPub;
    return result;
  }

  RgbHop._();

  factory RgbHop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RgbHop()..mergeFromBuffer(data, registry);
  factory RgbHop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RgbHop()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RgbHop',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: RgbHop.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'kadId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'encPub', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RgbHop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RgbHop copyWith(void Function(RgbHop) updates) =>
      super.copyWith((message) => updates(message as RgbHop)) as RgbHop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RgbHop() / RgbHop.new instead')
  static RgbHop create() => RgbHop._();
  static $pb.GeneratedMessage $_createMessage() => RgbHop._();
  @$core.override
  RgbHop createEmptyInstance() => RgbHop._();
  @$core.pragma('dart2js:noInline')
  static RgbHop getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RgbHop>(RgbHop.$_createMessage);
  static RgbHop? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get kadId => $_getN(0);
  @$pb.TagNumber(1)
  set kadId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKadId() => $_has(0);
  @$pb.TagNumber(1)
  void clearKadId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get encPub => $_getN(1);
  @$pb.TagNumber(2)
  set encPub($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEncPub() => $_has(1);
  @$pb.TagNumber(2)
  void clearEncPub() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
