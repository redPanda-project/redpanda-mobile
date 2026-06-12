import 'dart:convert';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';

/// Channel message envelope v3 (MS03 — AES-256-GCM).
///
/// Wire format:
///
/// ```
/// payload v3 = [version(1) = 0x03][nonce(12)][ciphertext + GCM tag(16)]
/// ciphertext = AES-256-GCM(K_enc, nonce, plaintext, aad = utf8(channelId))
/// plaintext  = ChannelMessage { message_id (16 bytes), timestamp_ms, content }
/// ```
///
/// Replaces the v2 envelope (`[0x02][IV][AES-CTR ciphertext][HMAC-SHA256]`):
/// GCM is a single-key AEAD, so the HKDF cipher/MAC key separation and the
/// separate HMAC of v2 are obsolete. The channel id (hex of
/// `SHA256(K_enc || K_auth_pub)`) is bound as AAD, so a payload cannot be
/// replayed into a different channel.
///
/// v2 payloads are not accepted: MS03 is a breaking protocol change and
/// existing channels are re-created (database migration drops them), so
/// there is nothing left to read in the old format.
class MessageCryptoV3 {
  MessageCryptoV3._();

  /// The format version byte. Unknown versions are rejected on decrypt.
  static const int version = 0x03;

  /// Encrypts a [ChannelMessage] into a v3 payload for the channel
  /// identified by [channelId] with the 32-byte channel key [channelKey].
  ///
  /// A fresh random nonce is generated for every call (so retries with the
  /// same inner [ChannelMessage.messageId] still produce different
  /// ciphertext — the inner message_id, not the nonce, is what deduplicates
  /// at the receiver).
  static Future<Uint8List> encrypt(
    ChannelMessage message,
    List<int> channelKey,
    String channelId,
  ) async {
    final nonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
    final ciphertext = await CryptoUtils.aesGcmEncrypt(
      channelKey,
      nonce,
      message.encode(),
      utf8.encode(channelId),
    );

    final payload = Uint8List(1 + nonce.length + ciphertext.length);
    payload[0] = version;
    payload.setRange(1, 1 + nonce.length, nonce);
    payload.setRange(1 + nonce.length, payload.length, ciphertext);
    return payload;
  }

  /// Verifies and decrypts a v3 payload into a [ChannelMessage].
  ///
  /// Throws [FormatException] on an unknown version byte or a too-short
  /// payload, and [GcmAuthenticationException] when the GCM tag does not
  /// verify (tampered payload, wrong key or wrong channel AAD).
  static Future<ChannelMessage> decrypt(
    List<int> payload,
    List<int> channelKey,
    String channelId,
  ) async {
    if (payload.length <
        1 + CryptoUtils.gcmNonceLength + CryptoUtils.gcmTagLength) {
      throw FormatException('v3 payload too short: ${payload.length} bytes');
    }
    if (payload[0] != version) {
      throw FormatException(
        'unsupported message format version: '
        '0x${payload[0].toRadixString(16)}',
      );
    }

    final data = Uint8List.fromList(payload);
    final nonce = Uint8List.sublistView(
      data,
      1,
      1 + CryptoUtils.gcmNonceLength,
    );
    final ciphertext = Uint8List.sublistView(
      data,
      1 + CryptoUtils.gcmNonceLength,
    );

    final plaintext = await CryptoUtils.aesGcmDecrypt(
      channelKey,
      nonce,
      ciphertext,
      utf8.encode(channelId),
    );

    return ChannelMessage.decode(plaintext);
  }
}
