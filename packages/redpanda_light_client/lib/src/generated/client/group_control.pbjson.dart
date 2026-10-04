// This is a generated file - do not edit.
//
// Generated from client/group_control.proto.

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

@$core.Deprecated('Use groupMemberDescriptor instead')
const GroupMember$json = {
  '1': 'GroupMember',
  '2': [
    {'1': 'member_id', '3': 1, '4': 1, '5': 12, '10': 'memberId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'oh_id', '3': 3, '4': 1, '5': 12, '10': 'ohId'},
    {'1': 'oh_endpoint', '3': 4, '4': 1, '5': 9, '10': 'ohEndpoint'},
    {'1': 'x25519_pub', '3': 5, '4': 1, '5': 12, '10': 'x25519Pub'},
    {'1': 'role', '3': 6, '4': 1, '5': 13, '10': 'role'},
  ],
};

/// Descriptor for `GroupMember`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupMemberDescriptor = $convert.base64Decode(
    'CgtHcm91cE1lbWJlchIbCgltZW1iZXJfaWQYASABKAxSCG1lbWJlcklkEiEKDGRpc3BsYXlfbm'
    'FtZRgCIAEoCVILZGlzcGxheU5hbWUSEwoFb2hfaWQYAyABKAxSBG9oSWQSHwoLb2hfZW5kcG9p'
    'bnQYBCABKAlSCm9oRW5kcG9pbnQSHQoKeDI1NTE5X3B1YhgFIAEoDFIJeDI1NTE5UHViEhIKBH'
    'JvbGUYBiABKA1SBHJvbGU=');

@$core.Deprecated('Use groupControlDescriptor instead')
const GroupControl$json = {
  '1': 'GroupControl',
  '2': [
    {
      '1': 'key_rotation',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.client.v1.KeyRotation',
      '9': 0,
      '10': 'keyRotation'
    },
    {
      '1': 'info_update',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.client.v1.GroupInfoUpdate',
      '9': 0,
      '10': 'infoUpdate'
    },
  ],
  '8': [
    {'1': 'action'},
  ],
};

/// Descriptor for `GroupControl`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupControlDescriptor = $convert.base64Decode(
    'CgxHcm91cENvbnRyb2wSRwoMa2V5X3JvdGF0aW9uGAEgASgLMiIuaW0ucmVkcGFuZGEuY2xpZW'
    '50LnYxLktleVJvdGF0aW9uSABSC2tleVJvdGF0aW9uEkkKC2luZm9fdXBkYXRlGAIgASgLMiYu'
    'aW0ucmVkcGFuZGEuY2xpZW50LnYxLkdyb3VwSW5mb1VwZGF0ZUgAUgppbmZvVXBkYXRlQggKBm'
    'FjdGlvbg==');

@$core.Deprecated('Use keyRotationDescriptor instead')
const KeyRotation$json = {
  '1': 'KeyRotation',
  '2': [
    {'1': 'group_secret', '3': 1, '4': 1, '5': 12, '10': 'groupSecret'},
    {'1': 'key_epoch', '3': 2, '4': 1, '5': 13, '10': 'keyEpoch'},
    {
      '1': 'members',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.im.redpanda.client.v1.GroupMember',
      '10': 'members'
    },
    {'1': 'group_name', '3': 4, '4': 1, '5': 9, '10': 'groupName'},
  ],
};

/// Descriptor for `KeyRotation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyRotationDescriptor = $convert.base64Decode(
    'CgtLZXlSb3RhdGlvbhIhCgxncm91cF9zZWNyZXQYASABKAxSC2dyb3VwU2VjcmV0EhsKCWtleV'
    '9lcG9jaBgCIAEoDVIIa2V5RXBvY2gSPAoHbWVtYmVycxgDIAMoCzIiLmltLnJlZHBhbmRhLmNs'
    'aWVudC52MS5Hcm91cE1lbWJlclIHbWVtYmVycxIdCgpncm91cF9uYW1lGAQgASgJUglncm91cE'
    '5hbWU=');

@$core.Deprecated('Use groupInfoUpdateDescriptor instead')
const GroupInfoUpdate$json = {
  '1': 'GroupInfoUpdate',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `GroupInfoUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupInfoUpdateDescriptor = $convert
    .base64Decode('Cg9Hcm91cEluZm9VcGRhdGUSEgoEbmFtZRgBIAEoCVIEbmFtZQ==');

@$core.Deprecated('Use groupHandshakeDescriptor instead')
const GroupHandshake$json = {
  '1': 'GroupHandshake',
  '2': [
    {
      '1': 'proposal',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.client.v1.InviteProposal',
      '9': 0,
      '10': 'proposal'
    },
    {
      '1': 'accept',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.im.redpanda.client.v1.JoinAccept',
      '9': 0,
      '10': 'accept'
    },
  ],
  '8': [
    {'1': 'kind'},
  ],
};

/// Descriptor for `GroupHandshake`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupHandshakeDescriptor = $convert.base64Decode(
    'Cg5Hcm91cEhhbmRzaGFrZRJDCghwcm9wb3NhbBgBIAEoCzIlLmltLnJlZHBhbmRhLmNsaWVudC'
    '52MS5JbnZpdGVQcm9wb3NhbEgAUghwcm9wb3NhbBI7CgZhY2NlcHQYAiABKAsyIS5pbS5yZWRw'
    'YW5kYS5jbGllbnQudjEuSm9pbkFjY2VwdEgAUgZhY2NlcHRCBgoEa2luZA==');

@$core.Deprecated('Use inviteProposalDescriptor instead')
const InviteProposal$json = {
  '1': 'InviteProposal',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'group_name', '3': 2, '4': 1, '5': 9, '10': 'groupName'},
    {'1': 'admin_member_id', '3': 3, '4': 1, '5': 12, '10': 'adminMemberId'},
  ],
};

/// Descriptor for `InviteProposal`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List inviteProposalDescriptor = $convert.base64Decode(
    'Cg5JbnZpdGVQcm9wb3NhbBIZCghncm91cF9pZBgBIAEoDFIHZ3JvdXBJZBIdCgpncm91cF9uYW'
    '1lGAIgASgJUglncm91cE5hbWUSJgoPYWRtaW5fbWVtYmVyX2lkGAMgASgMUg1hZG1pbk1lbWJl'
    'cklk');

@$core.Deprecated('Use joinAcceptDescriptor instead')
const JoinAccept$json = {
  '1': 'JoinAccept',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'member_id', '3': 2, '4': 1, '5': 12, '10': 'memberId'},
    {'1': 'x25519_pub', '3': 3, '4': 1, '5': 12, '10': 'x25519Pub'},
    {'1': 'oh_id', '3': 4, '4': 1, '5': 12, '10': 'ohId'},
    {'1': 'oh_endpoint', '3': 5, '4': 1, '5': 9, '10': 'ohEndpoint'},
  ],
};

/// Descriptor for `JoinAccept`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List joinAcceptDescriptor = $convert.base64Decode(
    'CgpKb2luQWNjZXB0EhkKCGdyb3VwX2lkGAEgASgMUgdncm91cElkEhsKCW1lbWJlcl9pZBgCIA'
    'EoDFIIbWVtYmVySWQSHQoKeDI1NTE5X3B1YhgDIAEoDFIJeDI1NTE5UHViEhMKBW9oX2lkGAQg'
    'ASgMUgRvaElkEh8KC29oX2VuZHBvaW50GAUgASgJUgpvaEVuZHBvaW50');
