import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import 'package:redpanda_light_client/src/generated/commands.pb.dart';

void main() {
  group('MS01 Protobuf: FetchRequest/Response', () {
    test('FetchRequest roundtrip with all fields', () {
      final ohId = Uint8List.fromList(List.generate(32, (i) => i));
      final cursor = Uint8List.fromList([1, 2, 3, 4]);
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
      expect(decoded.cursor, equals(cursor));
      expect(decoded.timestampMs.toInt(), 1700000000000);
      expect(decoded.nonce, equals(nonce));
      expect(decoded.signature, equals(sig));
    });

    test('FetchResponse with MailItems', () {
      final item1 = MailItem()
        ..messageId = 'msg-001'
        ..payload = Uint8List.fromList([1, 2, 3, 4, 5])
        ..receivedAtMs = fixnum.Int64(1700000001000);

      final item2 = MailItem()
        ..messageId = 'msg-002'
        ..payload = Uint8List.fromList([6, 7, 8])
        ..receivedAtMs = fixnum.Int64(1700000002000);

      final response = FetchResponse()
        ..status = Status.OK
        ..items.addAll([item1, item2])
        ..nextCursor = Uint8List.fromList([10, 20]);

      final buffer = response.writeToBuffer();
      final decoded = FetchResponse.fromBuffer(buffer);

      expect(decoded.status, Status.OK);
      expect(decoded.items.length, 2);
      expect(decoded.items[0].messageId, 'msg-001');
      expect(decoded.items[0].payload, equals([1, 2, 3, 4, 5]));
      expect(decoded.items[0].receivedAtMs.toInt(), 1700000001000);
      expect(decoded.items[1].messageId, 'msg-002');
      expect(decoded.nextCursor, equals([10, 20]));
    });

    test('FetchResponse with empty items list', () {
      final response = FetchResponse()
        ..status = Status.OK
        ..nextCursor = Uint8List.fromList([]);

      final decoded = FetchResponse.fromBuffer(response.writeToBuffer());
      expect(decoded.items, isEmpty);
      expect(decoded.status, Status.OK);
    });
  });

  group('MS01 Protobuf: FlaschenpostPut', () {
    test('FlaschenpostPut with encrypted payload', () {
      final payload = Uint8List.fromList(List.generate(100, (i) => i));
      final ohId = Uint8List.fromList(List.generate(32, (i) => 0xFF - i));

      final fput = FlaschenpostPut()
        ..content = payload
        ..ohId = ohId;

      final buffer = fput.writeToBuffer();
      final decoded = FlaschenpostPut.fromBuffer(buffer);

      expect(decoded.content, equals(payload));
      expect(decoded.ohId, equals(ohId));
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
      final item = MailItem()
        ..messageId = 'unique-id-123'
        ..payload = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])
        ..receivedAtMs = fixnum.Int64(1700000000000);

      final decoded = MailItem.fromBuffer(item.writeToBuffer());

      expect(decoded.messageId, 'unique-id-123');
      expect(decoded.payload, equals([0xDE, 0xAD, 0xBE, 0xEF]));
      expect(decoded.receivedAtMs.toInt(), 1700000000000);
    });
  });

  group('MS01 Protobuf: RegisterOhRequest', () {
    test('RegisterOhRequest roundtrip with all fields', () {
      final ohId = Uint8List.fromList(List.generate(32, (i) => i));
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
      expect(Status.UNKNOWN.value, 0);
      expect(Status.OK.value, 1);
      expect(Status.ERROR.value, 2);
      expect(Status.NOT_FOUND.value, 3);
      expect(Status.UNAUTHORIZED.value, 4);
    });

    test('Status.valueOf resolves correctly', () {
      expect(Status.valueOf(0), Status.UNKNOWN);
      expect(Status.valueOf(1), Status.OK);
      expect(Status.valueOf(2), Status.ERROR);
      expect(Status.valueOf(999), isNull);
    });
  });
}
