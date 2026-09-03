import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/generated/outbound.pb.dart';

void main() {
  group('MS02: AckFetchRequest protobuf', () {
    test('round-trips all fields', () {
      final request = AckFetchRequest()
        ..ohId = List.generate(20, (i) => i)
        ..ackedSequenceId = fixnum.Int64(42)
        ..timestampMs = fixnum.Int64(1700000000000)
        ..nonce = List.generate(16, (i) => 255 - i)
        ..signature = [1, 2, 3, 4];

      final decoded = AckFetchRequest.fromBuffer(request.writeToBuffer());

      expect(decoded.ohId, equals(List.generate(20, (i) => i)));
      expect(decoded.ackedSequenceId.toInt(), equals(42));
      expect(decoded.timestampMs.toInt(), equals(1700000000000));
      expect(decoded.nonce, equals(List.generate(16, (i) => 255 - i)));
      expect(decoded.signature, equals([1, 2, 3, 4]));
    });

    test('handles sequence ids above 2^53 (beyond JS-safe doubles)', () {
      // 2^53 + 1 cannot be represented exactly as a double — relevant for
      // web builds where Dart ints are doubles.
      final request = AckFetchRequest()
        ..ackedSequenceId = fixnum.Int64.parseInt('9007199254740993');

      final decoded = AckFetchRequest.fromBuffer(request.writeToBuffer());
      expect(
        decoded.ackedSequenceId,
        equals(fixnum.Int64.parseInt('9007199254740993')),
      );
    });
  });

  group('MS02: AckFetchResponse protobuf', () {
    test('round-trips status and server time', () {
      final response = AckFetchResponse()
        ..status = Status.OK
        ..serverTimeMs = fixnum.Int64(1700000000123);

      final decoded = AckFetchResponse.fromBuffer(response.writeToBuffer());
      expect(decoded.status, equals(Status.OK));
      expect(decoded.serverTimeMs.toInt(), equals(1700000000123));
    });

    test('defaults to STATUS_UNSPECIFIED', () {
      final decoded = AckFetchResponse.fromBuffer(
        AckFetchResponse().writeToBuffer(),
      );
      expect(decoded.status, equals(Status.STATUS_UNSPECIFIED));
    });
  });

  group('MS02: MailItem.sequenceId', () {
    test('round-trips sequence id alongside existing fields', () {
      final item = MailItem()
        ..messageId = [9, 8, 7]
        ..receivedAtMs = fixnum.Int64(123456)
        ..payload = [1, 1, 2, 3, 5]
        ..sequenceId = fixnum.Int64(77);

      final decoded = MailItem.fromBuffer(item.writeToBuffer());
      expect(decoded.messageId, equals([9, 8, 7]));
      expect(decoded.receivedAtMs.toInt(), equals(123456));
      expect(decoded.payload, equals([1, 1, 2, 3, 5]));
      expect(decoded.sequenceId.toInt(), equals(77));
    });

    test('defaults to zero when absent', () {
      final decoded = MailItem.fromBuffer(MailItem().writeToBuffer());
      expect(decoded.sequenceId.toInt(), equals(0));
    });
  });

  group('MS02: FetchResponse.mailboxOverflow', () {
    test('round-trips overflow flag with items', () {
      final response = FetchResponse()
        ..status = Status.OK
        ..nextCursor = fixnum.Int64(10)
        ..mailboxOverflow = true
        ..items.add(MailItem()..sequenceId = fixnum.Int64(10));

      final decoded = FetchResponse.fromBuffer(response.writeToBuffer());
      expect(decoded.mailboxOverflow, isTrue);
      expect(decoded.nextCursor.toInt(), equals(10));
      expect(decoded.items.single.sequenceId.toInt(), equals(10));
    });

    test('defaults to false when absent (backwards compatible)', () {
      final decoded = FetchResponse.fromBuffer(
        (FetchResponse()..status = Status.OK).writeToBuffer(),
      );
      expect(decoded.mailboxOverflow, isFalse);
    });
  });
}
