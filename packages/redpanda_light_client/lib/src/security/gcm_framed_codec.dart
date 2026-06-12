import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';

/// Protocol-v23 TCP stream encryption: framed AES-256-GCM with per-direction
/// keys and counter nonces (mirrors the backend `GcmFramedStreams`).
///
/// Frame format (each direction):
///
/// ```
/// [4 length][12 nonce][ciphertext + 16-byte GCM tag]
/// ```
///
/// - `length` = number of bytes after the length field (nonce + ciphertext
///   + tag), big-endian.
/// - `nonce` = unsigned 96-bit big-endian frame counter, starts at 0,
///   incremented per frame per direction; the receiver enforces the expected
///   counter value (replay/reorder protection).
/// - Any authentication failure or framing violation throws — the connection
///   must be dropped; a flipped bit never yields silently corrupted
///   plaintext.
class GcmFramedCodec {
  /// Maximum plaintext bytes per frame; larger writes are split into
  /// multiple frames.
  static const int maxPlaintextPerFrame = 32 * 1024;

  static const int _maxFramePayloadLength =
      CryptoUtils.gcmNonceLength +
      maxPlaintextPerFrame +
      CryptoUtils.gcmTagLength;

  final Uint8List _sendKey;
  final Uint8List _receiveKey;

  int _sendCounter = 0;
  int _receiveCounter = 0;

  /// Buffered inbound ciphertext of a not-yet-complete frame.
  final List<int> _inbound = [];

  GcmFramedCodec({required List<int> sendKey, required List<int> receiveKey})
    : _sendKey = Uint8List.fromList(sendKey),
      _receiveKey = Uint8List.fromList(receiveKey) {
    if (_sendKey.length != CryptoUtils.aesKeyLength ||
        _receiveKey.length != CryptoUtils.aesKeyLength) {
      throw ArgumentError('GCM stream keys must be 32 bytes');
    }
  }

  /// Derives the per-direction session keys for a v23 connection.
  ///
  /// `clientKey = HKDF(shared, salt = min(verifyKeys), info = "tcp-client")`
  /// `serverKey = HKDF(shared, salt = max(verifyKeys), info = "tcp-server")`
  ///
  /// The "client" is the connection initiator. As a light client we always
  /// initiate, so our send key is the client key.
  static Future<GcmFramedCodec> deriveForInitiator({
    required List<int> sharedSecret,
    required List<int> ourVerifyKey,
    required List<int> theirVerifyKey,
  }) async {
    final ourIsMin =
        CryptoUtils.compareUnsigned(ourVerifyKey, theirVerifyKey) <= 0;
    final minKey = ourIsMin ? ourVerifyKey : theirVerifyKey;
    final maxKey = ourIsMin ? theirVerifyKey : ourVerifyKey;

    final clientKey = await CryptoUtils.hkdfSha256(
      sharedSecret,
      minKey,
      'tcp-client',
      CryptoUtils.aesKeyLength,
    );
    final serverKey = await CryptoUtils.hkdfSha256(
      sharedSecret,
      maxKey,
      'tcp-server',
      CryptoUtils.aesKeyLength,
    );

    return GcmFramedCodec(sendKey: clientKey, receiveKey: serverKey);
  }

  /// Encrypts [plaintext] into one or more wire frames.
  Future<Uint8List> encrypt(List<int> plaintext) async {
    final out = BytesBuilder();
    var offset = 0;
    // An empty write still produces one (empty) frame, like the backend.
    do {
      final end = (offset + maxPlaintextPerFrame) > plaintext.length
          ? plaintext.length
          : offset + maxPlaintextPerFrame;
      final chunk = plaintext.sublist(offset, end);
      offset = end;

      final nonce = nonceFromCounter(_sendCounter++);
      final ciphertext = await CryptoUtils.aesGcmEncrypt(
        _sendKey,
        nonce,
        chunk,
        const [],
      );

      final lengthField = ByteData(4)
        ..setUint32(0, nonce.length + ciphertext.length);
      out.add(lengthField.buffer.asUint8List());
      out.add(nonce);
      out.add(ciphertext);
    } while (offset < plaintext.length);
    return out.toBytes();
  }

  /// Buffers [data] and decrypts all complete frames, returning the
  /// concatenated plaintext (possibly empty while a frame is still partial).
  ///
  /// Throws [FormatException] on framing violations and
  /// [GcmAuthenticationException] on tag/counter failures — the caller must
  /// drop the connection.
  Future<Uint8List> decrypt(List<int> data) async {
    _inbound.addAll(data);
    final out = BytesBuilder();

    while (true) {
      if (_inbound.length < 4) break;
      final payloadLength = ByteData.sublistView(
        Uint8List.fromList(_inbound.sublist(0, 4)),
      ).getUint32(0);
      if (payloadLength <
              CryptoUtils.gcmNonceLength + CryptoUtils.gcmTagLength ||
          payloadLength > _maxFramePayloadLength) {
        throw FormatException('invalid GCM frame length: $payloadLength');
      }
      if (_inbound.length < 4 + payloadLength) break;

      final nonce = _inbound.sublist(4, 4 + CryptoUtils.gcmNonceLength);
      final ciphertext = _inbound.sublist(
        4 + CryptoUtils.gcmNonceLength,
        4 + payloadLength,
      );
      _inbound.removeRange(0, 4 + payloadLength);

      final expectedNonce = nonceFromCounter(_receiveCounter);
      if (!CryptoUtils.constantTimeEquals(nonce, expectedNonce)) {
        throw GcmAuthenticationException(
          'unexpected GCM frame nonce (expected counter $_receiveCounter)',
        );
      }

      final plaintext = await CryptoUtils.aesGcmDecrypt(
        _receiveKey,
        nonce,
        ciphertext,
        const [],
      );
      _receiveCounter++;
      out.add(plaintext);
    }

    return out.toBytes();
  }

  /// Builds the 12-byte big-endian nonce for the given frame counter
  /// (4 zero bytes + uint64).
  static Uint8List nonceFromCounter(int counter) {
    final nonce = Uint8List(CryptoUtils.gcmNonceLength);
    ByteData.sublistView(nonce, 4).setUint64(0, counter);
    return nonce;
  }
}
