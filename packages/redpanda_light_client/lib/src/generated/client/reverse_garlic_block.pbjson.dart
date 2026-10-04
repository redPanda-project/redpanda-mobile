// This is a generated file - do not edit.
//
// Generated from client/reverse_garlic_block.proto.

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

@$core.Deprecated('Use reverseGarlicBlockDescriptor instead')
const ReverseGarlicBlock$json = {
  '1': 'ReverseGarlicBlock',
  '2': [
    {
      '1': 'version',
      '3': 1,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'version',
      '17': true
    },
    {
      '1': 'expiry_ts',
      '3': 2,
      '4': 1,
      '5': 3,
      '9': 1,
      '10': 'expiryTs',
      '17': true
    },
    {'1': 'session_tag', '3': 3, '4': 1, '5': 12, '10': 'sessionTag'},
    {'1': 'oh_id', '3': 4, '4': 1, '5': 12, '10': 'ohId'},
    {
      '1': 'hops',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.im.redpanda.client.v1.RgbHop',
      '10': 'hops'
    },
  ],
  '8': [
    {'1': '_version'},
    {'1': '_expiry_ts'},
  ],
};

/// Descriptor for `ReverseGarlicBlock`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reverseGarlicBlockDescriptor = $convert.base64Decode(
    'ChJSZXZlcnNlR2FybGljQmxvY2sSHQoHdmVyc2lvbhgBIAEoDUgAUgd2ZXJzaW9uiAEBEiAKCW'
    'V4cGlyeV90cxgCIAEoA0gBUghleHBpcnlUc4gBARIfCgtzZXNzaW9uX3RhZxgDIAEoDFIKc2Vz'
    'c2lvblRhZxITCgVvaF9pZBgEIAEoDFIEb2hJZBIxCgRob3BzGAUgAygLMh0uaW0ucmVkcGFuZG'
    'EuY2xpZW50LnYxLlJnYkhvcFIEaG9wc0IKCghfdmVyc2lvbkIMCgpfZXhwaXJ5X3Rz');

@$core.Deprecated('Use rgbHopDescriptor instead')
const RgbHop$json = {
  '1': 'RgbHop',
  '2': [
    {'1': 'kad_id', '3': 1, '4': 1, '5': 12, '10': 'kadId'},
    {'1': 'enc_pub', '3': 2, '4': 1, '5': 12, '10': 'encPub'},
  ],
};

/// Descriptor for `RgbHop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rgbHopDescriptor = $convert.base64Decode(
    'CgZSZ2JIb3ASFQoGa2FkX2lkGAEgASgMUgVrYWRJZBIXCgdlbmNfcHViGAIgASgMUgZlbmNQdW'
    'I=');
