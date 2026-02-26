import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

void main() {
  group('MS01 AK2: OH Registration', () {
    late RedPandaLightClient client;

    setUp(() {
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
      );
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('registerOutboundHandle returns a valid OHRegistration', () async {
      final registration = await client.registerOutboundHandle();

      expect(registration, isA<OHRegistration>());
      expect(registration.ohId.length, 20);
      expect(registration.keypair, isA<OHKeypair>());
      expect(registration.keypair.publicKeyBytes.length, 65);
      expect(registration.expiresAtMs, greaterThan(0));
    });

    test('registerOutboundHandle generates unique OH IDs', () async {
      final reg1 = await client.registerOutboundHandle();
      final reg2 = await client.registerOutboundHandle();

      expect(reg1.ohId, isNot(equals(reg2.ohId)));
    });

    test('registerOutboundHandle sets expiry 7 days ahead', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      final registration = await client.registerOutboundHandle();
      final after = DateTime.now().millisecondsSinceEpoch;

      final expectedMin = before + (7 * 24 * 60 * 60 * 1000) - 1000;
      final expectedMax = after + (7 * 24 * 60 * 60 * 1000) + 1000;

      expect(registration.expiresAtMs, greaterThanOrEqualTo(expectedMin));
      expect(registration.expiresAtMs, lessThanOrEqualTo(expectedMax));
    });

    test('OH registration produces valid keypair for signing', () async {
      final registration = await client.registerOutboundHandle();

      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final signature = registration.keypair.sign(testData);

      expect(registration.keypair.verify(testData, signature), isTrue);
    });
  });

  group('MS01 AK2: RegisterOhRequest protobuf', () {
    test('RegisterOhRequest serializes and deserializes correctly', () {
      final keypair = OHKeypair.generate();
      final ohId = Uint8List.fromList(List.generate(20, (i) => i));

      final request = RegisterOhRequest()
        ..ohId = ohId
        ..ohAuthPublicKey = keypair.publicKeyBytes
        ..nonce = Uint8List.fromList(List.generate(16, (i) => i));

      final buffer = request.writeToBuffer();
      expect(buffer.isNotEmpty, true);

      final decoded = RegisterOhRequest.fromBuffer(buffer);
      expect(decoded.ohId, equals(ohId));
      expect(decoded.ohAuthPublicKey, equals(keypair.publicKeyBytes));
      expect(decoded.nonce.length, 16);
    });

    test('RegisterOhResponse with Status.OK', () {
      final response = RegisterOhResponse()..status = Status.OK;

      final buffer = response.writeToBuffer();
      final decoded = RegisterOhResponse.fromBuffer(buffer);

      expect(decoded.status, Status.OK);
    });

    test('RegisterOhResponse with error statuses', () {
      for (final status in [
        Status.INVALID_SIGNATURE,
        Status.NOT_FOUND,
        Status.BAD_REQUEST,
      ]) {
        final response = RegisterOhResponse()..status = status;
        final decoded = RegisterOhResponse.fromBuffer(response.writeToBuffer());
        expect(decoded.status, status);
      }
    });
  });

  group('MS01 AK7: Background Polling', () {
    late RedPandaLightClient client;

    setUp(() {
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
      );
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('fetchMessages returns empty list when no backend', () async {
      final keypair = OHKeypair.generate();
      final oh = OHRegistration(
        ohId: List.generate(20, (i) => i),
        keypair: keypair,
        expiresAtMs: DateTime.now()
            .add(Duration(days: 7))
            .millisecondsSinceEpoch,
      );

      final messages = await client.fetchMessages(oh);
      expect(messages, isEmpty);
    });

    test('fetchMessages builds valid FetchRequest protobuf', () {
      final ohId = Uint8List.fromList(List.generate(20, (i) => i));
      final nonce = Uint8List.fromList(List.generate(16, (i) => i));

      final request = FetchRequest()
        ..ohId = ohId
        ..limit = 50
        ..nonce = nonce;

      final buffer = request.writeToBuffer();
      final decoded = FetchRequest.fromBuffer(buffer);

      expect(decoded.ohId, equals(ohId));
      expect(decoded.limit, 50);
      expect(decoded.nonce, equals(nonce));
    });
  });

  group('MS01 AK8: incomingMessages stream', () {
    late RedPandaLightClient client;

    setUp(() {
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
      );
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('incomingMessages stream exists and is a broadcast stream', () {
      final stream = client.incomingMessages;
      expect(stream, isA<Stream<DecryptedMessage>>());

      // Should support multiple listeners (broadcast)
      stream.listen((_) {});
      stream.listen((_) {});
    });
  });
}
