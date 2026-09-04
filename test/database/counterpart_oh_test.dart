import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/counterpart_oh.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

OHDescriptor _mailbox(String endpoint, int seed) => OHDescriptor(
  serverEndpoint: endpoint,
  handleId: List.generate(20, (i) => (i + seed) & 0xff),
  authPublicKey: List.generate(32, (i) => (i + seed) & 0xff),
);

void main() {
  group('counterpartOhColumns', () {
    test('an empty list leaves every column absent', () {
      final columns = counterpartOhColumns(const <OHDescriptor>[]);
      expect(columns.counterpartOhEndpoint.present, isFalse);
      expect(columns.counterpartOhId.present, isFalse);
      expect(columns.counterpartOhPublicKey.present, isFalse);
      expect(columns.counterpartOhSet.present, isFalse);
    });

    test('the primary columns mirror the first entry', () {
      final descriptors = [_mailbox('node-1:59558', 1), _mailbox('n2:1', 2)];
      final columns = counterpartOhColumns(descriptors);

      expect(columns.counterpartOhEndpoint.value, equals('node-1:59558'));
      expect(
        columns.counterpartOhId.value,
        equals(HEX.encode(descriptors.first.handleId)),
      );
      expect(
        columns.counterpartOhPublicKey.value,
        equals(HEX.encode(descriptors.first.authPublicKey)),
      );
      final roundTrip = decodeCounterpartOhSet(columns.counterpartOhSet.value)!;
      expect(
        roundTrip.map((d) => d.serverEndpoint),
        equals(['node-1:59558', 'n2:1']),
      );
    });
  });

  // Malformed input reaches this from the database, not from the network, but
  // the whole point of the fallback is that a broken set does not take the
  // channel down: the client then uses the primary columns.
  group('decodeCounterpartOhSet returns null instead of throwing', () {
    final broken = <String, String?>{
      'null column': null,
      'empty string': '',
      'not JSON': '[{"ep":',
      'not a list': '{"ep":"n:1","id":"aa","pk":"bb"}',
      'empty list': '[]',
      'list of strings': '["node-1:59558"]',
      'missing fields': '[{"ep":"node-1:59558"}]',
      'wrong id length': '[{"ep":"n:1","id":"aa","pk":"${'bb' * 32}"}]',
    };

    for (final entry in broken.entries) {
      test(entry.key, () {
        expect(decodeCounterpartOhSet(entry.value), isNull);
      });
    }

    test('one broken entry discards the whole set (fail closed)', () {
      final good = _mailbox('node-1:59558', 1);
      final json =
          '[{"ep":"${good.serverEndpoint}","id":"${HEX.encode(good.handleId)}",'
          '"pk":"${HEX.encode(good.authPublicKey)}"},{"ep":"node-2:59558"}]';
      expect(decodeCounterpartOhSet(json), isNull);
    });
  });

  group('promoteToPrimary', () {
    test('moves an already known mailbox to the head', () {
      final a = _mailbox('node-1:59558', 1);
      final b = _mailbox('node-2:59558', 2);

      expect(
        promoteToPrimary(b, [a, b]).map((d) => d.serverEndpoint),
        equals(['node-2:59558', 'node-1:59558']),
      );
    });

    test('prepends an unknown mailbox and keeps the rest', () {
      final a = _mailbox('node-1:59558', 1);
      final b = _mailbox('node-2:59558', 2);

      expect(
        promoteToPrimary(b, [a]).map((d) => d.serverEndpoint),
        equals(['node-2:59558', 'node-1:59558']),
      );
      expect(promoteToPrimary(b, null), equals([b]));
    });
  });
}
