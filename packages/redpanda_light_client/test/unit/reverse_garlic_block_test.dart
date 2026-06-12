import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/domain/reverse_garlic_block.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';

void main() {
  final sessionTag = Uint8List.fromList(List<int>.generate(16, (i) => i));
  final ohId = Uint8List.fromList(List<int>.generate(20, (i) => 100 + i));

  GarlicHop hop(int seed) => GarlicHop(
    nodeId: List<int>.filled(20, seed),
    encryptionPublicKey: List<int>.filled(32, seed + 1),
  );

  ReverseGarlicBlock sample({int? expiryTs, List<GarlicHop>? hops}) =>
      ReverseGarlicBlock(
        expiryTs: expiryTs ?? 1765000000000,
        sessionTag: sessionTag,
        ohId: ohId,
        hops: hops ?? [hop(1), hop(2), hop(3)],
      );

  group('ReverseGarlicBlock codec', () {
    test('serialize → deserialize roundtrip preserves all fields', () {
      final rgb = sample();
      final decoded = ReverseGarlicBlock.deserialize(rgb.serialize());

      expect(decoded.version, ReverseGarlicBlock.currentVersion);
      expect(decoded.expiryTs, rgb.expiryTs);
      expect(decoded.sessionTag, equals(sessionTag));
      expect(decoded.ohId, equals(ohId));
      expect(decoded.hops, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(decoded.hops[i].nodeId, equals(rgb.hops[i].nodeId));
        expect(
          decoded.hops[i].encryptionPublicKey,
          equals(rgb.hops[i].encryptionPublicKey),
        );
      }
    });

    test('a 3-hop RGB stays small enough for the ChannelMessage budget '
        '(master spec MS05, Decision 7 estimated ~205 B; actual 223 B)', () {
      expect(sample().serialize().length, lessThanOrEqualTo(230));
    });

    test('skips unknown fields (forward compatibility)', () {
      // Append an unknown varint field #15: tag (15<<3|0)=0x78, value 1.
      final bytes = Uint8List.fromList([...sample().serialize(), 0x78, 0x01]);
      expect(
        ReverseGarlicBlock.deserialize(bytes).sessionTag,
        equals(sessionTag),
      );
    });

    test('isExpired honors expiry_ts', () {
      final rgb = sample(expiryTs: 5000);
      expect(rgb.isExpired(4999), isFalse);
      expect(rgb.isExpired(5000), isTrue);
      expect(sample(expiryTs: 1).isExpired(), isTrue);
    });

    test('sessionTagHex is the lowercase hex of the tag', () {
      expect(sample().sessionTagHex, '000102030405060708090a0b0c0d0e0f');
    });
  });

  group('ReverseGarlicBlock negative paths', () {
    test('rejects malformed tag, oh_id, hop lengths and empty hop list', () {
      expect(
        () => ReverseGarlicBlock(
          expiryTs: 1,
          sessionTag: List<int>.filled(15, 0),
          ohId: ohId,
          hops: [hop(1)],
        ),
        throwsFormatException,
      );
      expect(
        () => ReverseGarlicBlock(
          expiryTs: 1,
          sessionTag: sessionTag,
          ohId: List<int>.filled(19, 0),
          hops: [hop(1)],
        ),
        throwsFormatException,
      );
      expect(
        () => ReverseGarlicBlock(
          expiryTs: 1,
          sessionTag: sessionTag,
          ohId: ohId,
          hops: [],
        ),
        throwsFormatException,
      );
    });

    test('rejects unsupported versions', () {
      expect(
        () => ReverseGarlicBlock(
          version: 2,
          expiryTs: 1,
          sessionTag: sessionTag,
          ohId: ohId,
          hops: [hop(1)],
        ),
        throwsFormatException,
      );
      // Serialized with a patched version byte: field 1 is the first field,
      // [0x08 version-tag][value] — flip the value to 2.
      final bytes = sample().serialize();
      expect(bytes[0], 0x08);
      bytes[1] = 2;
      expect(
        () => ReverseGarlicBlock.deserialize(bytes),
        throwsFormatException,
      );
    });

    test('rejects truncated and incomplete input', () {
      final bytes = sample().serialize();
      expect(
        () =>
            ReverseGarlicBlock.deserialize(bytes.sublist(0, bytes.length - 5)),
        throwsFormatException,
      );
      // Missing mandatory fields entirely.
      expect(
        () => ReverseGarlicBlock.deserialize(const [0x08, 0x01]),
        throwsFormatException,
      );
      // Hop with a 19-byte kad_id fails GarlicHop validation.
      final badHop = ReverseGarlicBlock.deserialize(bytes);
      expect(badHop.hops, isNotEmpty); // sanity: original parses
      final malformedHop = <int>[
        0x0A, 19, ...List<int>.filled(19, 1), // kad_id too short
        0x12, 32, ...List<int>.filled(32, 2),
      ];
      final withBadHop = <int>[
        0x08, 0x01, // version
        0x10, 0x01, // expiry_ts
        0x1A, 16, ...sessionTag,
        0x22, 20, ...ohId,
        0x2A, malformedHop.length, ...malformedHop,
      ];
      expect(
        () => ReverseGarlicBlock.deserialize(withBadHop),
        throwsFormatException,
      );
    });
  });
}
