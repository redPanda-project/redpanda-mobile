import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';

void main() {
  group('MS03b message-format v4 envelope', () {
    final messageKey = List<int>.generate(32, (i) => i);
    final ratchetPub = List<int>.generate(32, (i) => 0xA0 + (i % 16));
    final plaintext = List<int>.generate(48, (i) => 0x30 + (i % 10));
    final channelId = 'aabbccdd' * 8; // 64 hex chars like a real channel id

    Future<Uint8List> seal({
      List<int>? key,
      int prevChainLen = 7,
      int chainCounter = 42,
      String? channel,
    }) {
      return MessageCryptoV4.seal(
        messageKey: key ?? messageKey,
        ratchetPublicKey: ratchetPub,
        previousChainLength: prevChainLen,
        chainCounter: chainCounter,
        plaintext: plaintext,
        channelId: channel ?? channelId,
      );
    }

    test('seal → parseHeader → open roundtrip', () async {
      final payload = await seal();

      expect(payload[0], MessageCryptoV4.version);
      final header = MessageCryptoV4.parseHeader(payload);
      expect(header.ratchetPublicKey, ratchetPub);
      expect(header.previousChainLength, 7);
      expect(header.chainCounter, 42);

      final opened = await MessageCryptoV4.open(
        payload: payload,
        messageKey: messageKey,
        channelId: channelId,
      );
      expect(opened, plaintext);
    });

    test('payload overhead is exactly 69 bytes (size budget, MS04)', () async {
      final payload = await seal();
      // [version 1][ratchet_pub 32][PN 4][N 4][nonce 12][tag 16] = 69 bytes.
      expect(payload.length - plaintext.length, 69);
      expect(MessageCryptoV4.minPayloadLength, 69);
    });

    test('parseHeader rejects unknown version byte', () async {
      final payload = await seal();
      payload[0] = 0x03;
      expect(() => MessageCryptoV4.parseHeader(payload), throwsFormatException);
    });

    test('parseHeader and open reject too-short payloads', () {
      final short = Uint8List(MessageCryptoV4.minPayloadLength - 1)
        ..[0] = MessageCryptoV4.version;
      expect(() => MessageCryptoV4.parseHeader(short), throwsFormatException);
      expect(
        () => MessageCryptoV4.open(
          payload: short,
          messageKey: messageKey,
          channelId: channelId,
        ),
        throwsFormatException,
      );
    });

    test('open fails for a different channel (AAD binding)', () async {
      final payload = await seal();
      expect(
        () => MessageCryptoV4.open(
          payload: payload,
          messageKey: messageKey,
          channelId: 'ffeeddcc' * 8,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('open fails when the cleartext header was tampered', () async {
      final payload = await seal();
      payload[1 + 32 + 4 + 3] ^= 0x01; // flip a bit in chain_counter
      expect(
        () => MessageCryptoV4.open(
          payload: payload,
          messageKey: messageKey,
          channelId: channelId,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('open fails with the wrong message key', () async {
      final payload = await seal();
      expect(
        () => MessageCryptoV4.open(
          payload: payload,
          messageKey: List<int>.generate(32, (i) => 0xFF - i),
          channelId: channelId,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });

    test('seal validates ratchet key length and counter range', () {
      expect(
        () => MessageCryptoV4.seal(
          messageKey: messageKey,
          ratchetPublicKey: List<int>.filled(31, 0),
          previousChainLength: 0,
          chainCounter: 0,
          plaintext: plaintext,
          channelId: channelId,
        ),
        throwsArgumentError,
      );
      expect(
        () => MessageCryptoV4.seal(
          messageKey: messageKey,
          ratchetPublicKey: ratchetPub,
          previousChainLength: 0,
          chainCounter: 0x1_0000_0000,
          plaintext: plaintext,
          channelId: channelId,
        ),
        throwsArgumentError,
      );
    });
  });
}
