import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';

import '../helpers/garlic_test_utils.dart';

void main() {
  late TestHop h1;
  late TestHop h2;
  late TestHop h3;
  final ohId = Uint8List.fromList(List<int>.generate(20, (i) => 100 + i));

  setUp(() async {
    h1 = await TestHop.generate(1);
    h2 = await TestHop.generate(2);
    h3 = await TestHop.generate(3);
  });

  Future<Uint8List> buildThreeHop(List<int> payload) => GarlicBuilder.build(
    hops: [h1.asGarlicHop, h2.asGarlicHop, h3.asGarlicHop],
    ohId: ohId,
    payload: payload,
  );

  group('GarlicBuilder format lock (Decisions Backend-MS04)', () {
    test(
      'packet is exactly 2048 bytes with the 73-byte header layout',
      () async {
        final payload = List<int>.generate(48, (i) => i);
        final packet = await buildThreeHop(payload);

        final parsed = ParsedPacket.parse(packet);
        expect(parsed.version, GarlicBuilder.version);
        expect(parsed.nextHop, equals(h1.nodeId));
        // ct_len counts the ciphertext INCLUDING the 16-byte GCM tag: the
        // outermost plaintext is 195 + payload bytes for a 3-hop path.
        expect(parsed.ciphertextLength, equals(195 + payload.length + 16));
      },
    );

    test('constants match the master spec', () {
      expect(GarlicBuilder.headerLength, 73);
      expect(GarlicBuilder.bodyHeaderLength, 48);
      expect(GarlicBuilder.maxCiphertextLength, 1975);
      expect(GarlicBuilder.minCiphertextLength, 17);
      expect(GarlicBuilder.forwardLayerOverhead, 85);
      // Decision 6: max. 1764-byte deliver payload over 3 hops.
      expect(GarlicBuilder.maxPayloadLength(3), 1764);
      expect(GarlicBuilder.maxPayloadLength(1), 1934);
    });

    test('three relays peel their layers and the last one sees CMD_DELIVER '
        'with oh_id and payload', () async {
      final payload = List<int>.generate(321, (i) => (7 * i) & 0xff);
      var packet = await buildThreeHop(payload);

      // Relay H1: peel CMD_FORWARD, rebuild for the inner next hop (H2).
      var plaintext = await ParsedPacket.parse(
        packet,
      ).decryptLayer(h1.keys.privateKey);
      expect(plaintext[0], GarlicBuilder.cmdForward);
      expect(plaintext.sublist(1, 21), equals(h2.nodeId));
      packet = GarlicBuilder.buildPacket(
        plaintext.sublist(1, 21),
        plaintext.sublist(21),
      );
      expect(packet.length, GarlicBuilder.packetSize);

      // Relay H2: peel CMD_FORWARD toward H3.
      plaintext = await ParsedPacket.parse(
        packet,
      ).decryptLayer(h2.keys.privateKey);
      expect(plaintext[0], GarlicBuilder.cmdForward);
      expect(plaintext.sublist(1, 21), equals(h3.nodeId));
      packet = GarlicBuilder.buildPacket(
        plaintext.sublist(1, 21),
        plaintext.sublist(21),
      );

      // Relay H3: peel CMD_DELIVER [1 cmd][20 oh_id][4 payload_len][payload].
      plaintext = await ParsedPacket.parse(
        packet,
      ).decryptLayer(h3.keys.privateKey);
      expect(plaintext[0], GarlicBuilder.cmdDeliver);
      expect(plaintext.sublist(1, 21), equals(ohId));
      final payloadLen = ByteData.sublistView(plaintext).getUint32(21);
      expect(payloadLen, payload.length);
      expect(plaintext.sublist(25, 25 + payloadLen), equals(payload));
    });

    test('single-hop packet carries CMD_DELIVER directly', () async {
      final payload = [1, 2, 3];
      final packet = await GarlicBuilder.build(
        hops: [h1.asGarlicHop],
        ohId: ohId,
        payload: payload,
      );
      final plaintext = await ParsedPacket.parse(
        packet,
      ).decryptLayer(h1.keys.privateKey);
      expect(plaintext[0], GarlicBuilder.cmdDeliver);
      expect(plaintext.sublist(1, 21), equals(ohId));
      expect(plaintext.sublist(25, 28), equals(payload));
    });

    test('the maximum 3-hop payload (1764 bytes) still fits exactly', () async {
      final payload = List<int>.filled(GarlicBuilder.maxPayloadLength(3), 9);
      final packet = await buildThreeHop(payload);
      // ct_len = 195 + 1764 + 16 = 1975 = maxCiphertextLength: zero padding.
      expect(
        ParsedPacket.parse(packet).ciphertextLength,
        GarlicBuilder.maxCiphertextLength,
      );
    });
  });

  group('GarlicBuilder negative paths', () {
    test('a relay that is not the addressed next hop cannot decrypt '
        '(AAD = next_hop)', () async {
      final packet = await buildThreeHop([1, 2, 3]);
      // H2 holds a valid key but the layer is bound to H1 via AAD/key.
      await expectLater(
        ParsedPacket.parse(packet).decryptLayer(h2.keys.privateKey),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test(
      'redirecting the packet to another relay breaks authentication',
      () async {
        final packet = await buildThreeHop([1, 2, 3]);
        // Tamper the next_hop header (the AAD): even the right hop must fail.
        packet.setRange(5, 25, h2.nodeId);
        await expectLater(
          ParsedPacket.parse(packet).decryptLayer(h1.keys.privateKey),
          throwsA(isA<GcmAuthenticationException>()),
        );
      },
    );

    test('payload above the path budget is rejected', () async {
      final tooBig = List<int>.filled(GarlicBuilder.maxPayloadLength(3) + 1, 0);
      await expectLater(buildThreeHop(tooBig), throwsArgumentError);
    });

    test('empty hop list and malformed oh_id are rejected', () async {
      await expectLater(
        GarlicBuilder.build(hops: [], ohId: ohId, payload: [1]),
        throwsArgumentError,
      );
      await expectLater(
        GarlicBuilder.build(
          hops: [h1.asGarlicHop],
          ohId: [1, 2, 3],
          payload: [1],
        ),
        throwsArgumentError,
      );
    });

    test('GarlicHop validates key and id lengths', () {
      expect(
        () => GarlicHop(nodeId: [1], encryptionPublicKey: List.filled(32, 0)),
        throwsArgumentError,
      );
      expect(
        () =>
            GarlicHop(nodeId: List.filled(20, 0), encryptionPublicKey: [1, 2]),
        throwsArgumentError,
      );
    });
  });
}
