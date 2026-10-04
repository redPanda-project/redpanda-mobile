// This is a generated file - do not edit.
//
// Generated from client/group_control.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GroupMember extends $pb.GeneratedMessage {
  factory GroupMember({
    $core.List<$core.int>? memberId,
    $core.String? displayName,
    $core.List<$core.int>? ohId,
    $core.String? ohEndpoint,
    $core.List<$core.int>? x25519Pub,
    $core.int? role,
  }) {
    final result = GroupMember._();
    if (memberId != null) result.memberId = memberId;
    if (displayName != null) result.displayName = displayName;
    if (ohId != null) result.ohId = ohId;
    if (ohEndpoint != null) result.ohEndpoint = ohEndpoint;
    if (x25519Pub != null) result.x25519Pub = x25519Pub;
    if (role != null) result.role = role;
    return result;
  }

  GroupMember._();

  factory GroupMember.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupMember()..mergeFromBuffer(data, registry);
  factory GroupMember.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupMember()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GroupMember',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: GroupMember.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'memberId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'ohEndpoint')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'x25519Pub', $pb.PbFieldType.OY)
    ..aI(6, _omitFieldNames ? '' : 'role', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupMember clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupMember copyWith(void Function(GroupMember) updates) =>
      super.copyWith((message) => updates(message as GroupMember))
          as GroupMember;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GroupMember() / GroupMember.new instead')
  static GroupMember create() => GroupMember._();
  static $pb.GeneratedMessage $_createMessage() => GroupMember._();
  @$core.override
  GroupMember createEmptyInstance() => GroupMember._();
  @$core.pragma('dart2js:noInline')
  static GroupMember getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupMember>(
          GroupMember.$_createMessage);
  static GroupMember? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get memberId => $_getN(0);
  @$pb.TagNumber(1)
  set memberId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMemberId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMemberId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ohId => $_getN(2);
  @$pb.TagNumber(3)
  set ohId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOhId() => $_has(2);
  @$pb.TagNumber(3)
  void clearOhId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get ohEndpoint => $_getSZ(3);
  @$pb.TagNumber(4)
  set ohEndpoint($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOhEndpoint() => $_has(3);
  @$pb.TagNumber(4)
  void clearOhEndpoint() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get x25519Pub => $_getN(4);
  @$pb.TagNumber(5)
  set x25519Pub($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasX25519Pub() => $_has(4);
  @$pb.TagNumber(5)
  void clearX25519Pub() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get role => $_getIZ(5);
  @$pb.TagNumber(6)
  set role($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRole() => $_has(5);
  @$pb.TagNumber(6)
  void clearRole() => $_clearField(6);
}

enum GroupControl_Action { keyRotation, infoUpdate, notSet }

class GroupControl extends $pb.GeneratedMessage {
  factory GroupControl({
    KeyRotation? keyRotation,
    GroupInfoUpdate? infoUpdate,
  }) {
    final result = GroupControl._();
    if (keyRotation != null) result.keyRotation = keyRotation;
    if (infoUpdate != null) result.infoUpdate = infoUpdate;
    return result;
  }

  GroupControl._();

  factory GroupControl.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupControl()..mergeFromBuffer(data, registry);
  factory GroupControl.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupControl()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, GroupControl_Action>
      _GroupControl_ActionByTag = {
    1: GroupControl_Action.keyRotation,
    2: GroupControl_Action.infoUpdate,
    0: GroupControl_Action.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GroupControl',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: GroupControl.$_createMessage)
    ..oo(0, [1, 2])
    ..aOM<KeyRotation>(1, _omitFieldNames ? '' : 'keyRotation',
        subBuilder: KeyRotation.$_createMessage)
    ..aOM<GroupInfoUpdate>(2, _omitFieldNames ? '' : 'infoUpdate',
        subBuilder: GroupInfoUpdate.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupControl clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupControl copyWith(void Function(GroupControl) updates) =>
      super.copyWith((message) => updates(message as GroupControl))
          as GroupControl;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GroupControl() / GroupControl.new instead')
  static GroupControl create() => GroupControl._();
  static $pb.GeneratedMessage $_createMessage() => GroupControl._();
  @$core.override
  GroupControl createEmptyInstance() => GroupControl._();
  @$core.pragma('dart2js:noInline')
  static GroupControl getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupControl>(
          GroupControl.$_createMessage);
  static GroupControl? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  GroupControl_Action whichAction() =>
      _GroupControl_ActionByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearAction() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  KeyRotation get keyRotation => $_getN(0);
  @$pb.TagNumber(1)
  set keyRotation(KeyRotation value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKeyRotation() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeyRotation() => $_clearField(1);
  @$pb.TagNumber(1)
  KeyRotation ensureKeyRotation() => $_ensure(0);

  @$pb.TagNumber(2)
  GroupInfoUpdate get infoUpdate => $_getN(1);
  @$pb.TagNumber(2)
  set infoUpdate(GroupInfoUpdate value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasInfoUpdate() => $_has(1);
  @$pb.TagNumber(2)
  void clearInfoUpdate() => $_clearField(2);
  @$pb.TagNumber(2)
  GroupInfoUpdate ensureInfoUpdate() => $_ensure(1);
}

/// Distributes a new epoch secret plus the authoritative member list
/// (Decisions 3/6/12).
class KeyRotation extends $pb.GeneratedMessage {
  factory KeyRotation({
    $core.List<$core.int>? groupSecret,
    $core.int? keyEpoch,
    $core.Iterable<GroupMember>? members,
    $core.String? groupName,
  }) {
    final result = KeyRotation._();
    if (groupSecret != null) result.groupSecret = groupSecret;
    if (keyEpoch != null) result.keyEpoch = keyEpoch;
    if (members != null) result.members.addAll(members);
    if (groupName != null) result.groupName = groupName;
    return result;
  }

  KeyRotation._();

  factory KeyRotation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeyRotation()..mergeFromBuffer(data, registry);
  factory KeyRotation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeyRotation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KeyRotation',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: KeyRotation.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'groupSecret', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'keyEpoch', fieldType: $pb.PbFieldType.OU3)
    ..pPM<GroupMember>(3, _omitFieldNames ? '' : 'members',
        subBuilder: GroupMember.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'groupName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyRotation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyRotation copyWith(void Function(KeyRotation) updates) =>
      super.copyWith((message) => updates(message as KeyRotation))
          as KeyRotation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use KeyRotation() / KeyRotation.new instead')
  static KeyRotation create() => KeyRotation._();
  static $pb.GeneratedMessage $_createMessage() => KeyRotation._();
  @$core.override
  KeyRotation createEmptyInstance() => KeyRotation._();
  @$core.pragma('dart2js:noInline')
  static KeyRotation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KeyRotation>(
          KeyRotation.$_createMessage);
  static KeyRotation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupSecret => $_getN(0);
  @$pb.TagNumber(1)
  set groupSecret($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGroupSecret() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupSecret() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get keyEpoch => $_getIZ(1);
  @$pb.TagNumber(2)
  set keyEpoch($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKeyEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyEpoch() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<GroupMember> get members => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get groupName => $_getSZ(3);
  @$pb.TagNumber(4)
  set groupName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasGroupName() => $_has(3);
  @$pb.TagNumber(4)
  void clearGroupName() => $_clearField(4);
}

/// Rename broadcast (admin only).
class GroupInfoUpdate extends $pb.GeneratedMessage {
  factory GroupInfoUpdate({
    $core.String? name,
  }) {
    final result = GroupInfoUpdate._();
    if (name != null) result.name = name;
    return result;
  }

  GroupInfoUpdate._();

  factory GroupInfoUpdate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupInfoUpdate()..mergeFromBuffer(data, registry);
  factory GroupInfoUpdate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupInfoUpdate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GroupInfoUpdate',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: GroupInfoUpdate.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupInfoUpdate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupInfoUpdate copyWith(void Function(GroupInfoUpdate) updates) =>
      super.copyWith((message) => updates(message as GroupInfoUpdate))
          as GroupInfoUpdate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GroupInfoUpdate() / GroupInfoUpdate.new instead')
  static GroupInfoUpdate create() => GroupInfoUpdate._();
  static $pb.GeneratedMessage $_createMessage() => GroupInfoUpdate._();
  @$core.override
  GroupInfoUpdate createEmptyInstance() => GroupInfoUpdate._();
  @$core.pragma('dart2js:noInline')
  static GroupInfoUpdate getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupInfoUpdate>(
          GroupInfoUpdate.$_createMessage);
  static GroupInfoUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);
}

enum GroupHandshake_Kind { proposal, accept, notSet }

/// Two-way join handshake over an existing 1:1 channel (Decision 8).
class GroupHandshake extends $pb.GeneratedMessage {
  factory GroupHandshake({
    InviteProposal? proposal,
    JoinAccept? accept,
  }) {
    final result = GroupHandshake._();
    if (proposal != null) result.proposal = proposal;
    if (accept != null) result.accept = accept;
    return result;
  }

  GroupHandshake._();

  factory GroupHandshake.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupHandshake()..mergeFromBuffer(data, registry);
  factory GroupHandshake.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GroupHandshake()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, GroupHandshake_Kind>
      _GroupHandshake_KindByTag = {
    1: GroupHandshake_Kind.proposal,
    2: GroupHandshake_Kind.accept,
    0: GroupHandshake_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GroupHandshake',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: GroupHandshake.$_createMessage)
    ..oo(0, [1, 2])
    ..aOM<InviteProposal>(1, _omitFieldNames ? '' : 'proposal',
        subBuilder: InviteProposal.$_createMessage)
    ..aOM<JoinAccept>(2, _omitFieldNames ? '' : 'accept',
        subBuilder: JoinAccept.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupHandshake clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GroupHandshake copyWith(void Function(GroupHandshake) updates) =>
      super.copyWith((message) => updates(message as GroupHandshake))
          as GroupHandshake;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GroupHandshake() / GroupHandshake.new instead')
  static GroupHandshake create() => GroupHandshake._();
  static $pb.GeneratedMessage $_createMessage() => GroupHandshake._();
  @$core.override
  GroupHandshake createEmptyInstance() => GroupHandshake._();
  @$core.pragma('dart2js:noInline')
  static GroupHandshake getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupHandshake>(
          GroupHandshake.$_createMessage);
  static GroupHandshake? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  GroupHandshake_Kind whichKind() =>
      _GroupHandshake_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearKind() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  InviteProposal get proposal => $_getN(0);
  @$pb.TagNumber(1)
  set proposal(InviteProposal value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasProposal() => $_has(0);
  @$pb.TagNumber(1)
  void clearProposal() => $_clearField(1);
  @$pb.TagNumber(1)
  InviteProposal ensureProposal() => $_ensure(0);

  @$pb.TagNumber(2)
  JoinAccept get accept => $_getN(1);
  @$pb.TagNumber(2)
  set accept(JoinAccept value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAccept() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccept() => $_clearField(2);
  @$pb.TagNumber(2)
  JoinAccept ensureAccept() => $_ensure(1);
}

class InviteProposal extends $pb.GeneratedMessage {
  factory InviteProposal({
    $core.List<$core.int>? groupId,
    $core.String? groupName,
    $core.List<$core.int>? adminMemberId,
  }) {
    final result = InviteProposal._();
    if (groupId != null) result.groupId = groupId;
    if (groupName != null) result.groupName = groupName;
    if (adminMemberId != null) result.adminMemberId = adminMemberId;
    return result;
  }

  InviteProposal._();

  factory InviteProposal.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InviteProposal()..mergeFromBuffer(data, registry);
  factory InviteProposal.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InviteProposal()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InviteProposal',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: InviteProposal.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'groupName')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'adminMemberId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InviteProposal clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InviteProposal copyWith(void Function(InviteProposal) updates) =>
      super.copyWith((message) => updates(message as InviteProposal))
          as InviteProposal;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use InviteProposal() / InviteProposal.new instead')
  static InviteProposal create() => InviteProposal._();
  static $pb.GeneratedMessage $_createMessage() => InviteProposal._();
  @$core.override
  InviteProposal createEmptyInstance() => InviteProposal._();
  @$core.pragma('dart2js:noInline')
  static InviteProposal getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InviteProposal>(
          InviteProposal.$_createMessage);
  static InviteProposal? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get groupName => $_getSZ(1);
  @$pb.TagNumber(2)
  set groupName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGroupName() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroupName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get adminMemberId => $_getN(2);
  @$pb.TagNumber(3)
  set adminMemberId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAdminMemberId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdminMemberId() => $_clearField(3);
}

class JoinAccept extends $pb.GeneratedMessage {
  factory JoinAccept({
    $core.List<$core.int>? groupId,
    $core.List<$core.int>? memberId,
    $core.List<$core.int>? x25519Pub,
    $core.List<$core.int>? ohId,
    $core.String? ohEndpoint,
  }) {
    final result = JoinAccept._();
    if (groupId != null) result.groupId = groupId;
    if (memberId != null) result.memberId = memberId;
    if (x25519Pub != null) result.x25519Pub = x25519Pub;
    if (ohId != null) result.ohId = ohId;
    if (ohEndpoint != null) result.ohEndpoint = ohEndpoint;
    return result;
  }

  JoinAccept._();

  factory JoinAccept.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinAccept()..mergeFromBuffer(data, registry);
  factory JoinAccept.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinAccept()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JoinAccept',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'im.redpanda.client.v1'),
      createEmptyInstance: JoinAccept.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'memberId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'x25519Pub', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..aOS(5, _omitFieldNames ? '' : 'ohEndpoint')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinAccept clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinAccept copyWith(void Function(JoinAccept) updates) =>
      super.copyWith((message) => updates(message as JoinAccept)) as JoinAccept;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JoinAccept() / JoinAccept.new instead')
  static JoinAccept create() => JoinAccept._();
  static $pb.GeneratedMessage $_createMessage() => JoinAccept._();
  @$core.override
  JoinAccept createEmptyInstance() => JoinAccept._();
  @$core.pragma('dart2js:noInline')
  static JoinAccept getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<JoinAccept>(JoinAccept.$_createMessage);
  static JoinAccept? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get memberId => $_getN(1);
  @$pb.TagNumber(2)
  set memberId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMemberId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemberId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get x25519Pub => $_getN(2);
  @$pb.TagNumber(3)
  set x25519Pub($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX25519Pub() => $_has(2);
  @$pb.TagNumber(3)
  void clearX25519Pub() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ohId => $_getN(3);
  @$pb.TagNumber(4)
  set ohId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOhId() => $_has(3);
  @$pb.TagNumber(4)
  void clearOhId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get ohEndpoint => $_getSZ(4);
  @$pb.TagNumber(5)
  set ohEndpoint($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOhEndpoint() => $_has(4);
  @$pb.TagNumber(5)
  void clearOhEndpoint() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
