import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'package:redpanda_light_client/src/crypto/channel_message.dart';

/// Message format v2 (MS03 — authenticated encryption with key separation).
///
/// Wire format:
///
/// ```
/// payload v2 = [version(1) = 0x02][IV(16)][ciphertext][HMAC-SHA256(32)]
/// K_cipher = HKDF-SHA256(ikm = K_enc, salt = empty, info = "redpanda-msg-v2-cipher", L = 32)
/// K_mac    = HKDF-SHA256(ikm = K_enc, salt = empty, info = "redpanda-msg-v2-mac",    L = 32)
/// ciphertext = AES-256-CTR(K_cipher, IV, plaintext)
/// MAC = HMAC-SHA256(K_mac) over [version || IV || ciphertext]
/// plaintext = ChannelMessage { message_id (16 random bytes), timestamp_ms, content }
/// ```
///
/// Key separation (finding C3): the cipher key and MAC key are derived from
/// the channel key `K_enc` via HKDF-SHA256 with distinct `info` labels, so the
/// raw channel key is never used directly for either operation.
class MessageCryptoV2 {
  MessageCryptoV2._();

  /// The format version byte. Unknown versions are rejected on decrypt.
  static const int version = 0x02;

  static const int _ivLength = 16;
  static const int _macLength = 32;

  static final Uint8List _cipherInfo = Uint8List.fromList(
    utf8.encode('redpanda-msg-v2-cipher'),
  );
  static final Uint8List _macInfo = Uint8List.fromList(
    utf8.encode('redpanda-msg-v2-mac'),
  );

  /// Derives a 32-byte subkey from [channelKey] using HKDF-SHA256 with an
  /// empty salt and the given [info] label.
  static Uint8List _hkdf(List<int> channelKey, Uint8List info) {
    final hkdf = pc.HKDFKeyDerivator(pc.SHA256Digest());
    hkdf.init(
      pc.HkdfParameters(Uint8List.fromList(channelKey), 32, null, info),
    );
    final out = Uint8List(32);
    hkdf.deriveKey(Uint8List(0), 0, out, 0);
    return out;
  }

  /// Encrypts a [ChannelMessage] for the given channel key into a v2 payload.
  ///
  /// A fresh random IV is generated for every call (so retries with the same
  /// inner [ChannelMessage.messageId] still produce different ciphertext — the
  /// inner message_id, not the IV, is what deduplicates at the receiver).
  static Uint8List encrypt(ChannelMessage message, List<int> channelKey) {
    final kCipher = _hkdf(channelKey, _cipherInfo);
    final kMac = _hkdf(channelKey, _macInfo);

    final random = Random.secure();
    final iv = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => random.nextInt(256)),
    );

    final plaintext = message.encode();

    final cipher = pc.CTRStreamCipher(pc.AESEngine());
    cipher.init(true, pc.ParametersWithIV(pc.KeyParameter(kCipher), iv));
    final ciphertext = cipher.process(plaintext);

    // MAC over [version || IV || ciphertext]
    final macInput = Uint8List(1 + iv.length + ciphertext.length);
    macInput[0] = version;
    macInput.setRange(1, 1 + iv.length, iv);
    macInput.setRange(1 + iv.length, macInput.length, ciphertext);

    final hmac = pc.HMac(pc.SHA256Digest(), 64)..init(pc.KeyParameter(kMac));
    final mac = hmac.process(macInput);

    final payload = Uint8List(1 + iv.length + ciphertext.length + mac.length);
    payload[0] = version;
    payload.setRange(1, 1 + iv.length, iv);
    payload.setRange(
      1 + iv.length,
      1 + iv.length + ciphertext.length,
      ciphertext,
    );
    payload.setRange(1 + iv.length + ciphertext.length, payload.length, mac);
    return payload;
  }

  /// Verifies and decrypts a v2 payload into a [ChannelMessage].
  ///
  /// Throws [FormatException] on an unknown version byte or a too-short
  /// payload, and [StateError] on MAC verification failure. The MAC check uses
  /// a constant-time comparison.
  static ChannelMessage decrypt(List<int> payload, List<int> channelKey) {
    if (payload.length < 1 + _ivLength + _macLength) {
      throw FormatException('v2 payload too short: ${payload.length} bytes');
    }
    if (payload[0] != version) {
      throw FormatException(
        'unsupported message format version: 0x${payload[0].toRadixString(16)}',
      );
    }

    final data = Uint8List.fromList(payload);
    final iv = Uint8List.sublistView(data, 1, 1 + _ivLength);
    final ciphertext = Uint8List.sublistView(
      data,
      1 + _ivLength,
      data.length - _macLength,
    );
    final mac = Uint8List.sublistView(data, data.length - _macLength);

    final kMac = _hkdf(channelKey, _macInfo);
    final macInput = Uint8List(1 + iv.length + ciphertext.length);
    macInput[0] = version;
    macInput.setRange(1, 1 + iv.length, iv);
    macInput.setRange(1 + iv.length, macInput.length, ciphertext);

    final hmac = pc.HMac(pc.SHA256Digest(), 64)..init(pc.KeyParameter(kMac));
    final expectedMac = hmac.process(macInput);

    if (!constantTimeEquals(mac, expectedMac)) {
      throw StateError('HMAC verification failed');
    }

    final kCipher = _hkdf(channelKey, _cipherInfo);
    final cipher = pc.CTRStreamCipher(pc.AESEngine());
    cipher.init(false, pc.ParametersWithIV(pc.KeyParameter(kCipher), iv));
    final plaintext = cipher.process(ciphertext);

    return ChannelMessage.decode(plaintext);
  }

  /// Constant-time byte comparison: runs in time independent of where the
  /// first differing byte is, to avoid leaking MAC bytes through timing.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
