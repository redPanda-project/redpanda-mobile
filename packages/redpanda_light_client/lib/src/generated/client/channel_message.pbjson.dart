// This is a generated file - do not edit.
//
// Generated from client/channel_message.proto.

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

@$core.Deprecated('Use channelMessageDescriptor instead')
const ChannelMessage$json = {
  '1': 'ChannelMessage',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'content', '3': 3, '4': 1, '5': 9, '10': 'content'},
    {'1': 'reply_path', '3': 5, '4': 1, '5': 12, '10': 'replyPath'},
    {'1': 'ack_message_id', '3': 6, '4': 1, '5': 12, '10': 'ackMessageId'},
    {'1': 'group_handshake', '3': 7, '4': 1, '5': 12, '10': 'groupHandshake'},
    {'1': 'group_control', '3': 8, '4': 1, '5': 12, '10': 'groupControl'},
    {'1': 'oh_update', '3': 9, '4': 1, '5': 12, '10': 'ohUpdate'},
  ],
};

/// Descriptor for `ChannelMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelMessageDescriptor = $convert.base64Decode(
    'Cg5DaGFubmVsTWVzc2FnZRIdCgptZXNzYWdlX2lkGAEgASgMUgltZXNzYWdlSWQSIQoMdGltZX'
    'N0YW1wX21zGAIgASgDUgt0aW1lc3RhbXBNcxIYCgdjb250ZW50GAMgASgJUgdjb250ZW50Eh0K'
    'CnJlcGx5X3BhdGgYBSABKAxSCXJlcGx5UGF0aBIkCg5hY2tfbWVzc2FnZV9pZBgGIAEoDFIMYW'
    'NrTWVzc2FnZUlkEicKD2dyb3VwX2hhbmRzaGFrZRgHIAEoDFIOZ3JvdXBIYW5kc2hha2USIwoN'
    'Z3JvdXBfY29udHJvbBgIIAEoDFIMZ3JvdXBDb250cm9sEhsKCW9oX3VwZGF0ZRgJIAEoDFIIb2'
    'hVcGRhdGU=');
