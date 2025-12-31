// This is a generated file - do not edit.
//
// Generated from commands.proto.

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

class KademliaIdProto extends $pb.GeneratedMessage {
  factory KademliaIdProto({
    $core.List<$core.int>? keyBytes,
  }) {
    final result = create();
    if (keyBytes != null) result.keyBytes = keyBytes;
    return result;
  }

  KademliaIdProto._();

  factory KademliaIdProto.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory KademliaIdProto.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KademliaIdProto',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'keyBytes', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaIdProto clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaIdProto copyWith(void Function(KademliaIdProto) updates) =>
      super.copyWith((message) => updates(message as KademliaIdProto))
          as KademliaIdProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KademliaIdProto create() => KademliaIdProto._();
  @$core.override
  KademliaIdProto createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static KademliaIdProto getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KademliaIdProto>(create);
  static KademliaIdProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get keyBytes => $_getN(0);
  @$pb.TagNumber(1)
  set keyBytes($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKeyBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeyBytes() => $_clearField(1);
}

class NodeIdProto extends $pb.GeneratedMessage {
  factory NodeIdProto({
    $core.List<$core.int>? publicKeyBytes,
  }) {
    final result = create();
    if (publicKeyBytes != null) result.publicKeyBytes = publicKeyBytes;
    return result;
  }

  NodeIdProto._();

  factory NodeIdProto.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NodeIdProto.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NodeIdProto',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'publicKeyBytes', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeIdProto clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NodeIdProto copyWith(void Function(NodeIdProto) updates) =>
      super.copyWith((message) => updates(message as NodeIdProto))
          as NodeIdProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NodeIdProto create() => NodeIdProto._();
  @$core.override
  NodeIdProto createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NodeIdProto getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NodeIdProto>(create);
  static NodeIdProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get publicKeyBytes => $_getN(0);
  @$pb.TagNumber(1)
  set publicKeyBytes($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPublicKeyBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearPublicKeyBytes() => $_clearField(1);
}

class PeerInfoProto extends $pb.GeneratedMessage {
  factory PeerInfoProto({
    $core.String? ip,
    $core.int? port,
    NodeIdProto? nodeId,
  }) {
    final result = create();
    if (ip != null) result.ip = ip;
    if (port != null) result.port = port;
    if (nodeId != null) result.nodeId = nodeId;
    return result;
  }

  PeerInfoProto._();

  factory PeerInfoProto.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PeerInfoProto.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PeerInfoProto',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'ip')
    ..aI(2, _omitFieldNames ? '' : 'port')
    ..aOM<NodeIdProto>(3, _omitFieldNames ? '' : 'nodeId',
        subBuilder: NodeIdProto.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeerInfoProto clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeerInfoProto copyWith(void Function(PeerInfoProto) updates) =>
      super.copyWith((message) => updates(message as PeerInfoProto))
          as PeerInfoProto;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerInfoProto create() => PeerInfoProto._();
  @$core.override
  PeerInfoProto createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PeerInfoProto getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PeerInfoProto>(create);
  static PeerInfoProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get ip => $_getSZ(0);
  @$pb.TagNumber(1)
  set ip($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIp() => $_has(0);
  @$pb.TagNumber(1)
  void clearIp() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get port => $_getIZ(1);
  @$pb.TagNumber(2)
  set port($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPort() => $_has(1);
  @$pb.TagNumber(2)
  void clearPort() => $_clearField(2);

  @$pb.TagNumber(3)
  NodeIdProto get nodeId => $_getN(2);
  @$pb.TagNumber(3)
  set nodeId(NodeIdProto value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasNodeId() => $_has(2);
  @$pb.TagNumber(3)
  void clearNodeId() => $_clearField(3);
  @$pb.TagNumber(3)
  NodeIdProto ensureNodeId() => $_ensure(2);
}

class SendPeerList extends $pb.GeneratedMessage {
  factory SendPeerList({
    $core.Iterable<PeerInfoProto>? peers,
  }) {
    final result = create();
    if (peers != null) result.peers.addAll(peers);
    return result;
  }

  SendPeerList._();

  factory SendPeerList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SendPeerList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendPeerList',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..pPM<PeerInfoProto>(1, _omitFieldNames ? '' : 'peers',
        subBuilder: PeerInfoProto.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendPeerList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendPeerList copyWith(void Function(SendPeerList) updates) =>
      super.copyWith((message) => updates(message as SendPeerList))
          as SendPeerList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendPeerList create() => SendPeerList._();
  @$core.override
  SendPeerList createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SendPeerList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendPeerList>(create);
  static SendPeerList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PeerInfoProto> get peers => $_getList(0);
}

class Ping extends $pb.GeneratedMessage {
  factory Ping() => create();

  Ping._();

  factory Ping.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ping.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ping',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping copyWith(void Function(Ping) updates) =>
      super.copyWith((message) => updates(message as Ping)) as Ping;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ping create() => Ping._();
  @$core.override
  Ping createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ping getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ping>(create);
  static Ping? _defaultInstance;
}

class Pong extends $pb.GeneratedMessage {
  factory Pong() => create();

  Pong._();

  factory Pong.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Pong.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pong',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pong clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pong copyWith(void Function(Pong) updates) =>
      super.copyWith((message) => updates(message as Pong)) as Pong;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Pong create() => Pong._();
  @$core.override
  Pong createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Pong getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Pong>(create);
  static Pong? _defaultInstance;
}

class RequestPeerList extends $pb.GeneratedMessage {
  factory RequestPeerList() => create();

  RequestPeerList._();

  factory RequestPeerList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RequestPeerList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RequestPeerList',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RequestPeerList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RequestPeerList copyWith(void Function(RequestPeerList) updates) =>
      super.copyWith((message) => updates(message as RequestPeerList))
          as RequestPeerList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RequestPeerList create() => RequestPeerList._();
  @$core.override
  RequestPeerList createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RequestPeerList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RequestPeerList>(create);
  static RequestPeerList? _defaultInstance;
}

class KademliaGet extends $pb.GeneratedMessage {
  factory KademliaGet({
    $core.int? jobId,
    KademliaIdProto? searchedId,
  }) {
    final result = create();
    if (jobId != null) result.jobId = jobId;
    if (searchedId != null) result.searchedId = searchedId;
    return result;
  }

  KademliaGet._();

  factory KademliaGet.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory KademliaGet.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KademliaGet',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'jobId')
    ..aOM<KademliaIdProto>(2, _omitFieldNames ? '' : 'searchedId',
        subBuilder: KademliaIdProto.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaGet clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaGet copyWith(void Function(KademliaGet) updates) =>
      super.copyWith((message) => updates(message as KademliaGet))
          as KademliaGet;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KademliaGet create() => KademliaGet._();
  @$core.override
  KademliaGet createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static KademliaGet getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KademliaGet>(create);
  static KademliaGet? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get jobId => $_getIZ(0);
  @$pb.TagNumber(1)
  set jobId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  @$pb.TagNumber(2)
  KademliaIdProto get searchedId => $_getN(1);
  @$pb.TagNumber(2)
  set searchedId(KademliaIdProto value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSearchedId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSearchedId() => $_clearField(2);
  @$pb.TagNumber(2)
  KademliaIdProto ensureSearchedId() => $_ensure(1);
}

class KademliaGetAnswer extends $pb.GeneratedMessage {
  factory KademliaGetAnswer({
    $core.int? ackId,
    $fixnum.Int64? timestamp,
    $core.List<$core.int>? publicKey,
    $core.List<$core.int>? content,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (ackId != null) result.ackId = ackId;
    if (timestamp != null) result.timestamp = timestamp;
    if (publicKey != null) result.publicKey = publicKey;
    if (content != null) result.content = content;
    if (signature != null) result.signature = signature;
    return result;
  }

  KademliaGetAnswer._();

  factory KademliaGetAnswer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory KademliaGetAnswer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KademliaGetAnswer',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'ackId')
    ..aInt64(2, _omitFieldNames ? '' : 'timestamp')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaGetAnswer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaGetAnswer copyWith(void Function(KademliaGetAnswer) updates) =>
      super.copyWith((message) => updates(message as KademliaGetAnswer))
          as KademliaGetAnswer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KademliaGetAnswer create() => KademliaGetAnswer._();
  @$core.override
  KademliaGetAnswer createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static KademliaGetAnswer getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KademliaGetAnswer>(create);
  static KademliaGetAnswer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get ackId => $_getIZ(0);
  @$pb.TagNumber(1)
  set ackId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAckId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAckId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get publicKey => $_getN(2);
  @$pb.TagNumber(3)
  set publicKey($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPublicKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearPublicKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get content => $_getN(3);
  @$pb.TagNumber(4)
  set content($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearContent() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get signature => $_getN(4);
  @$pb.TagNumber(5)
  set signature($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSignature() => $_has(4);
  @$pb.TagNumber(5)
  void clearSignature() => $_clearField(5);
}

class KademliaStore extends $pb.GeneratedMessage {
  factory KademliaStore({
    $core.int? jobId,
    $fixnum.Int64? timestamp,
    $core.List<$core.int>? publicKey,
    $core.List<$core.int>? content,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (jobId != null) result.jobId = jobId;
    if (timestamp != null) result.timestamp = timestamp;
    if (publicKey != null) result.publicKey = publicKey;
    if (content != null) result.content = content;
    if (signature != null) result.signature = signature;
    return result;
  }

  KademliaStore._();

  factory KademliaStore.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory KademliaStore.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KademliaStore',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'jobId')
    ..aInt64(2, _omitFieldNames ? '' : 'timestamp')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaStore clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KademliaStore copyWith(void Function(KademliaStore) updates) =>
      super.copyWith((message) => updates(message as KademliaStore))
          as KademliaStore;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KademliaStore create() => KademliaStore._();
  @$core.override
  KademliaStore createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static KademliaStore getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KademliaStore>(create);
  static KademliaStore? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get jobId => $_getIZ(0);
  @$pb.TagNumber(1)
  set jobId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get publicKey => $_getN(2);
  @$pb.TagNumber(3)
  set publicKey($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPublicKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearPublicKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get content => $_getN(3);
  @$pb.TagNumber(4)
  set content($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearContent() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get signature => $_getN(4);
  @$pb.TagNumber(5)
  set signature($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSignature() => $_has(4);
  @$pb.TagNumber(5)
  void clearSignature() => $_clearField(5);
}

class JobAck extends $pb.GeneratedMessage {
  factory JobAck({
    $core.int? jobId,
  }) {
    final result = create();
    if (jobId != null) result.jobId = jobId;
    return result;
  }

  JobAck._();

  factory JobAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory JobAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JobAck',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'jobId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JobAck copyWith(void Function(JobAck) updates) =>
      super.copyWith((message) => updates(message as JobAck)) as JobAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JobAck create() => JobAck._();
  @$core.override
  JobAck createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static JobAck getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JobAck>(create);
  static JobAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get jobId => $_getIZ(0);
  @$pb.TagNumber(1)
  set jobId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJobId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJobId() => $_clearField(1);
}

class FlaschenpostPut extends $pb.GeneratedMessage {
  factory FlaschenpostPut({
    $core.List<$core.int>? content,
  }) {
    final result = create();
    if (content != null) result.content = content;
    return result;
  }

  FlaschenpostPut._();

  factory FlaschenpostPut.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FlaschenpostPut.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FlaschenpostPut',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FlaschenpostPut clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FlaschenpostPut copyWith(void Function(FlaschenpostPut) updates) =>
      super.copyWith((message) => updates(message as FlaschenpostPut))
          as FlaschenpostPut;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FlaschenpostPut create() => FlaschenpostPut._();
  @$core.override
  FlaschenpostPut createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FlaschenpostPut getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FlaschenpostPut>(create);
  static FlaschenpostPut? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get content => $_getN(0);
  @$pb.TagNumber(1)
  set content($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContent() => $_has(0);
  @$pb.TagNumber(1)
  void clearContent() => $_clearField(1);
}

enum PandaMessage_Content {
  ping,
  pong,
  requestPeerList,
  sendPeerList,
  kademliaGet,
  kademliaGetAnswer,
  kademliaStore,
  jobAck,
  flaschenpostPut,
  notSet
}

/// Unified envelope for future-proofing or batching,
/// though we currently use a 1-byte header for dispatch.
class PandaMessage extends $pb.GeneratedMessage {
  factory PandaMessage({
    Ping? ping,
    Pong? pong,
    RequestPeerList? requestPeerList,
    SendPeerList? sendPeerList,
    KademliaGet? kademliaGet,
    KademliaGetAnswer? kademliaGetAnswer,
    KademliaStore? kademliaStore,
    JobAck? jobAck,
    FlaschenpostPut? flaschenpostPut,
  }) {
    final result = create();
    if (ping != null) result.ping = ping;
    if (pong != null) result.pong = pong;
    if (requestPeerList != null) result.requestPeerList = requestPeerList;
    if (sendPeerList != null) result.sendPeerList = sendPeerList;
    if (kademliaGet != null) result.kademliaGet = kademliaGet;
    if (kademliaGetAnswer != null) result.kademliaGetAnswer = kademliaGetAnswer;
    if (kademliaStore != null) result.kademliaStore = kademliaStore;
    if (jobAck != null) result.jobAck = jobAck;
    if (flaschenpostPut != null) result.flaschenpostPut = flaschenpostPut;
    return result;
  }

  PandaMessage._();

  factory PandaMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PandaMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, PandaMessage_Content>
      _PandaMessage_ContentByTag = {
    1: PandaMessage_Content.ping,
    2: PandaMessage_Content.pong,
    3: PandaMessage_Content.requestPeerList,
    4: PandaMessage_Content.sendPeerList,
    5: PandaMessage_Content.kademliaGet,
    6: PandaMessage_Content.kademliaGetAnswer,
    7: PandaMessage_Content.kademliaStore,
    8: PandaMessage_Content.jobAck,
    9: PandaMessage_Content.flaschenpostPut,
    0: PandaMessage_Content.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PandaMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6, 7, 8, 9])
    ..aOM<Ping>(1, _omitFieldNames ? '' : 'ping', subBuilder: Ping.create)
    ..aOM<Pong>(2, _omitFieldNames ? '' : 'pong', subBuilder: Pong.create)
    ..aOM<RequestPeerList>(3, _omitFieldNames ? '' : 'requestPeerList',
        subBuilder: RequestPeerList.create)
    ..aOM<SendPeerList>(4, _omitFieldNames ? '' : 'sendPeerList',
        subBuilder: SendPeerList.create)
    ..aOM<KademliaGet>(5, _omitFieldNames ? '' : 'kademliaGet',
        subBuilder: KademliaGet.create)
    ..aOM<KademliaGetAnswer>(6, _omitFieldNames ? '' : 'kademliaGetAnswer',
        subBuilder: KademliaGetAnswer.create)
    ..aOM<KademliaStore>(7, _omitFieldNames ? '' : 'kademliaStore',
        subBuilder: KademliaStore.create)
    ..aOM<JobAck>(8, _omitFieldNames ? '' : 'jobAck', subBuilder: JobAck.create)
    ..aOM<FlaschenpostPut>(9, _omitFieldNames ? '' : 'flaschenpostPut',
        subBuilder: FlaschenpostPut.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PandaMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PandaMessage copyWith(void Function(PandaMessage) updates) =>
      super.copyWith((message) => updates(message as PandaMessage))
          as PandaMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PandaMessage create() => PandaMessage._();
  @$core.override
  PandaMessage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PandaMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PandaMessage>(create);
  static PandaMessage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  PandaMessage_Content whichContent() =>
      _PandaMessage_ContentByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  void clearContent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  Ping get ping => $_getN(0);
  @$pb.TagNumber(1)
  set ping(Ping value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPing() => $_has(0);
  @$pb.TagNumber(1)
  void clearPing() => $_clearField(1);
  @$pb.TagNumber(1)
  Ping ensurePing() => $_ensure(0);

  @$pb.TagNumber(2)
  Pong get pong => $_getN(1);
  @$pb.TagNumber(2)
  set pong(Pong value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPong() => $_has(1);
  @$pb.TagNumber(2)
  void clearPong() => $_clearField(2);
  @$pb.TagNumber(2)
  Pong ensurePong() => $_ensure(1);

  @$pb.TagNumber(3)
  RequestPeerList get requestPeerList => $_getN(2);
  @$pb.TagNumber(3)
  set requestPeerList(RequestPeerList value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestPeerList() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestPeerList() => $_clearField(3);
  @$pb.TagNumber(3)
  RequestPeerList ensureRequestPeerList() => $_ensure(2);

  @$pb.TagNumber(4)
  SendPeerList get sendPeerList => $_getN(3);
  @$pb.TagNumber(4)
  set sendPeerList(SendPeerList value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSendPeerList() => $_has(3);
  @$pb.TagNumber(4)
  void clearSendPeerList() => $_clearField(4);
  @$pb.TagNumber(4)
  SendPeerList ensureSendPeerList() => $_ensure(3);

  @$pb.TagNumber(5)
  KademliaGet get kademliaGet => $_getN(4);
  @$pb.TagNumber(5)
  set kademliaGet(KademliaGet value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasKademliaGet() => $_has(4);
  @$pb.TagNumber(5)
  void clearKademliaGet() => $_clearField(5);
  @$pb.TagNumber(5)
  KademliaGet ensureKademliaGet() => $_ensure(4);

  @$pb.TagNumber(6)
  KademliaGetAnswer get kademliaGetAnswer => $_getN(5);
  @$pb.TagNumber(6)
  set kademliaGetAnswer(KademliaGetAnswer value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasKademliaGetAnswer() => $_has(5);
  @$pb.TagNumber(6)
  void clearKademliaGetAnswer() => $_clearField(6);
  @$pb.TagNumber(6)
  KademliaGetAnswer ensureKademliaGetAnswer() => $_ensure(5);

  @$pb.TagNumber(7)
  KademliaStore get kademliaStore => $_getN(6);
  @$pb.TagNumber(7)
  set kademliaStore(KademliaStore value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasKademliaStore() => $_has(6);
  @$pb.TagNumber(7)
  void clearKademliaStore() => $_clearField(7);
  @$pb.TagNumber(7)
  KademliaStore ensureKademliaStore() => $_ensure(6);

  @$pb.TagNumber(8)
  JobAck get jobAck => $_getN(7);
  @$pb.TagNumber(8)
  set jobAck(JobAck value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasJobAck() => $_has(7);
  @$pb.TagNumber(8)
  void clearJobAck() => $_clearField(8);
  @$pb.TagNumber(8)
  JobAck ensureJobAck() => $_ensure(7);

  @$pb.TagNumber(9)
  FlaschenpostPut get flaschenpostPut => $_getN(8);
  @$pb.TagNumber(9)
  set flaschenpostPut(FlaschenpostPut value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasFlaschenpostPut() => $_has(8);
  @$pb.TagNumber(9)
  void clearFlaschenpostPut() => $_clearField(9);
  @$pb.TagNumber(9)
  FlaschenpostPut ensureFlaschenpostPut() => $_ensure(8);
}

class GarlicMessage extends $pb.GeneratedMessage {
  factory GarlicMessage({
    $core.int? type,
    KademliaIdProto? destination,
    $core.List<$core.int>? iv,
    $core.List<$core.int>? senderPublicKey,
    $core.List<$core.int>? encryptedPayload,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (destination != null) result.destination = destination;
    if (iv != null) result.iv = iv;
    if (senderPublicKey != null) result.senderPublicKey = senderPublicKey;
    if (encryptedPayload != null) result.encryptedPayload = encryptedPayload;
    if (signature != null) result.signature = signature;
    return result;
  }

  GarlicMessage._();

  factory GarlicMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GarlicMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GarlicMessage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'type')
    ..aOM<KademliaIdProto>(2, _omitFieldNames ? '' : 'destination',
        subBuilder: KademliaIdProto.create)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'iv', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'senderPublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'encryptedPayload', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GarlicMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GarlicMessage copyWith(void Function(GarlicMessage) updates) =>
      super.copyWith((message) => updates(message as GarlicMessage))
          as GarlicMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GarlicMessage create() => GarlicMessage._();
  @$core.override
  GarlicMessage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GarlicMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GarlicMessage>(create);
  static GarlicMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get type => $_getIZ(0);
  @$pb.TagNumber(1)
  set type($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  KademliaIdProto get destination => $_getN(1);
  @$pb.TagNumber(2)
  set destination(KademliaIdProto value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDestination() => $_has(1);
  @$pb.TagNumber(2)
  void clearDestination() => $_clearField(2);
  @$pb.TagNumber(2)
  KademliaIdProto ensureDestination() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get iv => $_getN(2);
  @$pb.TagNumber(3)
  set iv($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIv() => $_has(2);
  @$pb.TagNumber(3)
  void clearIv() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get senderPublicKey => $_getN(3);
  @$pb.TagNumber(4)
  set senderPublicKey($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSenderPublicKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearSenderPublicKey() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get encryptedPayload => $_getN(4);
  @$pb.TagNumber(5)
  set encryptedPayload($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEncryptedPayload() => $_has(4);
  @$pb.TagNumber(5)
  void clearEncryptedPayload() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get signature => $_getN(5);
  @$pb.TagNumber(6)
  set signature($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSignature() => $_has(5);
  @$pb.TagNumber(6)
  void clearSignature() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
