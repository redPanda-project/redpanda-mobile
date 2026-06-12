import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v3.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  const channelId =
      'aabbccdd00112233aabbccdd00112233'
      'aabbccdd00112233aabbccdd00112233';

  ChannelMessage sampleMessage({String content = 'Hello, Bob! 🎉 Ünïcödé'}) {
    return ChannelMessage(
      messageId: Uint8List.fromList(List<int>.generate(16, (i) => 200 - i)),
      timestampMs: 1749600000000,
      content: content,
    );
  }

  group('ChannelMessage codec (proto3-compatible)', () {
    test('encode → decode roundtrip preserves all fields', () {
      final msg = sampleMessage();
      final decoded = ChannelMessage.decode(msg.encode());

      expect(decoded.messageId, equals(msg.messageId));
      expect(decoded.timestampMs, equals(msg.timestampMs));
      expect(decoded.content, equals(msg.content));
    });

    test('handles empty content and unicode', () {
      for (final content in ['', 'a', '🎉🎉🎉', 'Ünïcödé Ümläuts']) {
        final msg = sampleMessage(content: content);
        expect(ChannelMessage.decode(msg.encode()).content, equals(content));
      }
    });

    test('uses the documented proto3 tag bytes', () {
      final msg = ChannelMessage(
        messageId: Uint8List.fromList([1, 2, 3]),
        timestampMs: 1,
        content: 'x',
      );
      final bytes = msg.encode();
      // field 1 (message_id): tag 0x0A, len 0x03
      expect(bytes[0], equals(0x0A));
      expect(bytes[1], equals(0x03));
      // After 3 id bytes: field 2 (timestamp_ms) tag 0x10, value 0x01
      expect(bytes[5], equals(0x10));
      expect(bytes[6], equals(0x01));
      // Then field 3 (content) tag 0x1A, len 0x01
      expect(bytes[7], equals(0x1A));
      expect(bytes[8], equals(0x01));
    });

    test('skips unknown fields (forward compatibility)', () {
      final msg = sampleMessage();
      final encoded = msg.encode();
      // Append an unknown field #5, varint wire type: tag (5<<3|0)=0x28, val 7.
      final withUnknown = Uint8List.fromList([...encoded, 0x28, 0x07]);
      final decoded = ChannelMessage.decode(withUnknown);
      expect(decoded.content, equals(msg.content));
      expect(decoded.messageId, equals(msg.messageId));
    });

    test('throws on truncated input', () {
      final encoded = sampleMessage().encode();
      expect(
        () => ChannelMessage.decode(encoded.sublist(0, encoded.length - 3)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('MessageCryptoV3 encrypt/decrypt (AES-256-GCM)', () {
    test('roundtrip recovers the original ChannelMessage', () async {
      final msg = sampleMessage();
      final payload = await MessageCryptoV3.encrypt(msg, key, channelId);

      expect(payload[0], equals(MessageCryptoV3.version));
      // [version][12 nonce][ciphertext + 16 tag]
      expect(payload.length, greaterThanOrEqualTo(1 + 12 + 16));

      final decoded = await MessageCryptoV3.decrypt(payload, key, channelId);
      expect(decoded.messageId, equals(msg.messageId));
      expect(decoded.timestampMs, equals(msg.timestampMs));
      expect(decoded.content, equals(msg.content));
    });

    test('same message encrypts to different payloads (fresh nonce)', () async {
      final msg = sampleMessage();
      final a = await MessageCryptoV3.encrypt(msg, key, channelId);
      final b = await MessageCryptoV3.encrypt(msg, key, channelId);
      expect(a, isNot(equals(b)));
    });

    test('a flipped ciphertext bit fails authentication', () async {
      final payload = await MessageCryptoV3.encrypt(
        sampleMessage(),
        key,
        channelId,
      );
      payload[payload.length - 20] ^= 0x01;

      expect(
        () => MessageCryptoV3.decrypt(payload, key, channelId),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('a flipped tag bit fails authentication', () async {
      final payload = await MessageCryptoV3.encrypt(
        sampleMessage(),
        key,
        channelId,
      );
      payload[payload.length - 1] ^= 0x80;

      expect(
        () => MessageCryptoV3.decrypt(payload, key, channelId),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('wrong key fails authentication', () async {
      final payload = await MessageCryptoV3.encrypt(
        sampleMessage(),
        key,
        channelId,
      );
      final wrongKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

      expect(
        () => MessageCryptoV3.decrypt(payload, wrongKey, channelId),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('payload is bound to its channel id (AAD)', () async {
      final payload = await MessageCryptoV3.encrypt(
        sampleMessage(),
        key,
        channelId,
      );

      expect(
        () => MessageCryptoV3.decrypt(payload, key, 'other-channel-id'),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('rejects unknown version byte', () async {
      final payload = await MessageCryptoV3.encrypt(
        sampleMessage(),
        key,
        channelId,
      );
      payload[0] = 0x02; // old v2 envelope marker

      expect(
        () => MessageCryptoV3.decrypt(payload, key, channelId),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects too-short payloads', () async {
      expect(
        () => MessageCryptoV3.decrypt(Uint8List(8), key, channelId),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
