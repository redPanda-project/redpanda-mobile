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
    $core.List<$core.int>? encryptionPublicKey,
  }) {
    final result = create();
    if (ip != null) result.ip = ip;
    if (port != null) result.port = port;
    if (nodeId != null) result.nodeId = nodeId;
    if (encryptionPublicKey != null) {
      result.encryptionPublicKey = encryptionPublicKey;
    }
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
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'encryptionPublicKey', $pb.PbFieldType.OY)
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

  /// MS04: 32-byte X25519 encryption public key of the node, so light clients
  /// can pick garlic hops without importing the full 64-byte node_id export.
  /// Only set when node_id is known (duplicates bytes 32..63 of the export).
  @$pb.TagNumber(4)
  $core.List<$core.int> get encryptionPublicKey => $_getN(3);
  @$pb.TagNumber(4)
  set encryptionPublicKey($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEncryptionPublicKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncryptionPublicKey() => $_clearField(4);
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
    $core.List<$core.int>? ohId,
    $core.bool? wantResponse,
    $core.int? hopCount,
  }) {
    final result = create();
    if (content != null) result.content = content;
    if (ohId != null) result.ohId = ohId;
    if (wantResponse != null) result.wantResponse = wantResponse;
    if (hopCount != null) result.hopCount = hopCount;
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
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'wantResponse')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'hopCount', $pb.PbFieldType.OU3)
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

  @$pb.TagNumber(2)
  $core.List<$core.int> get ohId => $_getN(1);
  @$pb.TagNumber(2)
  set ohId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOhId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOhId() => $_clearField(2);

  /// MS02b: if set by a directly connected light client, the node answers
  /// with FlaschenpostPutResponse (command 158). Full nodes never set this.
  @$pb.TagNumber(3)
  $core.bool get wantResponse => $_getBF(2);
  @$pb.TagNumber(3)
  set wantResponse($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWantResponse() => $_has(2);
  @$pb.TagNumber(3)
  void clearWantResponse() => $_clearField(3);

  /// MS02b: node-to-node forward counter (loop protection).
  /// Light clients never set this.
  @$pb.TagNumber(4)
  $core.int get hopCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set hopCount($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHopCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearHopCount() => $_clearField(4);
}

// --- FlaschenpostPutResponse (MS02b) ---
/// Optional response to a FlaschenpostPut deposit (command 158). Only sent to
/// light clients that set FlaschenpostPut.want_response. OK means deposited
/// or accepted for best-effort forwarding toward the OH host node.
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FlaschenpostPutResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..e<Status>(1, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE,
        defaultOrMaker: Status.STATUS_UNSPECIFIED,
        valueOf: Status.valueOf,
        enumValues: Status.values)
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
  static FlaschenpostPutResponse? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static FlaschenpostPutResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FlaschenpostPutResponse>(create);

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
}

// --- Status enum for OH operations ---
class Status extends $pb.ProtobufEnum {
  static const Status STATUS_UNSPECIFIED =
      Status._(0, _omitEnumNames ? '' : 'STATUS_UNSPECIFIED');
  static const Status OK = Status._(1, _omitEnumNames ? '' : 'OK');
  static const Status INVALID_SIGNATURE =
      Status._(2, _omitEnumNames ? '' : 'INVALID_SIGNATURE');
  static const Status INVALID_TIMESTAMP =
      Status._(3, _omitEnumNames ? '' : 'INVALID_TIMESTAMP');
  static const Status REPLAY = Status._(4, _omitEnumNames ? '' : 'REPLAY');
  static const Status NOT_FOUND =
      Status._(5, _omitEnumNames ? '' : 'NOT_FOUND');
  static const Status RATE_LIMIT =
      Status._(6, _omitEnumNames ? '' : 'RATE_LIMIT');
  static const Status QUOTA_EXCEEDED =
      Status._(7, _omitEnumNames ? '' : 'QUOTA_EXCEEDED');
  static const Status BAD_REQUEST =
      Status._(8, _omitEnumNames ? '' : 'BAD_REQUEST');

  static const $core.List<Status> values = <Status>[
    STATUS_UNSPECIFIED,
    OK,
    INVALID_SIGNATURE,
    INVALID_TIMESTAMP,
    REPLAY,
    NOT_FOUND,
    RATE_LIMIT,
    QUOTA_EXCEEDED,
    BAD_REQUEST,
  ];

  static final $core.Map<$core.int, Status> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static Status? valueOf($core.int value) => _byValue[value];

  const Status._(super.v, super.n);
}

// --- RegisterOhRequest ---
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterOhRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
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
  static RegisterOhRequest? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static RegisterOhRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterOhRequest>(create);

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ohAuthPublicKey => $_getN(1);
  @$pb.TagNumber(2)
  set ohAuthPublicKey($core.List<$core.int> value) => $_setBytes(1, value);

  @$pb.TagNumber(3)
  $fixnum.Int64 get requestedExpiresAt => $_getI64(2);
  @$pb.TagNumber(3)
  set requestedExpiresAt($fixnum.Int64 value) => $_setInt64(2, value);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 value) => $_setInt64(3, value);

  @$pb.TagNumber(5)
  $core.List<$core.int> get nonce => $_getN(4);
  @$pb.TagNumber(5)
  set nonce($core.List<$core.int> value) => $_setBytes(4, value);

  @$pb.TagNumber(6)
  $core.List<$core.int> get signature => $_getN(5);
  @$pb.TagNumber(6)
  set signature($core.List<$core.int> value) => $_setBytes(5, value);
}

// --- RegisterOhResponse ---
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterOhResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..e<Status>(1, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE,
        defaultOrMaker: Status.STATUS_UNSPECIFIED,
        valueOf: Status.valueOf,
        enumValues: Status.values)
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
  static RegisterOhResponse? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static RegisterOhResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterOhResponse>(create);

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);

  @$pb.TagNumber(3)
  $fixnum.Int64 get expiresAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set expiresAtMs($fixnum.Int64 value) => $_setInt64(2, value);
}

// --- FetchRequest ---
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FetchRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ohId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.OU3)
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
  static FetchRequest? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static FetchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FetchRequest>(create);

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setUnsignedInt32(1, value);

  @$pb.TagNumber(3)
  $fixnum.Int64 get cursor => $_getI64(2);
  @$pb.TagNumber(3)
  set cursor($fixnum.Int64 value) => $_setInt64(2, value);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 value) => $_setInt64(3, value);

  @$pb.TagNumber(5)
  $core.List<$core.int> get nonce => $_getN(4);
  @$pb.TagNumber(5)
  set nonce($core.List<$core.int> value) => $_setBytes(4, value);

  @$pb.TagNumber(6)
  $core.List<$core.int> get signature => $_getN(5);
  @$pb.TagNumber(6)
  set signature($core.List<$core.int> value) => $_setBytes(5, value);
}

// --- MailItem ---
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MailItem',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
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
  static MailItem? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static MailItem getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MailItem>(create);

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> value) => $_setBytes(0, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get receivedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set receivedAtMs($fixnum.Int64 value) => $_setInt64(1, value);

  @$pb.TagNumber(3)
  $core.List<$core.int> get payload => $_getN(2);
  @$pb.TagNumber(3)
  set payload($core.List<$core.int> value) => $_setBytes(2, value);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sequenceId => $_getI64(3);
  @$pb.TagNumber(4)
  set sequenceId($fixnum.Int64 value) => $_setInt64(3, value);

  /// MS05: 16-byte session tag from a reverse-garlic reply
  /// (CMD_DELIVER_TAGGED). Empty for direct messages and untagged delivers.
  @$pb.TagNumber(5)
  $core.List<$core.int> get sessionTag => $_getN(4);
  @$pb.TagNumber(5)
  set sessionTag($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSessionTag() => $_has(4);
  @$pb.TagNumber(5)
  void clearSessionTag() => $_clearField(5);
}

// --- FetchResponse ---
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FetchResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..e<Status>(1, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE,
        defaultOrMaker: Status.STATUS_UNSPECIFIED,
        valueOf: Status.valueOf,
        enumValues: Status.values)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'nextCursor', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pc<MailItem>(3, _omitFieldNames ? '' : 'items', $pb.PbFieldType.PM,
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
  static FetchResponse? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static FetchResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FetchResponse>(create);

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get nextCursor => $_getI64(1);
  @$pb.TagNumber(2)
  set nextCursor($fixnum.Int64 value) => $_setInt64(1, value);

  @$pb.TagNumber(3)
  $core.List<MailItem> get items => $_getList(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get serverTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(3, value);

  @$pb.TagNumber(5)
  $core.bool get mailboxOverflow => $_getBF(4);
  @$pb.TagNumber(5)
  set mailboxOverflow($core.bool value) => $_setBool(4, value);
}

// --- AckFetchRequest ---
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AckFetchRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
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
  static AckFetchRequest? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static AckFetchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AckFetchRequest>(create);

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get ackedSequenceId => $_getI64(1);
  @$pb.TagNumber(2)
  set ackedSequenceId($fixnum.Int64 value) => $_setInt64(1, value);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 value) => $_setInt64(2, value);

  @$pb.TagNumber(4)
  $core.List<$core.int> get nonce => $_getN(3);
  @$pb.TagNumber(4)
  set nonce($core.List<$core.int> value) => $_setBytes(3, value);

  @$pb.TagNumber(5)
  $core.List<$core.int> get signature => $_getN(4);
  @$pb.TagNumber(5)
  set signature($core.List<$core.int> value) => $_setBytes(4, value);
}

// --- AckFetchResponse ---
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AckFetchResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..e<Status>(1, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE,
        defaultOrMaker: Status.STATUS_UNSPECIFIED,
        valueOf: Status.valueOf,
        enumValues: Status.values)
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
  static AckFetchResponse? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static AckFetchResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AckFetchResponse>(create);

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
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

// --- SubscribeRequest ---
// Connection-Notify (T38): hand-extended from outbound.proto (im.redpanda.outbound.v1).
// Proves OH ownership exactly like FetchRequest — Ed25519 signature over the signing
// bytes [CMD_BYTE=159 | oh_id | timestamp_ms(8 BE) | nonce] (0x02 version prefix added
// by OHKeypair.sign). Sent as command 159.
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SubscribeRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
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
  static SubscribeRequest? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static SubscribeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SubscribeRequest>(create);

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nonce => $_getN(2);
  @$pb.TagNumber(3)
  set nonce($core.List<$core.int> value) => $_setBytes(2, value);

  @$pb.TagNumber(4)
  $core.List<$core.int> get signature => $_getN(3);
  @$pb.TagNumber(4)
  set signature($core.List<$core.int> value) => $_setBytes(3, value);
}

// --- SubscribeResponse ---
// Connection-Notify (T38): node → client answer to a SubscribeRequest (command 160).
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SubscribeResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
      createEmptyInstance: create)
    ..e<Status>(1, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE,
        defaultOrMaker: Status.STATUS_UNSPECIFIED,
        valueOf: Status.valueOf,
        enumValues: Status.values)
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
  static SubscribeResponse? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static SubscribeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SubscribeResponse>(create);

  @$pb.TagNumber(1)
  Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Status value) => $_setField(1, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set serverTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
}

// --- Notify ---
// Connection-Notify (T38): one-way node → client (command 161). Carries ONLY the oh_id.
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

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Notify',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'im.redpanda.proto'),
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
  static Notify? _defaultInstance;
  @$core.pragma('dart2js:noInline')
  static Notify getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Notify>(create);

  @$pb.TagNumber(1)
  $core.List<$core.int> get ohId => $_getN(0);
  @$pb.TagNumber(1)
  set ohId($core.List<$core.int> value) => $_setBytes(0, value);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
