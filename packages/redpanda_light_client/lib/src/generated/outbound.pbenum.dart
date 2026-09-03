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

import 'package:protobuf/protobuf.dart' as $pb;

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

  static final $core.List<Status?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 8);
  static Status? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Status._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
