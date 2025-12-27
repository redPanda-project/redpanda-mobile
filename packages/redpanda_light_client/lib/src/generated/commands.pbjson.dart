// This is a generated file - do not edit.
//
// Generated from commands.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use kademliaIdProtoDescriptor instead')
const KademliaIdProto$json = {
  '1': 'KademliaIdProto',
  '2': [
    {'1': 'key_bytes', '3': 1, '4': 1, '5': 12, '10': 'keyBytes'},
  ],
};

/// Descriptor for `KademliaIdProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List kademliaIdProtoDescriptor = $convert.base64Decode(
    'Cg9LYWRlbWxpYUlkUHJvdG8SGwoJa2V5X2J5dGVzGAEgASgMUghrZXlCeXRlcw==');

@$core.Deprecated('Use nodeIdProtoDescriptor instead')
const NodeIdProto$json = {
  '1': 'NodeIdProto',
  '2': [
    {'1': 'public_key_bytes', '3': 1, '4': 1, '5': 12, '10': 'publicKeyBytes'},
  ],
};

/// Descriptor for `NodeIdProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nodeIdProtoDescriptor = $convert.base64Decode(
    'CgtOb2RlSWRQcm90bxIoChBwdWJsaWNfa2V5X2J5dGVzGAEgASgMUg5wdWJsaWNLZXlCeXRlcw'
    '==');

@$core.Deprecated('Use peerInfoProtoDescriptor instead')
const PeerInfoProto$json = {
  '1': 'PeerInfoProto',
  '2': [
    {'1': 'ip', '3': 1, '4': 1, '5': 9, '10': 'ip'},
    {'1': 'port', '3': 2, '4': 1, '5': 5, '10': 'port'},
    {
      '1': 'node_id',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.NodeIdProto',
      '10': 'nodeId'
    },
  ],
};

/// Descriptor for `PeerInfoProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerInfoProtoDescriptor = $convert.base64Decode(
    'Cg1QZWVySW5mb1Byb3RvEg4KAmlwGAEgASgJUgJpcBISCgRwb3J0GAIgASgFUgRwb3J0EjcKB2'
    '5vZGVfaWQYAyABKAsyHi5pbS5yZWRwYW5kYS5wcm90by5Ob2RlSWRQcm90b1IGbm9kZUlk');

@$core.Deprecated('Use sendPeerListDescriptor instead')
const SendPeerList$json = {
  '1': 'SendPeerList',
  '2': [
    {
      '1': 'peers',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.im.redpanda.proto.PeerInfoProto',
      '10': 'peers'
    },
  ],
};

/// Descriptor for `SendPeerList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendPeerListDescriptor = $convert.base64Decode(
    'CgxTZW5kUGVlckxpc3QSNgoFcGVlcnMYASADKAsyIC5pbS5yZWRwYW5kYS5wcm90by5QZWVySW'
    '5mb1Byb3RvUgVwZWVycw==');

@$core.Deprecated('Use pingDescriptor instead')
const Ping$json = {
  '1': 'Ping',
};

/// Descriptor for `Ping`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingDescriptor = $convert.base64Decode('CgRQaW5n');

@$core.Deprecated('Use pongDescriptor instead')
const Pong$json = {
  '1': 'Pong',
};

/// Descriptor for `Pong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pongDescriptor = $convert.base64Decode('CgRQb25n');

@$core.Deprecated('Use requestPeerListDescriptor instead')
const RequestPeerList$json = {
  '1': 'RequestPeerList',
};

/// Descriptor for `RequestPeerList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List requestPeerListDescriptor =
    $convert.base64Decode('Cg9SZXF1ZXN0UGVlckxpc3Q=');

@$core.Deprecated('Use kademliaGetDescriptor instead')
const KademliaGet$json = {
  '1': 'KademliaGet',
  '2': [
    {'1': 'job_id', '3': 1, '4': 1, '5': 5, '10': 'jobId'},
    {
      '1': 'searched_id',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.KademliaIdProto',
      '10': 'searchedId'
    },
  ],
};

/// Descriptor for `KademliaGet`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List kademliaGetDescriptor = $convert.base64Decode(
    'CgtLYWRlbWxpYUdldBIVCgZqb2JfaWQYASABKAVSBWpvYklkEkMKC3NlYXJjaGVkX2lkGAIgAS'
    'gLMiIuaW0ucmVkcGFuZGEucHJvdG8uS2FkZW1saWFJZFByb3RvUgpzZWFyY2hlZElk');

@$core.Deprecated('Use kademliaGetAnswerDescriptor instead')
const KademliaGetAnswer$json = {
  '1': 'KademliaGetAnswer',
  '2': [
    {'1': 'ack_id', '3': 1, '4': 1, '5': 5, '10': 'ackId'},
    {'1': 'timestamp', '3': 2, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'public_key', '3': 3, '4': 1, '5': 12, '10': 'publicKey'},
    {'1': 'content', '3': 4, '4': 1, '5': 12, '10': 'content'},
    {'1': 'signature', '3': 5, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `KademliaGetAnswer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List kademliaGetAnswerDescriptor = $convert.base64Decode(
    'ChFLYWRlbWxpYUdldEFuc3dlchIVCgZhY2tfaWQYASABKAVSBWFja0lkEhwKCXRpbWVzdGFtcB'
    'gCIAEoA1IJdGltZXN0YW1wEh0KCnB1YmxpY19rZXkYAyABKAxSCXB1YmxpY0tleRIYCgdjb250'
    'ZW50GAQgASgMUgdjb250ZW50EhwKCXNpZ25hdHVyZRgFIAEoDFIJc2lnbmF0dXJl');

@$core.Deprecated('Use kademliaStoreDescriptor instead')
const KademliaStore$json = {
  '1': 'KademliaStore',
  '2': [
    {'1': 'job_id', '3': 1, '4': 1, '5': 5, '10': 'jobId'},
    {'1': 'timestamp', '3': 2, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'public_key', '3': 3, '4': 1, '5': 12, '10': 'publicKey'},
    {'1': 'content', '3': 4, '4': 1, '5': 12, '10': 'content'},
    {'1': 'signature', '3': 5, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `KademliaStore`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List kademliaStoreDescriptor = $convert.base64Decode(
    'Cg1LYWRlbWxpYVN0b3JlEhUKBmpvYl9pZBgBIAEoBVIFam9iSWQSHAoJdGltZXN0YW1wGAIgAS'
    'gDUgl0aW1lc3RhbXASHQoKcHVibGljX2tleRgDIAEoDFIJcHVibGljS2V5EhgKB2NvbnRlbnQY'
    'BCABKAxSB2NvbnRlbnQSHAoJc2lnbmF0dXJlGAUgASgMUglzaWduYXR1cmU=');

@$core.Deprecated('Use jobAckDescriptor instead')
const JobAck$json = {
  '1': 'JobAck',
  '2': [
    {'1': 'job_id', '3': 1, '4': 1, '5': 5, '10': 'jobId'},
  ],
};

/// Descriptor for `JobAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jobAckDescriptor =
    $convert.base64Decode('CgZKb2JBY2sSFQoGam9iX2lkGAEgASgFUgVqb2JJZA==');

@$core.Deprecated('Use flaschenpostPutDescriptor instead')
const FlaschenpostPut$json = {
  '1': 'FlaschenpostPut',
  '2': [
    {'1': 'content', '3': 1, '4': 1, '5': 12, '10': 'content'},
  ],
};

/// Descriptor for `FlaschenpostPut`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List flaschenpostPutDescriptor = $convert.base64Decode(
    'Cg9GbGFzY2hlbnBvc3RQdXQSGAoHY29udGVudBgBIAEoDFIHY29udGVudA==');

@$core.Deprecated('Use pandaMessageDescriptor instead')
const PandaMessage$json = {
  '1': 'PandaMessage',
  '2': [
    {
      '1': 'ping',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.Ping',
      '9': 0,
      '10': 'ping'
    },
    {
      '1': 'pong',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.Pong',
      '9': 0,
      '10': 'pong'
    },
    {
      '1': 'request_peer_list',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.RequestPeerList',
      '9': 0,
      '10': 'requestPeerList'
    },
    {
      '1': 'send_peer_list',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.SendPeerList',
      '9': 0,
      '10': 'sendPeerList'
    },
    {
      '1': 'kademlia_get',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.KademliaGet',
      '9': 0,
      '10': 'kademliaGet'
    },
    {
      '1': 'kademlia_get_answer',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.KademliaGetAnswer',
      '9': 0,
      '10': 'kademliaGetAnswer'
    },
    {
      '1': 'kademlia_store',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.KademliaStore',
      '9': 0,
      '10': 'kademliaStore'
    },
    {
      '1': 'job_ack',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.JobAck',
      '9': 0,
      '10': 'jobAck'
    },
    {
      '1': 'flaschenpost_put',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.proto.FlaschenpostPut',
      '9': 0,
      '10': 'flaschenpostPut'
    },
  ],
  '8': [
    {'1': 'content'},
  ],
};

/// Descriptor for `PandaMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pandaMessageDescriptor = $convert.base64Decode(
    'CgxQYW5kYU1lc3NhZ2USLQoEcGluZxgBIAEoCzIXLmltLnJlZHBhbmRhLnByb3RvLlBpbmdIAF'
    'IEcGluZxItCgRwb25nGAIgASgLMhcuaW0ucmVkcGFuZGEucHJvdG8uUG9uZ0gAUgRwb25nElAK'
    'EXJlcXVlc3RfcGVlcl9saXN0GAMgASgLMiIuaW0ucmVkcGFuZGEucHJvdG8uUmVxdWVzdFBlZX'
    'JMaXN0SABSD3JlcXVlc3RQZWVyTGlzdBJHCg5zZW5kX3BlZXJfbGlzdBgEIAEoCzIfLmltLnJl'
    'ZHBhbmRhLnByb3RvLlNlbmRQZWVyTGlzdEgAUgxzZW5kUGVlckxpc3QSQwoMa2FkZW1saWFfZ2'
    'V0GAUgASgLMh4uaW0ucmVkcGFuZGEucHJvdG8uS2FkZW1saWFHZXRIAFILa2FkZW1saWFHZXQS'
    'VgoTa2FkZW1saWFfZ2V0X2Fuc3dlchgGIAEoCzIkLmltLnJlZHBhbmRhLnByb3RvLkthZGVtbG'
    'lhR2V0QW5zd2VySABSEWthZGVtbGlhR2V0QW5zd2VyEkkKDmthZGVtbGlhX3N0b3JlGAcgASgL'
    'MiAuaW0ucmVkcGFuZGEucHJvdG8uS2FkZW1saWFTdG9yZUgAUg1rYWRlbWxpYVN0b3JlEjQKB2'
    'pvYl9hY2sYCCABKAsyGS5pbS5yZWRwYW5kYS5wcm90by5Kb2JBY2tIAFIGam9iQWNrEk8KEGZs'
    'YXNjaGVucG9zdF9wdXQYCSABKAsyIi5pbS5yZWRwYW5kYS5wcm90by5GbGFzY2hlbnBvc3RQdX'
    'RIAFIPZmxhc2NoZW5wb3N0UHV0QgkKB2NvbnRlbnQ=');
