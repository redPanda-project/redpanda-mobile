// This is a generated file - do not edit.
//
// Generated from outbound.proto.

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

@$core.Deprecated('Use statusDescriptor instead')
const Status$json = {
  '1': 'Status',
  '2': [
    {'1': 'STATUS_UNSPECIFIED', '2': 0},
    {'1': 'OK', '2': 1},
    {'1': 'INVALID_SIGNATURE', '2': 2},
    {'1': 'INVALID_TIMESTAMP', '2': 3},
    {'1': 'REPLAY', '2': 4},
    {'1': 'NOT_FOUND', '2': 5},
    {'1': 'RATE_LIMIT', '2': 6},
    {'1': 'QUOTA_EXCEEDED', '2': 7},
    {'1': 'BAD_REQUEST', '2': 8},
  ],
};

/// Descriptor for `Status`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List statusDescriptor = $convert.base64Decode(
    'CgZTdGF0dXMSFgoSU1RBVFVTX1VOU1BFQ0lGSUVEEAASBgoCT0sQARIVChFJTlZBTElEX1NJR0'
    '5BVFVSRRACEhUKEUlOVkFMSURfVElNRVNUQU1QEAMSCgoGUkVQTEFZEAQSDQoJTk9UX0ZPVU5E'
    'EAUSDgoKUkFURV9MSU1JVBAGEhIKDlFVT1RBX0VYQ0VFREVEEAcSDwoLQkFEX1JFUVVFU1QQCA'
    '==');

@$core.Deprecated('Use registerOhRequestDescriptor instead')
const RegisterOhRequest$json = {
  '1': 'RegisterOhRequest',
  '2': [
    {'1': 'oh_id', '3': 1, '4': 1, '5': 12, '10': 'ohId'},
    {
      '1': 'oh_auth_public_key',
      '3': 2,
      '4': 1,
      '5': 12,
      '10': 'ohAuthPublicKey'
    },
    {
      '1': 'requested_expires_at',
      '3': 3,
      '4': 1,
      '5': 3,
      '10': 'requestedExpiresAt'
    },
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'nonce', '3': 5, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'signature', '3': 6, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `RegisterOhRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerOhRequestDescriptor = $convert.base64Decode(
    'ChFSZWdpc3Rlck9oUmVxdWVzdBITCgVvaF9pZBgBIAEoDFIEb2hJZBIrChJvaF9hdXRoX3B1Ym'
    'xpY19rZXkYAiABKAxSD29oQXV0aFB1YmxpY0tleRIwChRyZXF1ZXN0ZWRfZXhwaXJlc19hdBgD'
    'IAEoA1IScmVxdWVzdGVkRXhwaXJlc0F0EiEKDHRpbWVzdGFtcF9tcxgEIAEoA1ILdGltZXN0YW'
    '1wTXMSFAoFbm9uY2UYBSABKAxSBW5vbmNlEhwKCXNpZ25hdHVyZRgGIAEoDFIJc2lnbmF0dXJl');

@$core.Deprecated('Use registerOhResponseDescriptor instead')
const RegisterOhResponse$json = {
  '1': 'RegisterOhResponse',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.im.redpanda.outbound.v1.Status',
      '10': 'status'
    },
    {'1': 'server_time_ms', '3': 2, '4': 1, '5': 3, '10': 'serverTimeMs'},
    {'1': 'expires_at_ms', '3': 3, '4': 1, '5': 3, '10': 'expiresAtMs'},
  ],
};

/// Descriptor for `RegisterOhResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerOhResponseDescriptor = $convert.base64Decode(
    'ChJSZWdpc3Rlck9oUmVzcG9uc2USNwoGc3RhdHVzGAEgASgOMh8uaW0ucmVkcGFuZGEub3V0Ym'
    '91bmQudjEuU3RhdHVzUgZzdGF0dXMSJAoOc2VydmVyX3RpbWVfbXMYAiABKANSDHNlcnZlclRp'
    'bWVNcxIiCg1leHBpcmVzX2F0X21zGAMgASgDUgtleHBpcmVzQXRNcw==');

@$core.Deprecated('Use fetchRequestDescriptor instead')
const FetchRequest$json = {
  '1': 'FetchRequest',
  '2': [
    {'1': 'oh_id', '3': 1, '4': 1, '5': 12, '10': 'ohId'},
    {'1': 'limit', '3': 2, '4': 1, '5': 13, '10': 'limit'},
    {'1': 'cursor', '3': 3, '4': 1, '5': 4, '10': 'cursor'},
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'nonce', '3': 5, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'signature', '3': 6, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `FetchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fetchRequestDescriptor = $convert.base64Decode(
    'CgxGZXRjaFJlcXVlc3QSEwoFb2hfaWQYASABKAxSBG9oSWQSFAoFbGltaXQYAiABKA1SBWxpbW'
    'l0EhYKBmN1cnNvchgDIAEoBFIGY3Vyc29yEiEKDHRpbWVzdGFtcF9tcxgEIAEoA1ILdGltZXN0'
    'YW1wTXMSFAoFbm9uY2UYBSABKAxSBW5vbmNlEhwKCXNpZ25hdHVyZRgGIAEoDFIJc2lnbmF0dX'
    'Jl');

@$core.Deprecated('Use mailItemDescriptor instead')
const MailItem$json = {
  '1': 'MailItem',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'received_at_ms', '3': 2, '4': 1, '5': 3, '10': 'receivedAtMs'},
    {'1': 'payload', '3': 3, '4': 1, '5': 12, '10': 'payload'},
    {'1': 'sequence_id', '3': 4, '4': 1, '5': 4, '10': 'sequenceId'},
    {'1': 'session_tag', '3': 5, '4': 1, '5': 12, '10': 'sessionTag'},
  ],
};

/// Descriptor for `MailItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mailItemDescriptor = $convert.base64Decode(
    'CghNYWlsSXRlbRIdCgptZXNzYWdlX2lkGAEgASgMUgltZXNzYWdlSWQSJAoOcmVjZWl2ZWRfYX'
    'RfbXMYAiABKANSDHJlY2VpdmVkQXRNcxIYCgdwYXlsb2FkGAMgASgMUgdwYXlsb2FkEh8KC3Nl'
    'cXVlbmNlX2lkGAQgASgEUgpzZXF1ZW5jZUlkEh8KC3Nlc3Npb25fdGFnGAUgASgMUgpzZXNzaW'
    '9uVGFn');

@$core.Deprecated('Use fetchResponseDescriptor instead')
const FetchResponse$json = {
  '1': 'FetchResponse',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.im.redpanda.outbound.v1.Status',
      '10': 'status'
    },
    {'1': 'next_cursor', '3': 2, '4': 1, '5': 4, '10': 'nextCursor'},
    {
      '1': 'items',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.im.redpanda.outbound.v1.MailItem',
      '10': 'items'
    },
    {'1': 'server_time_ms', '3': 4, '4': 1, '5': 3, '10': 'serverTimeMs'},
    {'1': 'mailbox_overflow', '3': 5, '4': 1, '5': 8, '10': 'mailboxOverflow'},
  ],
};

/// Descriptor for `FetchResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fetchResponseDescriptor = $convert.base64Decode(
    'Cg1GZXRjaFJlc3BvbnNlEjcKBnN0YXR1cxgBIAEoDjIfLmltLnJlZHBhbmRhLm91dGJvdW5kLn'
    'YxLlN0YXR1c1IGc3RhdHVzEh8KC25leHRfY3Vyc29yGAIgASgEUgpuZXh0Q3Vyc29yEjcKBWl0'
    'ZW1zGAMgAygLMiEuaW0ucmVkcGFuZGEub3V0Ym91bmQudjEuTWFpbEl0ZW1SBWl0ZW1zEiQKDn'
    'NlcnZlcl90aW1lX21zGAQgASgDUgxzZXJ2ZXJUaW1lTXMSKQoQbWFpbGJveF9vdmVyZmxvdxgF'
    'IAEoCFIPbWFpbGJveE92ZXJmbG93');

@$core.Deprecated('Use ackFetchRequestDescriptor instead')
const AckFetchRequest$json = {
  '1': 'AckFetchRequest',
  '2': [
    {'1': 'oh_id', '3': 1, '4': 1, '5': 12, '10': 'ohId'},
    {'1': 'acked_sequence_id', '3': 2, '4': 1, '5': 4, '10': 'ackedSequenceId'},
    {'1': 'timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'nonce', '3': 4, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'signature', '3': 5, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `AckFetchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackFetchRequestDescriptor = $convert.base64Decode(
    'Cg9BY2tGZXRjaFJlcXVlc3QSEwoFb2hfaWQYASABKAxSBG9oSWQSKgoRYWNrZWRfc2VxdWVuY2'
    'VfaWQYAiABKARSD2Fja2VkU2VxdWVuY2VJZBIhCgx0aW1lc3RhbXBfbXMYAyABKANSC3RpbWVz'
    'dGFtcE1zEhQKBW5vbmNlGAQgASgMUgVub25jZRIcCglzaWduYXR1cmUYBSABKAxSCXNpZ25hdH'
    'VyZQ==');

@$core.Deprecated('Use ackFetchResponseDescriptor instead')
const AckFetchResponse$json = {
  '1': 'AckFetchResponse',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.im.redpanda.outbound.v1.Status',
      '10': 'status'
    },
    {'1': 'server_time_ms', '3': 2, '4': 1, '5': 3, '10': 'serverTimeMs'},
  ],
};

/// Descriptor for `AckFetchResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackFetchResponseDescriptor = $convert.base64Decode(
    'ChBBY2tGZXRjaFJlc3BvbnNlEjcKBnN0YXR1cxgBIAEoDjIfLmltLnJlZHBhbmRhLm91dGJvdW'
    '5kLnYxLlN0YXR1c1IGc3RhdHVzEiQKDnNlcnZlcl90aW1lX21zGAIgASgDUgxzZXJ2ZXJUaW1l'
    'TXM=');

@$core.Deprecated('Use flaschenpostPutResponseDescriptor instead')
const FlaschenpostPutResponse$json = {
  '1': 'FlaschenpostPutResponse',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.im.redpanda.outbound.v1.Status',
      '10': 'status'
    },
    {'1': 'server_time_ms', '3': 2, '4': 1, '5': 3, '10': 'serverTimeMs'},
  ],
};

/// Descriptor for `FlaschenpostPutResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List flaschenpostPutResponseDescriptor = $convert.base64Decode(
    'ChdGbGFzY2hlbnBvc3RQdXRSZXNwb25zZRI3CgZzdGF0dXMYASABKA4yHy5pbS5yZWRwYW5kYS'
    '5vdXRib3VuZC52MS5TdGF0dXNSBnN0YXR1cxIkCg5zZXJ2ZXJfdGltZV9tcxgCIAEoA1IMc2Vy'
    'dmVyVGltZU1z');

@$core.Deprecated('Use ohNodeRecordDescriptor instead')
const OhNodeRecord$json = {
  '1': 'OhNodeRecord',
  '2': [
    {'1': 'oh_id_hash', '3': 1, '4': 1, '5': 12, '10': 'ohIdHash'},
    {'1': 'node_id', '3': 2, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'endpoint', '3': 3, '4': 1, '5': 9, '10': 'endpoint'},
    {'1': 'announced_at_ms', '3': 4, '4': 1, '5': 3, '10': 'announcedAtMs'},
    {'1': 'padding', '3': 5, '4': 1, '5': 12, '10': 'padding'},
  ],
};

/// Descriptor for `OhNodeRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ohNodeRecordDescriptor = $convert.base64Decode(
    'CgxPaE5vZGVSZWNvcmQSHAoKb2hfaWRfaGFzaBgBIAEoDFIIb2hJZEhhc2gSFwoHbm9kZV9pZB'
    'gCIAEoDFIGbm9kZUlkEhoKCGVuZHBvaW50GAMgASgJUghlbmRwb2ludBImCg9hbm5vdW5jZWRf'
    'YXRfbXMYBCABKANSDWFubm91bmNlZEF0TXMSGAoHcGFkZGluZxgFIAEoDFIHcGFkZGluZw==');

@$core.Deprecated('Use routingAckDescriptor instead')
const RoutingAck$json = {
  '1': 'RoutingAck',
  '2': [
    {'1': 'timestamp_ms', '3': 1, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'status', '3': 2, '4': 1, '5': 13, '10': 'status'},
  ],
};

/// Descriptor for `RoutingAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List routingAckDescriptor = $convert.base64Decode(
    'CgpSb3V0aW5nQWNrEiEKDHRpbWVzdGFtcF9tcxgBIAEoA1ILdGltZXN0YW1wTXMSFgoGc3RhdH'
    'VzGAIgASgNUgZzdGF0dXM=');

@$core.Deprecated('Use revokeOhRequestDescriptor instead')
const RevokeOhRequest$json = {
  '1': 'RevokeOhRequest',
  '2': [
    {'1': 'oh_id', '3': 1, '4': 1, '5': 12, '10': 'ohId'},
    {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'nonce', '3': 3, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'signature', '3': 4, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `RevokeOhRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeOhRequestDescriptor = $convert.base64Decode(
    'Cg9SZXZva2VPaFJlcXVlc3QSEwoFb2hfaWQYASABKAxSBG9oSWQSIQoMdGltZXN0YW1wX21zGA'
    'IgASgDUgt0aW1lc3RhbXBNcxIUCgVub25jZRgDIAEoDFIFbm9uY2USHAoJc2lnbmF0dXJlGAQg'
    'ASgMUglzaWduYXR1cmU=');

@$core.Deprecated('Use revokeOhResponseDescriptor instead')
const RevokeOhResponse$json = {
  '1': 'RevokeOhResponse',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.im.redpanda.outbound.v1.Status',
      '10': 'status'
    },
    {'1': 'server_time_ms', '3': 2, '4': 1, '5': 3, '10': 'serverTimeMs'},
  ],
};

/// Descriptor for `RevokeOhResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeOhResponseDescriptor = $convert.base64Decode(
    'ChBSZXZva2VPaFJlc3BvbnNlEjcKBnN0YXR1cxgBIAEoDjIfLmltLnJlZHBhbmRhLm91dGJvdW'
    '5kLnYxLlN0YXR1c1IGc3RhdHVzEiQKDnNlcnZlcl90aW1lX21zGAIgASgDUgxzZXJ2ZXJUaW1l'
    'TXM=');

@$core.Deprecated('Use subscribeRequestDescriptor instead')
const SubscribeRequest$json = {
  '1': 'SubscribeRequest',
  '2': [
    {'1': 'oh_id', '3': 1, '4': 1, '5': 12, '10': 'ohId'},
    {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'nonce', '3': 3, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'signature', '3': 4, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `SubscribeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List subscribeRequestDescriptor = $convert.base64Decode(
    'ChBTdWJzY3JpYmVSZXF1ZXN0EhMKBW9oX2lkGAEgASgMUgRvaElkEiEKDHRpbWVzdGFtcF9tcx'
    'gCIAEoA1ILdGltZXN0YW1wTXMSFAoFbm9uY2UYAyABKAxSBW5vbmNlEhwKCXNpZ25hdHVyZRgE'
    'IAEoDFIJc2lnbmF0dXJl');

@$core.Deprecated('Use subscribeResponseDescriptor instead')
const SubscribeResponse$json = {
  '1': 'SubscribeResponse',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.im.redpanda.outbound.v1.Status',
      '10': 'status'
    },
    {'1': 'server_time_ms', '3': 2, '4': 1, '5': 3, '10': 'serverTimeMs'},
  ],
};

/// Descriptor for `SubscribeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List subscribeResponseDescriptor = $convert.base64Decode(
    'ChFTdWJzY3JpYmVSZXNwb25zZRI3CgZzdGF0dXMYASABKA4yHy5pbS5yZWRwYW5kYS5vdXRib3'
    'VuZC52MS5TdGF0dXNSBnN0YXR1cxIkCg5zZXJ2ZXJfdGltZV9tcxgCIAEoA1IMc2VydmVyVGlt'
    'ZU1z');

@$core.Deprecated('Use notifyDescriptor instead')
const Notify$json = {
  '1': 'Notify',
  '2': [
    {'1': 'oh_id', '3': 1, '4': 1, '5': 12, '10': 'ohId'},
  ],
};

/// Descriptor for `Notify`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List notifyDescriptor =
    $convert.base64Decode('CgZOb3RpZnkSEwoFb2hfaWQYASABKAxSBG9oSWQ=');
