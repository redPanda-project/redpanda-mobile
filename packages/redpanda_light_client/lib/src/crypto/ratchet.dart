import 'dart:convert';
import 'dart:typed_data';

import 'package:hex/hex.dart';

import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';

/// Thrown when the ratchet cannot derive a key for an incoming message —
/// e.g. the gap to the last seen counter exceeds [RatchetSession.maxSkip],
/// or a replayed counter whose message key was already used and deleted.
class RatchetException implements Exception {
  final String message;
  RatchetException(this.message);

  @override
  String toString() => 'RatchetException: $message';
}

/// A ratchet state change for one channel; the app layer persists
/// [stateJson] (Drift `Channels.ratchetState`) so the ratchet survives
/// app restarts. The state never travels in the QR code or any backup
/// that leaves the device (master spec MS03b).
class RatchetStateUpdate {
  final String channelId;
  final String stateJson;
  const RatchetStateUpdate({required this.channelId, required this.stateJson});
}

/// MS03b Double-Ratchet session for one channel (Signal Double Ratchet over
/// the MS03 X25519/HKDF/AES-GCM primitives).
///
/// Stage 1 (forward secrecy): sending/receiving chains are one-way
/// HKDF-SHA256 chains — `MK_n = HKDF(CK_n, "redpanda-fs-msg")`,
/// `CK_{n+1} = HKDF(CK_n, "redpanda-fs-step")`. Old chain keys and used
/// message keys are dropped as soon as the chain advances, so capturing the
/// current state does not decrypt earlier messages.
///
/// Stage 2 (post-compromise security): every message carries the sender's
/// current X25519 ratchet public key (v4 envelope header). A fresh inbound
/// ratchet key triggers a DH step that mixes new entropy into the root key
/// and re-seeds both chains — one full round trip locks an attacker who
/// captured older state out of all future messages.
///
/// Initialization is deterministic from the shared channel key `K_enc`
/// (no extra handshake; QR stays v3). Roles are fixed by who generated the
/// channel:
///
/// - The **creator** starts with the *bootstrap ratchet keypair* (derived
///   from `K_enc` via `"redpanda-fs-boot-ratchet"`) as its own keypair and
///   the stage-1 bootstrap chain `CK_boot = HKDF(K_enc,
///   "redpanda-fs-chain-init")` as its sending chain, so it can send before
///   ever hearing from the joiner.
/// - The **joiner** generates a fresh ratchet keypair, performs the first DH
///   step against the bootstrap public key for its sending chain, and uses
///   `CK_boot` as its receiving chain.
///
/// Until the first full round trip both sides' chains are derivable from
/// `K_enc` (whoever holds the QR holds `K_enc` — that is the pre-MS03b
/// status quo for *all* messages); afterwards the root key contains fresh
/// DH entropy that `K_enc` alone cannot reproduce.
///
/// Out-of-order delivery (routine with store-and-forward) is handled with a
/// bounded store of skipped message keys: at most [maxSkip] keys are derived
/// per advance, at most [maxSkippedKeys] are retained per channel (oldest
/// evicted first) and entries expire after [skippedKeyLifetime].
///
/// Key deletion is best-effort: Dart cannot zeroize GC-managed memory, so
/// "deletion" means the state object and its persisted row only ever contain
/// the *current* keys (plus the bounded skipped-key store).
class RatchetSession {
  /// Maximum chain advance per incoming message (Open Question 2). A gap
  /// larger than this is declared undecryptable instead of grinding keys.
  static const int maxSkip = 512;

  /// Maximum number of retained skipped message keys per channel; the
  /// oldest entries are evicted first.
  static const int maxSkippedKeys = 1024;

  /// Retention period for skipped message keys.
  static const Duration skippedKeyLifetime = Duration(days: 30);

  static const String _infoRootInit = 'redpanda-fs-root-init';
  static const String _infoBootRatchet = 'redpanda-fs-boot-ratchet';
  static const String _infoChainInit = 'redpanda-fs-chain-init';
  static const String _infoRoot = 'redpanda-fs-root';
  static const String _infoMessageKey = 'redpanda-fs-msg';
  static const String _infoChainStep = 'redpanda-fs-step';

  Uint8List _rootKey;
  Uint8List _ownPrivateKey;
  Uint8List _ownPublicKey;
  Uint8List? _remotePublicKey;
  Uint8List? _sendChainKey;
  int _sendCount;
  Uint8List? _recvChainKey;
  int _recvCount;
  int _prevSendCount;
  final List<_SkippedKey> _skipped;

  /// Serializes encrypt/decrypt so concurrent calls cannot interleave their
  /// chain steps (which would reuse a message key / desync counters).
  Future<void> _pending = Future.value();

  RatchetSession._({
    required Uint8List rootKey,
    required Uint8List ownPrivateKey,
    required Uint8List ownPublicKey,
    required Uint8List? remotePublicKey,
    required Uint8List? sendChainKey,
    required int sendCount,
    required Uint8List? recvChainKey,
    required int recvCount,
    required int prevSendCount,
    required List<_SkippedKey> skipped,
  }) : _rootKey = rootKey,
       _ownPrivateKey = ownPrivateKey,
       _ownPublicKey = ownPublicKey,
       _remotePublicKey = remotePublicKey,
       _sendChainKey = sendChainKey,
       _sendCount = sendCount,
       _recvChainKey = recvChainKey,
       _recvCount = recvCount,
       _prevSendCount = prevSendCount,
       _skipped = skipped;

  /// Initializes a fresh ratchet for a channel from its 32-byte `K_enc`.
  ///
  /// [isChannelCreator] decides the role (see class docs); both sides must
  /// use their true role or their chains will not line up. In the app the
  /// creator is the device holding the channel auth private key; a device
  /// that imported the channel via QR is the joiner.
  static Future<RatchetSession> create({
    required List<int> channelKey,
    required bool isChannelCreator,
  }) async {
    if (channelKey.length != CryptoUtils.aesKeyLength) {
      throw ArgumentError.value(
        channelKey.length,
        'channelKey',
        'K_enc must be ${CryptoUtils.aesKeyLength} bytes',
      );
    }
    final rootInit = await CryptoUtils.hkdfSha256(
      channelKey,
      const [],
      _infoRootInit,
      CryptoUtils.keyLength,
    );
    final bootSeed = await CryptoUtils.hkdfSha256(
      channelKey,
      const [],
      _infoBootRatchet,
      CryptoUtils.keyLength,
    );
    final boot = await CryptoUtils.encryptionKeypairFromSeed(bootSeed);
    final bootChain = await CryptoUtils.hkdfSha256(
      channelKey,
      const [],
      _infoChainInit,
      CryptoUtils.keyLength,
    );

    if (isChannelCreator) {
      return RatchetSession._(
        rootKey: rootInit,
        ownPrivateKey: boot.privateKey,
        ownPublicKey: boot.publicKey,
        remotePublicKey: null,
        sendChainKey: bootChain,
        sendCount: 0,
        recvChainKey: null,
        recvCount: 0,
        prevSendCount: 0,
        skipped: [],
      );
    }

    final own = await CryptoUtils.generateEncryptionKeypair();
    final dh = await CryptoUtils.x25519(own.privateKey, boot.publicKey);
    final (rootKey, sendChain) = await _kdfRoot(rootInit, dh);
    return RatchetSession._(
      rootKey: rootKey,
      ownPrivateKey: own.privateKey,
      ownPublicKey: own.publicKey,
      remotePublicKey: boot.publicKey,
      sendChainKey: sendChain,
      sendCount: 0,
      recvChainKey: bootChain,
      recvCount: 0,
      prevSendCount: 0,
      skipped: [],
    );
  }

  /// Encrypts [message] into a v4 payload, advancing the sending chain.
  /// The previous chain key and the message key are dropped immediately.
  Future<Uint8List> encrypt(ChannelMessage message, String channelId) {
    return _synchronized(() async {
      final chainKey = _sendChainKey;
      if (chainKey == null) {
        // Cannot happen: both roles initialize a sending chain.
        throw StateError('ratchet has no sending chain');
      }
      final messageKey = await _messageKey(chainKey);
      final payload = await MessageCryptoV4.seal(
        messageKey: messageKey,
        ratchetPublicKey: _ownPublicKey,
        previousChainLength: _prevSendCount,
        chainCounter: _sendCount,
        plaintext: message.encode(),
        channelId: channelId,
      );
      _sendChainKey = await _stepChain(chainKey);
      _sendCount++;
      return payload;
    });
  }

  /// Verifies and decrypts a v4 [payload], advancing the receiving chain
  /// (and performing a DH ratchet step when the header carries a fresh
  /// ratchet key). Out-of-order messages are served from / recorded into
  /// the bounded skipped-key store.
  ///
  /// State is only committed when authentication succeeds — a tampered or
  /// undecryptable payload leaves the session unchanged. Throws
  /// [FormatException] (bad version/length), [RatchetException] (gap too
  /// large, replayed/expired counter) or [GcmAuthenticationException]
  /// (tampered payload or mismatching chains).
  Future<ChannelMessage> decrypt(List<int> payload, String channelId) {
    return _synchronized(() async {
      final header = MessageCryptoV4.parseHeader(payload);

      // 1. A message we already skipped past? Serve it from the stored key
      //    without touching the live chains.
      final skippedIndex = _skipped.indexWhere(
        (s) =>
            s.counter == header.chainCounter &&
            CryptoUtils.constantTimeEquals(
              s.ratchetPublicKey,
              header.ratchetPublicKey,
            ),
      );
      if (skippedIndex >= 0) {
        final plaintext = await MessageCryptoV4.open(
          payload: payload,
          messageKey: _skipped[skippedIndex].messageKey,
          channelId: channelId,
        );
        // Used exactly once — drop the key now that it served its message.
        _skipped.removeAt(skippedIndex);
        return ChannelMessage.decode(plaintext);
      }

      // 2. Advance on a copy; commit only after the GCM tag verified, so a
      //    forged header cannot corrupt or fast-forward the live state.
      final next = _Mutation(this);

      final remote = _remotePublicKey;
      final isNewRatchetKey =
          remote == null ||
          !CryptoUtils.constantTimeEquals(remote, header.ratchetPublicKey);
      if (isNewRatchetKey) {
        await next.skipReceivingChain(until: header.previousChainLength);
        await next.dhRatchetStep(header.ratchetPublicKey);
      } else if (header.chainCounter < _recvCount) {
        // Counter behind the chain and not in the skipped store: the key was
        // already used (replay) or evicted/expired.
        throw RatchetException(
          'no message key for counter ${header.chainCounter} '
          '(chain already at $_recvCount — replayed or expired message)',
        );
      }
      await next.skipReceivingChain(until: header.chainCounter);

      final chainKey = next.recvChainKey;
      if (chainKey == null) {
        throw RatchetException('ratchet has no receiving chain');
      }
      final messageKey = await _messageKey(chainKey);
      final plaintext = await MessageCryptoV4.open(
        payload: payload,
        messageKey: messageKey,
        channelId: channelId,
      );

      next.recvChainKey = await _stepChain(chainKey);
      next.recvCount = header.chainCounter + 1;
      next.commit(this);
      _pruneSkipped();
      return ChannelMessage.decode(plaintext);
    });
  }

  // -----------------------------------------------------------------------
  // Persistence
  // -----------------------------------------------------------------------

  /// Serializes the full session (including skipped message keys) to JSON
  /// for on-device persistence. Treat the result as key material.
  String toJson() {
    return jsonEncode(<String, dynamic>{
      'v': 1,
      'rk': HEX.encode(_rootKey),
      'ownPriv': HEX.encode(_ownPrivateKey),
      'ownPub': HEX.encode(_ownPublicKey),
      'remotePub': _remotePublicKey != null
          ? HEX.encode(_remotePublicKey!)
          : null,
      'cks': _sendChainKey != null ? HEX.encode(_sendChainKey!) : null,
      'ns': _sendCount,
      'ckr': _recvChainKey != null ? HEX.encode(_recvChainKey!) : null,
      'nr': _recvCount,
      'pn': _prevSendCount,
      'skipped': [
        for (final s in _skipped)
          {
            'pub': HEX.encode(s.ratchetPublicKey),
            'n': s.counter,
            'mk': HEX.encode(s.messageKey),
            'ts': s.createdAtMs,
          },
      ],
    });
  }

  /// Restores a session persisted with [toJson]. Throws [FormatException]
  /// on malformed input.
  factory RatchetSession.fromJson(String json) {
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) {
        throw const FormatException('unsupported ratchet state');
      }
      Uint8List bytes(String field) =>
          Uint8List.fromList(HEX.decode(decoded[field] as String));
      Uint8List? maybeBytes(String field) => decoded[field] != null
          ? Uint8List.fromList(HEX.decode(decoded[field] as String))
          : null;

      return RatchetSession._(
        rootKey: bytes('rk'),
        ownPrivateKey: bytes('ownPriv'),
        ownPublicKey: bytes('ownPub'),
        remotePublicKey: maybeBytes('remotePub'),
        sendChainKey: maybeBytes('cks'),
        sendCount: decoded['ns'] as int,
        recvChainKey: maybeBytes('ckr'),
        recvCount: decoded['nr'] as int,
        prevSendCount: decoded['pn'] as int,
        skipped: [
          for (final entry in decoded['skipped'] as List)
            _SkippedKey(
              ratchetPublicKey: Uint8List.fromList(
                HEX.decode((entry as Map<String, dynamic>)['pub'] as String),
              ),
              counter: entry['n'] as int,
              messageKey: Uint8List.fromList(HEX.decode(entry['mk'] as String)),
              createdAtMs: entry['ts'] as int,
            ),
        ],
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      // Missing fields / wrong types surface as TypeError or similar —
      // normalize to the documented contract.
      throw FormatException('malformed ratchet state: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Internals
  // -----------------------------------------------------------------------

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<Uint8List> _messageKey(Uint8List chainKey) {
    return CryptoUtils.hkdfSha256(
      chainKey,
      const [],
      _infoMessageKey,
      CryptoUtils.keyLength,
    );
  }

  static Future<Uint8List> _stepChain(Uint8List chainKey) {
    return CryptoUtils.hkdfSha256(
      chainKey,
      const [],
      _infoChainStep,
      CryptoUtils.keyLength,
    );
  }

  /// Root KDF: mixes a DH output into the root key, yielding the next root
  /// key and a fresh chain key.
  static Future<(Uint8List, Uint8List)> _kdfRoot(
    Uint8List rootKey,
    Uint8List dhOutput,
  ) async {
    final out = await CryptoUtils.hkdfSha256(
      dhOutput,
      rootKey,
      _infoRoot,
      2 * CryptoUtils.keyLength,
    );
    return (
      Uint8List.sublistView(out, 0, CryptoUtils.keyLength),
      Uint8List.sublistView(out, CryptoUtils.keyLength),
    );
  }

  void _pruneSkipped() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch -
        skippedKeyLifetime.inMilliseconds;
    _skipped.removeWhere((s) => s.createdAtMs < cutoff);
    if (_skipped.length > maxSkippedKeys) {
      // Entries are appended in derivation order — drop the oldest first.
      _skipped.removeRange(0, _skipped.length - maxSkippedKeys);
    }
  }
}

/// A staged copy of the mutable ratchet state, committed only after a
/// successful decrypt.
class _Mutation {
  Uint8List rootKey;
  Uint8List ownPrivateKey;
  Uint8List ownPublicKey;
  Uint8List? remotePublicKey;
  Uint8List? sendChainKey;
  int sendCount;
  Uint8List? recvChainKey;
  int recvCount;
  int prevSendCount;
  final List<_SkippedKey> newSkipped = [];

  _Mutation(RatchetSession s)
    : rootKey = s._rootKey,
      ownPrivateKey = s._ownPrivateKey,
      ownPublicKey = s._ownPublicKey,
      remotePublicKey = s._remotePublicKey,
      sendChainKey = s._sendChainKey,
      sendCount = s._sendCount,
      recvChainKey = s._recvChainKey,
      recvCount = s._recvCount,
      prevSendCount = s._prevSendCount;

  /// Advances the receiving chain to [until], storing the skipped message
  /// keys so late deliveries remain decryptable.
  Future<void> skipReceivingChain({required int until}) async {
    final chainKey = recvChainKey;
    if (chainKey == null) {
      return; // No chain yet (creator before first DH step) — nothing to skip.
    }
    if (until - recvCount > RatchetSession.maxSkip) {
      throw RatchetException(
        'gap of ${until - recvCount} messages exceeds the maximum of '
        '${RatchetSession.maxSkip} skipped keys',
      );
    }
    var ck = chainKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    while (recvCount < until) {
      newSkipped.add(
        _SkippedKey(
          ratchetPublicKey: remotePublicKey!,
          counter: recvCount,
          messageKey: await RatchetSession._messageKey(ck),
          createdAtMs: now,
        ),
      );
      ck = await RatchetSession._stepChain(ck);
      recvCount++;
    }
    recvChainKey = ck;
  }

  /// Performs a DH ratchet step for a fresh inbound ratchet key: re-keys
  /// the receiving chain, generates a new own keypair and re-keys the
  /// sending chain (post-compromise security).
  Future<void> dhRatchetStep(Uint8List newRemotePublicKey) async {
    prevSendCount = sendCount;
    sendCount = 0;
    recvCount = 0;
    remotePublicKey = Uint8List.fromList(newRemotePublicKey);

    final dhRecv = await CryptoUtils.x25519(ownPrivateKey, newRemotePublicKey);
    final (rootAfterRecv, recvChain) = await RatchetSession._kdfRoot(
      rootKey,
      dhRecv,
    );
    recvChainKey = recvChain;

    final fresh = await CryptoUtils.generateEncryptionKeypair();
    ownPrivateKey = fresh.privateKey;
    ownPublicKey = fresh.publicKey;
    final dhSend = await CryptoUtils.x25519(ownPrivateKey, newRemotePublicKey);
    final (rootAfterSend, sendChain) = await RatchetSession._kdfRoot(
      rootAfterRecv,
      dhSend,
    );
    rootKey = rootAfterSend;
    sendChainKey = sendChain;
  }

  void commit(RatchetSession s) {
    s._rootKey = rootKey;
    s._ownPrivateKey = ownPrivateKey;
    s._ownPublicKey = ownPublicKey;
    s._remotePublicKey = remotePublicKey;
    s._sendChainKey = sendChainKey;
    s._sendCount = sendCount;
    s._recvChainKey = recvChainKey;
    s._recvCount = recvCount;
    s._prevSendCount = prevSendCount;
    s._skipped.addAll(newSkipped);
  }
}

/// A message key retained for a message that was skipped over (out-of-order
/// delivery), keyed by the sender ratchet public key and chain counter.
class _SkippedKey {
  final Uint8List ratchetPublicKey;
  final int counter;
  final Uint8List messageKey;
  final int createdAtMs;

  const _SkippedKey({
    required this.ratchetPublicKey,
    required this.counter,
    required this.messageKey,
    required this.createdAtMs,
  });
}
