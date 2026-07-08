import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/garlic/ack_tag_store.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:redpanda_light_client/src/garlic/return_path.dart';

import '../helpers/garlic_test_utils.dart';

void main() {
  final ohId = Uint8List.fromList(List<int>.generate(20, (i) => 100 + i));
  final tag = Uint8List.fromList(List<int>.generate(16, (i) => 200 + i));

  group('ReturnPathBlock (Decisions Backend-MS06, Decision 2)', () {
    test('serializes to 37 + 52·h bytes and roundtrips', () async {
      final h1 = await TestHop.generate(1);
      final h2 = await TestHop.generate(2);
      final block = ReturnPathBlock(
        ackOhId: ohId,
        ackSessionTag: tag,
        hops: [h1.asGarlicHop, h2.asGarlicHop],
      );

      final bytes = block.serialize();
      expect(bytes.length, ReturnPathBlock.serializedLength(2));
      expect(bytes.length, 37 + 2 * 52);

      final parsed = ReturnPathBlock.deserialize(bytes);
      expect(parsed.ackOhId, equals(ohId));
      expect(parsed.ackSessionTag, equals(tag));
      expect(parsed.hops.length, 2);
      expect(parsed.hops[0].nodeId, equals(h1.nodeId));
      expect(parsed.hops[1].encryptionPublicKey, equals(h2.keys.publicKey));
    });

    test('zero-hop block is valid (depositing node delivers directly)', () {
      final block = ReturnPathBlock(
        ackOhId: ohId,
        ackSessionTag: tag,
        hops: const [],
      );
      expect(block.serialize().length, 37);
      expect(ReturnPathBlock.deserialize(block.serialize()).hops, isEmpty);
    });

    test('rejects more than 4 hops and malformed input', () async {
      final hops = [
        for (var i = 0; i < 5; i++) (await TestHop.generate(i)).asGarlicHop,
      ];
      expect(
        () => ReturnPathBlock(ackOhId: ohId, ackSessionTag: tag, hops: hops),
        throwsArgumentError,
      );
      expect(
        () => ReturnPathBlock.deserialize(Uint8List(10)),
        throwsFormatException,
      );
      // Trailing garbage after the announced hops must be rejected.
      final valid = ReturnPathBlock(
        ackOhId: ohId,
        ackSessionTag: tag,
        hops: const [],
      ).serialize();
      expect(
        () => ReturnPathBlock.deserialize([...valid, 0x00]),
        throwsFormatException,
      );
    });

    test('max serialized length matches the backend constant (245)', () {
      expect(ReturnPathBlock.maxSerializedLength, 245);
    });
  });

  group('acked garlic budget (Decision 6)', () {
    test('tagged send with 3 forward + 3 return hops carries 1554 bytes', () {
      expect(
        GarlicBuilder.maxAckedPayloadLength(3, tagged: true, returnHopCount: 3),
        1554,
      );
      // Untagged variant gains the 16 tag bytes back.
      expect(
        GarlicBuilder.maxAckedPayloadLength(
          3,
          tagged: false,
          returnHopCount: 3,
        ),
        1570,
      );
    });

    test(
      'CMD_DELIVER_ACKED innermost layer has the Decision-1 layout',
      () async {
        final h1 = await TestHop.generate(1);
        final returnHop = await TestHop.generate(9);
        final payload = List<int>.generate(64, (i) => i);
        final returnPath = ReturnPathBlock(
          ackOhId: ohId,
          ackSessionTag: tag,
          hops: [returnHop.asGarlicHop],
        );

        final packet = await GarlicBuilder.build(
          hops: [h1.asGarlicHop],
          ohId: ohId,
          payload: payload,
          sessionTag: tag,
          returnPath: returnPath,
        );

        final plaintext = await ParsedPacket.parse(
          packet,
        ).decryptLayer(h1.keys.privateKey);
        var offset = 0;
        expect(plaintext[offset++], GarlicBuilder.cmdDeliverAcked);
        expect(plaintext.sublist(offset, offset += 20), equals(ohId));
        expect(plaintext[offset++], 16); // tag_len
        expect(plaintext.sublist(offset, offset += 16), equals(tag));
        final returnBytes = returnPath.serialize();
        expect(
          plaintext.sublist(offset, offset += returnBytes.length),
          equals(returnBytes),
        );
        final payloadLen = ByteData.sublistView(
          plaintext,
          offset,
          offset + 4,
        ).getUint32(0);
        offset += 4;
        expect(payloadLen, payload.length);
        expect(plaintext.sublist(offset, offset + payloadLen), equals(payload));
      },
    );
  });

  group('RoutingAck decoding (Decision 3)', () {
    test('roundtrips timestamp and status, no message_id field', () {
      const ack = RoutingAck(timestampMs: 1751500000000, status: 2);
      final decoded = RoutingAck.decode(ack.encode());
      expect(decoded.timestampMs, 1751500000000);
      expect(decoded.status, RoutingAck.statusHandleExpired);
    });

    test('status defaults to stored (0) when absent', () {
      const ack = RoutingAck(timestampMs: 12345, status: 0);
      final decoded = RoutingAck.decode(ack.encode());
      expect(decoded.status, RoutingAck.statusStored);
    });

    test('rejects truncated input', () {
      expect(() => RoutingAck.decode([0x08]), throwsFormatException);
    });
  });

  group('AckTagStore', () {
    test('consume is single-use and takeExpired reaps old entries', () {
      final store = AckTagStore();
      store.store(
        'aa' * 16,
        channelId: 'chan',
        messageIdHex: 'msg-1',
        hopNodeIdsHex: ['11', '22'],
        sentAtMs: 1000,
      );
      store.store(
        'bb' * 16,
        channelId: 'chan',
        messageIdHex: 'msg-2',
        hopNodeIdsHex: ['33'],
        sentAtMs: 5000,
      );

      final entry = store.consume('aa' * 16);
      expect(entry!.messageIdHex, 'msg-1');
      expect(store.consume('aa' * 16), isNull);

      final expired = store.takeExpired(
        const Duration(seconds: 90),
        nowMs: 5000 + 90000 + 1,
      );
      expect(expired.map((e) => e.messageIdHex), ['msg-2']);
      expect(store.outstanding, 0);
    });
  });

  group('NodeScorer', () {
    test('scores successes and failures with running latency average', () {
      final scorer = NodeScorer();
      expect(scorer.score('n1'), NodeScorer.neutralScore);

      scorer.recordSuccess(['n1', 'n2'], 100);
      scorer.recordSuccess(['n1'], 300);
      scorer.recordFailure(['n2']);

      expect(scorer.score('n1'), 1.0);
      expect(scorer.score('n2'), 0.5);
      final n1 = scorer.snapshot().firstWhere((s) => s.nodeIdHex == 'n1');
      expect(n1.avgLatencyMs, 200);
    });

    test('shouldAvoid needs at least 3 observations below the threshold', () {
      final scorer = NodeScorer();
      scorer.recordFailure(['bad']);
      expect(scorer.shouldAvoid('bad'), isFalse); // only one observation
      scorer.recordFailure(['bad']);
      scorer.recordFailure(['bad']);
      expect(scorer.shouldAvoid('bad'), isTrue);
      expect(scorer.shouldAvoid('unknown'), isFalse);
    });

    test('restore keeps live entries and fills missing ones', () {
      final scorer = NodeScorer();
      scorer.recordSuccess(['live'], 50);
      scorer.restore([
        const NodeScore(
          nodeIdHex: 'live',
          successCount: 0,
          failureCount: 9,
          avgLatencyMs: 0,
          lastUpdatedMs: 1,
        ),
        const NodeScore(
          nodeIdHex: 'persisted',
          successCount: 3,
          failureCount: 1,
          avgLatencyMs: 120,
          lastUpdatedMs: 2,
        ),
      ]);
      expect(scorer.score('live'), 1.0); // live state wins
      expect(scorer.score('persisted'), 0.75);
    });
  });

  group('ChannelMessage ack field (MS06)', () {
    test('ack_message_id (field 6) roundtrips and marks a channel ack', () {
      final ackedId = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final ack = ChannelMessage(
        messageId: Uint8List.fromList(List<int>.generate(16, (i) => 50 + i)),
        timestampMs: 1751500000000,
        content: '',
        ackMessageId: ackedId,
      );
      final decoded = ChannelMessage.decode(ack.encode());
      expect(decoded.isChannelAck, isTrue);
      expect(decoded.ackMessageId, equals(ackedId));
      expect(decoded.content, isEmpty);
    });

    test('regular messages carry no ack id and stay wire-compatible', () {
      final msg = ChannelMessage(
        messageId: Uint8List.fromList(List<int>.generate(16, (i) => i)),
        timestampMs: 7,
        content: 'hallo',
      );
      final decoded = ChannelMessage.decode(msg.encode());
      expect(decoded.isChannelAck, isFalse);
      expect(decoded.ackMessageId, isNull);
      expect(decoded.content, 'hallo');
    });
  });
}
