import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v3.dart';
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
      final channel = await Channel.generate('Test');

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
        final channel = await Channel.generate('Test');
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

  group('MS03 message-format-v3: encrypt → decrypt roundtrip', () {
    test('roundtrip via MessageCryptoV3 recovers content and id', () async {
      final channel = await Channel.generate('Test');
      final encKey = channel.encryptionKey;

      final msg = ChannelMessage(
        messageId: Uint8List.fromList(List<int>.generate(16, (i) => i)),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        content: 'Hello, Bob! This is a secret message. 🎉 Ünïcödé',
      );

      final payload = await MessageCryptoV3.encrypt(msg, encKey, channel.id);
      expect(payload[0], equals(MessageCryptoV3.version));

      final decoded = await MessageCryptoV3.decrypt(
        payload,
        encKey,
        channel.id,
      );
      expect(decoded.content, equals(msg.content));
      expect(decoded.messageId, equals(msg.messageId));
      expect(decoded.timestampMs, equals(msg.timestampMs));
    });

    test('tampered payload is rejected', () async {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final msg = ChannelMessage(
        messageId: Uint8List(16),
        timestampMs: 1,
        content: 'Secret',
      );
      final payload = await MessageCryptoV3.encrypt(msg, encKey, 'chan');
      payload[1 + 12 + 1] ^= 0xFF; // flip a ciphertext byte
      expect(
        () => MessageCryptoV3.decrypt(payload, encKey, 'chan'),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('empty content roundtrips', () async {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final msg = ChannelMessage(
        messageId: Uint8List(16),
        timestampMs: 1,
        content: '',
      );
      final decoded = await MessageCryptoV3.decrypt(
        await MessageCryptoV3.encrypt(msg, encKey, 'chan'),
        encKey,
        'chan',
      );
      expect(decoded.content, equals(''));
    });
  });
}
