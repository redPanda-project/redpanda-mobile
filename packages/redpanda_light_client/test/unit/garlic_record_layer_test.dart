import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/return_path.dart';
import 'package:test/test.dart';

import '../helpers/garlic_test_utils.dart';

/// T44: the two record garlic layer commands (`CMD_RECORD_STORE` = 0x05,
/// `CMD_RECORD_LOOKUP` = 0x06) peel exactly like the deliver family, and the
/// innermost layer matches the backend `GarlicRouter` plaintext framing.
void main() {
  late TestHop h1;
  late TestHop h2;
  late TestHop h3;

  setUp(() async {
    h1 = await TestHop.generate(0x11);
    h2 = await TestHop.generate(0x22);
    h3 = await TestHop.generate(0x33);
  });

  Future<Uint8List> peelForward(
    Uint8List packet,
    TestHop hop,
    TestHop next,
  ) async {
    final plaintext = await ParsedPacket.parse(
      packet,
    ).decryptLayer(hop.keys.privateKey);
    expect(plaintext[0], GarlicBuilder.cmdForward);
    expect(plaintext.sublist(1, 21), equals(next.nodeId));
    return GarlicBuilder.buildPacket(
      plaintext.sublist(1, 21),
      plaintext.sublist(21),
    );
  }

  test(
    'record_store: three relays peel to CMD_RECORD_STORE [1][4 len][store]',
    () async {
      final store = List<int>.generate(660, (i) => (13 * i) & 0xff);
      var packet = await GarlicBuilder.buildRecordStore(
        hops: [h1.asGarlicHop, h2.asGarlicHop, h3.asGarlicHop],
        kademliaStore: store,
      );
      expect(packet.length, GarlicBuilder.packetSize);

      packet = await peelForward(packet, h1, h2);
      packet = await peelForward(packet, h2, h3);

      final inner = await ParsedPacket.parse(
        packet,
      ).decryptLayer(h3.keys.privateKey);
      expect(inner[0], GarlicBuilder.cmdRecordStore);
      final len = ByteData.sublistView(inner).getUint32(1);
      expect(len, store.length);
      expect(inner.sublist(5, 5 + len), equals(store));
    },
  );

  test(
    'record_lookup: peels to CMD_RECORD_LOOKUP [1][20 key][ReturnPath]',
    () async {
      final recordKey = CryptoUtils.randomBytes(20);
      final returnPath = ReturnPathBlock(
        ackOhId: CryptoUtils.randomBytes(20),
        ackSessionTag: CryptoUtils.randomBytes(GarlicBuilder.sessionTagLength),
        hops: [
          GarlicHop(
            nodeId: CryptoUtils.randomBytes(20),
            encryptionPublicKey: CryptoUtils.randomBytes(32),
          ),
          GarlicHop(
            nodeId: CryptoUtils.randomBytes(20),
            encryptionPublicKey: CryptoUtils.randomBytes(32),
          ),
        ],
      );
      var packet = await GarlicBuilder.buildRecordLookup(
        hops: [h1.asGarlicHop, h2.asGarlicHop, h3.asGarlicHop],
        recordKey: recordKey,
        returnPath: returnPath,
      );
      expect(packet.length, GarlicBuilder.packetSize);

      packet = await peelForward(packet, h1, h2);
      packet = await peelForward(packet, h2, h3);

      final inner = await ParsedPacket.parse(
        packet,
      ).decryptLayer(h3.keys.privateKey);
      expect(inner[0], GarlicBuilder.cmdRecordLookup);
      expect(inner.sublist(1, 21), equals(recordKey));
      final rp = ReturnPathBlock.deserialize(inner.sublist(21));
      expect(rp.ackOhId, equals(returnPath.ackOhId));
      expect(rp.ackSessionTag, equals(returnPath.ackSessionTag));
      expect(rp.hops.length, 2);
    },
  );

  test('single-hop record_store carries the layer directly', () async {
    final store = List<int>.generate(100, (i) => i & 0xff);
    final packet = await GarlicBuilder.buildRecordStore(
      hops: [h1.asGarlicHop],
      kademliaStore: store,
    );
    final inner = await ParsedPacket.parse(
      packet,
    ).decryptLayer(h1.keys.privateKey);
    expect(inner[0], GarlicBuilder.cmdRecordStore);
    final len = ByteData.sublistView(inner).getUint32(1);
    expect(inner.sublist(5, 5 + len), equals(store));
  });

  test('empty hop list is rejected', () {
    expect(
      () => GarlicBuilder.buildRecordStore(hops: [], kademliaStore: [1, 2, 3]),
      throwsA(isA<ArgumentError>()),
    );
  });
}
