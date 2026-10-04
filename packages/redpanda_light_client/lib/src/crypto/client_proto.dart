import 'package:protobuf/protobuf.dart' as pb_runtime;

/// Parses [bytes] with a generated `fromBuffer` and maps every parse failure
/// to the [FormatException] the callers of the client codecs catch.
///
/// protobuf 6.x does not report all malformed input as
/// [pb_runtime.InvalidProtocolBufferException]: a negative length prefix
/// (e.g. `0a ff ff ff ff 0f`) surfaces as a [RangeError] from the bytes/string
/// readers or an [ArgumentError] from the embedded-message reader. Those are
/// [Error]s and would slip past the `on FormatException` handlers on the
/// receive paths — one crafted item from a channel partner or group member
/// must not abort a fetch loop (T142 review).
T decodeClientProto<T>(
  List<int> bytes,
  T Function(List<int>) fromBuffer,
  String what,
) {
  try {
    return fromBuffer(bytes);
  } on pb_runtime.InvalidProtocolBufferException catch (e) {
    throw FormatException('$what: ${e.message}');
  } on ArgumentError catch (e) {
    // RangeError is an ArgumentError.
    throw FormatException('$what: malformed input (${e.message})');
  }
}
