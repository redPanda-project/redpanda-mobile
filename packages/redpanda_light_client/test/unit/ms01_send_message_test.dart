import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v2.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

void main() {
  group('MS01 AK1 / MS02: sendMessage() reports delivery failures', () {
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

    test('sendMessage without channel keys throws StateError', () async {
      final channel = Channel.generate('Test');

      // MS02: failures must surface so the retry queue can re-send later.
      expect(
        () => client.sendMessage(channel.id, 'Hello World'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no encryption keys'),
          ),
        ),
      );
    });

    test(
      'sendMessage with keys but no connected peer throws StateError',
      () async {
        final channel = Channel.generate('Test');
        client.addChannelKeys(channel.id, channel.encryptionKey);

        expect(
          () => client.sendMessage(channel.id, 'Hello'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('no active peer'),
            ),
          ),
        );
      },
    );
  });

  group('MS03 message-format-v2: encrypt → decrypt roundtrip', () {
    test('roundtrip via MessageCryptoV2 recovers content and id', () {
      final channel = Channel.generate('Test');
      final encKey = channel.encryptionKey;

      final msg = ChannelMessage(
        messageId: Uint8List.fromList(List<int>.generate(16, (i) => i)),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        content: 'Hello, Bob! This is a secret message. 🎉 Ünïcödé',
      );

      final payload = MessageCryptoV2.encrypt(msg, encKey);
      expect(payload[0], equals(MessageCryptoV2.version));

      final decoded = MessageCryptoV2.decrypt(payload, encKey);
      expect(decoded.content, equals(msg.content));
      expect(decoded.messageId, equals(msg.messageId));
      expect(decoded.timestampMs, equals(msg.timestampMs));
    });

    test('tampered payload is rejected', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final msg = ChannelMessage(
        messageId: Uint8List(16),
        timestampMs: 1,
        content: 'Secret',
      );
      final payload = MessageCryptoV2.encrypt(msg, encKey);
      payload[1 + 16 + 1] ^= 0xFF; // flip a ciphertext byte
      expect(
        () => MessageCryptoV2.decrypt(payload, encKey),
        throwsA(isA<StateError>()),
      );
    });

    test('empty content roundtrips', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final msg = ChannelMessage(
        messageId: Uint8List(16),
        timestampMs: 1,
        content: '',
      );
      final decoded = MessageCryptoV2.decrypt(
        MessageCryptoV2.encrypt(msg, encKey),
        encKey,
      );
      expect(decoded.content, equals(''));
    });
  });
}
