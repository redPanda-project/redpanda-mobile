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
      // MS05 Decisions 1+7: CMD_DELIVER_TAGGED (0x03), 41-byte header,
      // max. 1748-byte tagged reply payload over 3 hops.
      expect(GarlicBuilder.cmdDeliverTagged, 0x03);
      expect(GarlicBuilder.sessionTagLength, 16);
      expect(GarlicBuilder.taggedDeliverHeaderLength, 41);
      expect(GarlicBuilder.maxPayloadLength(3, tagged: true), 1748);
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

    test('tagged deliver (MS05): the last relay sees CMD_DELIVER_TAGGED with '
        'oh_id, session_tag and payload', () async {
      final payload = List<int>.generate(99, (i) => (3 * i) & 0xff);
      final sessionTag = List<int>.generate(16, (i) => 0xF0 + i);
      var packet = await GarlicBuilder.build(
        hops: [h1.asGarlicHop, h2.asGarlicHop, h3.asGarlicHop],
        ohId: ohId,
        payload: payload,
        sessionTag: sessionTag,
      );

      // Relays H1/H2 peel ordinary CMD_FORWARD layers — the reverse path
      // is invisible to them (no reverse special-casing, MS05 Decision 4).
      for (final hop in [h1, h2]) {
        final plaintext = await ParsedPacket.parse(
          packet,
        ).decryptLayer(hop.keys.privateKey);
        expect(plaintext[0], GarlicBuilder.cmdForward);
        packet = GarlicBuilder.buildPacket(
          plaintext.sublist(1, 21),
          plaintext.sublist(21),
        );
      }

      // H3: [1 cmd=0x03][20 oh_id][16 session_tag][4 payload_len][payload].
      final plaintext = await ParsedPacket.parse(
        packet,
      ).decryptLayer(h3.keys.privateKey);
      expect(plaintext[0], GarlicBuilder.cmdDeliverTagged);
      expect(plaintext.sublist(1, 21), equals(ohId));
      expect(plaintext.sublist(21, 37), equals(sessionTag));
      final payloadLen = ByteData.sublistView(plaintext).getUint32(37);
      expect(payloadLen, payload.length);
      expect(plaintext.sublist(41, 41 + payloadLen), equals(payload));
    });

    test(
      'the maximum tagged 3-hop payload (1748 bytes) fits exactly',
      () async {
        final payload = List<int>.filled(
          GarlicBuilder.maxPayloadLength(3, tagged: true),
          7,
        );
        final packet = await GarlicBuilder.build(
          hops: [h1.asGarlicHop, h2.asGarlicHop, h3.asGarlicHop],
          ohId: ohId,
          payload: payload,
          sessionTag: List<int>.filled(16, 1),
        );
        expect(
          ParsedPacket.parse(packet).ciphertextLength,
          GarlicBuilder.maxCiphertextLength,
        );
      },
    );

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

    test(
      'tagged payload above the smaller tagged budget is rejected',
      () async {
        final tooBig = List<int>.filled(
          GarlicBuilder.maxPayloadLength(3, tagged: true) + 1,
          0,
        );
        await expectLater(
          GarlicBuilder.build(
            hops: [h1.asGarlicHop, h2.asGarlicHop, h3.asGarlicHop],
            ohId: ohId,
            payload: tooBig,
            sessionTag: List<int>.filled(16, 1),
          ),
          throwsArgumentError,
        );
      },
    );

    test('session tags must be exactly 16 bytes', () async {
      for (final badTag in [
        <int>[],
        List<int>.filled(15, 1),
        List<int>.filled(17, 1),
      ]) {
        await expectLater(
          GarlicBuilder.build(
            hops: [h1.asGarlicHop],
            ohId: ohId,
            payload: [1],
            sessionTag: badTag,
          ),
          throwsArgumentError,
        );
      }
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
