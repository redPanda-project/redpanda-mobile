import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';

void main() {
  group('MS01 Protobuf: FetchRequest/Response', () {
    test('FetchRequest roundtrip with all fields', () {
      final ohId = Uint8List.fromList(List.generate(20, (i) => i));
      final cursor = fixnum.Int64(0x01020304);
      final nonce = Uint8List.fromList(List.generate(16, (i) => i + 50));
      final sig = Uint8List.fromList(List.generate(64, (i) => i));

      final request = FetchRequest()
        ..ohId = ohId
        ..limit = 50
        ..cursor = cursor
        ..timestampMs = fixnum.Int64(1700000000000)
        ..nonce = nonce
        ..signature = sig;

      final buffer = request.writeToBuffer();
      final decoded = FetchRequest.fromBuffer(buffer);

      expect(decoded.ohId, equals(ohId));
      expect(decoded.limit, 50);
      expect(decoded.cursor.toInt(), 0x01020304);
      expect(decoded.timestampMs.toInt(), 1700000000000);
      expect(decoded.nonce, equals(nonce));
      expect(decoded.signature, equals(sig));
    });

    test('FetchResponse with MailItems', () {
      final item1 = MailItem()
        ..messageId = Uint8List.fromList([
          0x6D,
          0x73,
          0x67,
          0x2D,
          0x30,
          0x30,
          0x31,
        ])
        ..payload = Uint8List.fromList([1, 2, 3, 4, 5])
        ..receivedAtMs = fixnum.Int64(1700000001000);

      final item2 = MailItem()
        ..messageId = Uint8List.fromList([
          0x6D,
          0x73,
          0x67,
          0x2D,
          0x30,
          0x30,
          0x32,
        ])
        ..payload = Uint8List.fromList([6, 7, 8])
        ..receivedAtMs = fixnum.Int64(1700000002000);

      final response = FetchResponse()
        ..status = Status.OK
        ..nextCursor = fixnum.Int64(42)
        ..items.addAll([item1, item2]);

      final buffer = response.writeToBuffer();
      final decoded = FetchResponse.fromBuffer(buffer);

      expect(decoded.status, Status.OK);
      expect(decoded.items.length, 2);
      expect(
        decoded.items[0].messageId,
        equals([0x6D, 0x73, 0x67, 0x2D, 0x30, 0x30, 0x31]),
      );
      expect(decoded.items[0].payload, equals([1, 2, 3, 4, 5]));
      expect(decoded.items[0].receivedAtMs.toInt(), 1700000001000);
      expect(
        decoded.items[1].messageId,
        equals([0x6D, 0x73, 0x67, 0x2D, 0x30, 0x30, 0x32]),
      );
      expect(decoded.nextCursor.toInt(), 42);
    });

    test('FetchResponse with empty items list', () {
      final response = FetchResponse()
        ..status = Status.OK
        ..nextCursor = fixnum.Int64(0);

      final decoded = FetchResponse.fromBuffer(response.writeToBuffer());
      expect(decoded.items, isEmpty);
      expect(decoded.status, Status.OK);
    });
  });

  group('MS01 Protobuf: FlaschenpostPut', () {
    test('FlaschenpostPut with encrypted payload', () {
      final payload = Uint8List.fromList(List.generate(100, (i) => i));

      final fput = FlaschenpostPut()..content = payload;

      final buffer = fput.writeToBuffer();
      final decoded = FlaschenpostPut.fromBuffer(buffer);

      expect(decoded.content, equals(payload));
    });

    test('FlaschenpostPut content holds IV+ciphertext', () {
      // Simulate the payload structure from sendMessage():
      // [IV (16 bytes)][ciphertext (variable)]
      final iv = Uint8List.fromList(List.generate(16, (i) => i));
      final ciphertext = Uint8List.fromList(List.generate(50, (i) => i + 100));

      final payload = Uint8List(iv.length + ciphertext.length);
      payload.setRange(0, iv.length, iv);
      payload.setRange(iv.length, payload.length, ciphertext);

      final fput = FlaschenpostPut()..content = payload;
      final decoded = FlaschenpostPut.fromBuffer(fput.writeToBuffer());

      // Verify we can extract IV and ciphertext back
      final extractedIv = decoded.content.sublist(0, 16);
      final extractedCt = decoded.content.sublist(16);

      expect(extractedIv, equals(iv));
      expect(extractedCt, equals(ciphertext));
    });
  });

  group('MS01 Protobuf: MailItem', () {
    test('MailItem roundtrip', () {
      final msgId = Uint8List.fromList([0x75, 0x6E, 0x69, 0x71, 0x75, 0x65]);
      final item = MailItem()
        ..messageId = msgId
        ..payload = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])
        ..receivedAtMs = fixnum.Int64(1700000000000);

      final decoded = MailItem.fromBuffer(item.writeToBuffer());

      expect(decoded.messageId, equals(msgId));
      expect(decoded.payload, equals([0xDE, 0xAD, 0xBE, 0xEF]));
      expect(decoded.receivedAtMs.toInt(), 1700000000000);
    });
  });

  group('MS01 Protobuf: RegisterOhRequest', () {
    test('RegisterOhRequest roundtrip with all fields', () {
      final ohId = Uint8List.fromList(List.generate(20, (i) => i));
      final pubKey = Uint8List.fromList(List.generate(65, (i) => i));
      final nonce = Uint8List.fromList(List.generate(16, (i) => i + 100));
      final sig = Uint8List.fromList(List.generate(72, (i) => i));

      final request = RegisterOhRequest()
        ..ohId = ohId
        ..ohAuthPublicKey = pubKey
        ..requestedExpiresAt = fixnum.Int64(1700604800000)
        ..timestampMs = fixnum.Int64(1700000000000)
        ..nonce = nonce
        ..signature = sig;

      final decoded = RegisterOhRequest.fromBuffer(request.writeToBuffer());

      expect(decoded.ohId, equals(ohId));
      expect(decoded.ohAuthPublicKey, equals(pubKey));
      expect(decoded.requestedExpiresAt.toInt(), 1700604800000);
      expect(decoded.timestampMs.toInt(), 1700000000000);
      expect(decoded.nonce, equals(nonce));
      expect(decoded.signature, equals(sig));
    });
  });

  group('MS01 Protobuf: Status enum', () {
    test('all Status values are accessible', () {
      expect(Status.STATUS_UNSPECIFIED.value, 0);
      expect(Status.OK.value, 1);
      expect(Status.INVALID_SIGNATURE.value, 2);
      expect(Status.INVALID_TIMESTAMP.value, 3);
      expect(Status.REPLAY.value, 4);
      expect(Status.NOT_FOUND.value, 5);
      expect(Status.RATE_LIMIT.value, 6);
      expect(Status.QUOTA_EXCEEDED.value, 7);
      expect(Status.BAD_REQUEST.value, 8);
    });

    test('Status.valueOf resolves correctly', () {
      expect(Status.valueOf(0), Status.STATUS_UNSPECIFIED);
      expect(Status.valueOf(1), Status.OK);
      expect(Status.valueOf(2), Status.INVALID_SIGNATURE);
      expect(Status.valueOf(999), isNull);
    });
  });
}
