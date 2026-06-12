import 'dart:convert';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';

/// Channel message envelope v4 (MS03b — Forward Secrecy / Double Ratchet).
///
/// Wire format:
///
/// ```
/// payload v4 = [version(1) = 0x04]
///              [ratchet_pub(32)]        // sender's current X25519 ratchet key
///              [prev_chain_len(4 BE)]   // PN: length of previous sending chain
///              [chain_counter(4 BE)]    // N: message index in current chain
///              [nonce(12)]
///              [ciphertext + GCM tag(16)]
/// ciphertext = AES-256-GCM(MK_n, nonce, plaintext, aad = utf8(channelId) || header)
/// plaintext  = ChannelMessage { message_id (16 bytes), timestamp_ms, content }
/// ```
///
/// Unlike v3 (static `K_enc`), the AES key is the per-message key `MK_n`
/// derived by the channel ratchet ([RatchetSession]). The ratchet header
/// (`ratchet_pub`, `prev_chain_len`, `chain_counter`) must be readable
/// *before* decryption — the receiver needs it to derive `MK_n` in the first
/// place — so it travels in the clear but is authenticated as part of the
/// GCM AAD together with the channel id. The master spec sketched these
/// fields inside the encrypted `ChannelMessage`; that placement is circular
/// for the DH ratchet (the key depends on the header), hence this envelope
/// header (see "Decisions (MS03b)" in the master spec).
class MessageCryptoV4 {
  MessageCryptoV4._();

  /// The format version byte. v3 payloads are dispatched to
  /// `MessageCryptoV3`; unknown versions are rejected.
  static const int version = 0x04;

  /// `[version][ratchet_pub 32][prev_chain_len 4][chain_counter 4]`.
  static const int headerLength = 1 + CryptoUtils.keyLength + 4 + 4;

  /// Header + nonce + GCM tag (minimum size of a v4 payload).
  static const int minPayloadLength =
      headerLength + CryptoUtils.gcmNonceLength + CryptoUtils.gcmTagLength;

  /// Encrypts [plaintext] under the per-message key [messageKey] into a v4
  /// payload carrying the given ratchet header fields.
  static Future<Uint8List> seal({
    required List<int> messageKey,
    required List<int> ratchetPublicKey,
    required int previousChainLength,
    required int chainCounter,
    required List<int> plaintext,
    required String channelId,
  }) async {
    final header = _encodeHeader(
      ratchetPublicKey,
      previousChainLength,
      chainCounter,
    );
    final nonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
    final ciphertext = await CryptoUtils.aesGcmEncrypt(
      messageKey,
      nonce,
      plaintext,
      _aad(channelId, header),
    );

    final payload = BytesBuilder(copy: false)
      ..add(header)
      ..add(nonce)
      ..add(ciphertext);
    return payload.toBytes();
  }

  /// Parses the cleartext ratchet header of a v4 payload.
  ///
  /// Throws [FormatException] on an unknown version byte or a too-short
  /// payload. The header is only trustworthy once [open] succeeds — it is
  /// part of the GCM AAD.
  static RatchetHeader parseHeader(List<int> payload) {
    if (payload.length < minPayloadLength) {
      throw FormatException('v4 payload too short: ${payload.length} bytes');
    }
    if (payload[0] != version) {
      throw FormatException(
        'unsupported message format version: '
        '0x${payload[0].toRadixString(16)}',
      );
    }
    final data = Uint8List.fromList(payload);
    final view = ByteData.sublistView(data);
    return RatchetHeader(
      ratchetPublicKey: Uint8List.sublistView(
        data,
        1,
        1 + CryptoUtils.keyLength,
      ),
      previousChainLength: view.getUint32(1 + CryptoUtils.keyLength),
      chainCounter: view.getUint32(1 + CryptoUtils.keyLength + 4),
    );
  }

  /// Verifies and decrypts a v4 payload with the per-message key
  /// [messageKey]; returns the inner plaintext.
  ///
  /// Throws [GcmAuthenticationException] when the tag does not verify
  /// (tampered payload/header, wrong message key or wrong channel AAD).
  static Future<Uint8List> open({
    required List<int> payload,
    required List<int> messageKey,
    required String channelId,
  }) async {
    // parseHeader has validated version and length.
    final data = Uint8List.fromList(payload);
    final header = Uint8List.sublistView(data, 0, headerLength);
    final nonce = Uint8List.sublistView(
      data,
      headerLength,
      headerLength + CryptoUtils.gcmNonceLength,
    );
    final ciphertext = Uint8List.sublistView(
      data,
      headerLength + CryptoUtils.gcmNonceLength,
    );

    return CryptoUtils.aesGcmDecrypt(
      messageKey,
      nonce,
      ciphertext,
      _aad(channelId, header),
    );
  }

  static Uint8List _encodeHeader(
    List<int> ratchetPublicKey,
    int previousChainLength,
    int chainCounter,
  ) {
    if (ratchetPublicKey.length != CryptoUtils.keyLength) {
      throw ArgumentError.value(
        ratchetPublicKey.length,
        'ratchetPublicKey',
        'X25519 ratchet public key must be ${CryptoUtils.keyLength} bytes',
      );
    }
    _checkUint32(previousChainLength, 'previousChainLength');
    _checkUint32(chainCounter, 'chainCounter');

    final header = Uint8List(headerLength);
    header[0] = version;
    header.setRange(1, 1 + CryptoUtils.keyLength, ratchetPublicKey);
    ByteData.sublistView(header)
      ..setUint32(1 + CryptoUtils.keyLength, previousChainLength)
      ..setUint32(1 + CryptoUtils.keyLength + 4, chainCounter);
    return header;
  }

  static void _checkUint32(int value, String name) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw ArgumentError.value(value, name, 'must fit in an unsigned 32-bit');
    }
  }

  /// AAD binds the ciphertext to its channel *and* its ratchet header, so
  /// neither can be swapped without failing authentication.
  static Uint8List _aad(String channelId, List<int> header) {
    final aad = BytesBuilder(copy: false)
      ..add(utf8.encode(channelId))
      ..add(header);
    return aad.toBytes();
  }
}

/// The cleartext (but AAD-authenticated) ratchet header of a v4 payload.
class RatchetHeader {
  /// The sender's current X25519 ratchet public key (32 bytes).
  final Uint8List ratchetPublicKey;

  /// PN — number of messages in the sender's previous sending chain.
  final int previousChainLength;

  /// N — index of this message in the sender's current sending chain.
  final int chainCounter;

  const RatchetHeader({
    required this.ratchetPublicKey,
    required this.previousChainLength,
    required this.chainCounter,
  });
}
