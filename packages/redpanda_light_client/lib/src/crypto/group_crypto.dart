import 'dart:convert';
import 'dart:typed_data';

import 'package:hex/hex.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';

/// Thrown when a v5 group envelope carries an epoch this session has no keys
/// for (newer than the current epoch, or older than the archive). The caller
/// buffers the item and drains the buffer once the rotation arrives
/// (master spec MS08, Decision 10).
class GroupUnknownEpochException implements Exception {
  final int epoch;
  GroupUnknownEpochException(this.epoch);

  @override
  String toString() => 'GroupUnknownEpochException: epoch $epoch';
}

/// Thrown when a group envelope cannot be decrypted for a non-epoch reason:
/// unknown sender, bad signature, replayed counter or a skip gap beyond the
/// bounds. The item is dropped (re-sending it can never succeed).
class GroupCryptoException implements Exception {
  final String message;
  GroupCryptoException(this.message);

  @override
  String toString() => 'GroupCryptoException: $message';
}

/// The result of decrypting a v5 group envelope: the inner plaintext plus
/// the authenticated sender.
class GroupDecryptResult {
  final Uint8List plaintext;

  /// Sender member id (hex) — verified via the envelope's Ed25519 signature
  /// (the member id is the verify key, Decision 4).
  final String senderMemberIdHex;

  /// The key epoch the message was encrypted under.
  final int epoch;

  const GroupDecryptResult({
    required this.plaintext,
    required this.senderMemberIdHex,
    required this.epoch,
  });
}

/// MS08 group crypto session: epoch sender keys (master spec MS08,
/// Decisions 3–6).
///
/// Per epoch `e`, all members derive from one admin-distributed 32-byte
/// `group_secret_e`:
///
/// ```
/// ck_0(M)  = HKDF(secret_e, info = "ms08-chain-v1" ‖ member_id_M)
/// K_out(e) = HKDF(secret_e, info = "ms08-outer-v1")
/// MK_N     = HKDF(ck_N, "ms08-msg-v1");  ck_{N+1} = HKDF(ck_N, "ms08-adv-v1")
/// ```
///
/// The secret itself is **not stored** — [installEpoch] derives every
/// member's chain seed plus the outer key and lets the secret go out of
/// scope, so hash-chain forward secrecy holds from installation onward
/// (used message keys and chain keys are dropped as the chains advance).
///
/// Envelope v5 (group message):
///
/// ```
/// outer: [0x05][key_epoch 4 BE][nonce 12][ct+tag]     // K_out, AAD = utf8(group_id)
/// inner: [member_id 32][N 4 BE][nonce 12][ct+tag][sig 64]
///        inner AAD = utf8(group_id) ‖ epoch ‖ member_id ‖ N
///        sig = Ed25519(member) over AAD ‖ nonce ‖ ct
/// ```
///
/// The outer layer hides the sender pseudonym and counter from the OH host
/// (metadata matrix, Decision 5); the inner signature provides sender
/// authenticity — an attacker (or another member) cannot forge messages for
/// a member id they do not hold the signing seed of, and an unknown member
/// id has no derived chain, so membership is enforced implicitly.
///
/// Envelope v6 (sealed control, Decision 6) is stateless and lives in the
/// static [seal]/[unseal] pair.
///
/// Out-of-order delivery uses a bounded skipped-key store per sender chain
/// (bounds mirror the 1:1 ratchet, Decision 11); superseded epochs stay in
/// a bounded archive for late arrivals and expire after [epochLifetime].
class GroupCryptoSession {
  /// Version bytes, continuing the v3/v4 envelope numbering.
  static const int versionGroupMessage = 0x05;
  static const int versionSealedControl = 0x06;

  static const String _infoChain = 'ms08-chain-v1';
  static const String _infoOuter = 'ms08-outer-v1';
  static const String _infoMessageKey = 'ms08-msg-v1';
  static const String _infoChainStep = 'ms08-adv-v1';
  static const String _infoSealed = 'ms08-sealed-v1';

  /// Maximum chain advance per incoming message (Decision 11).
  static const int maxSkip = 512;

  /// Maximum retained skipped keys across all chains of the group.
  static const int maxSkippedKeys = 2048;

  /// Retention for skipped keys and archived epochs (Decision 11).
  static const Duration epochLifetime = Duration(days: 30);

  /// Fixed envelope overhead: outer (1 + 4 + 12 + 16) + inner
  /// (32 + 4 + 12 + 16 + 64) = 161 bytes (master spec MS08, Decision 5).
  static const int envelopeOverhead = 161;

  final String groupId;
  int _epoch;
  Uint8List? _outerKey;

  /// Live sender chains by member id (hex). Only members present at the
  /// epoch install have a chain — the implicit membership check.
  final Map<String, _SenderChain> _chains;

  /// Superseded epochs kept for late arrivals, by epoch number.
  final Map<int, _ArchivedEpoch> _archive;

  /// Serializes encrypt/decrypt so concurrent calls cannot interleave
  /// their chain steps (mirrors `RatchetSession`).
  Future<void> _pending = Future.value();

  GroupCryptoSession._({
    required this.groupId,
    required int epoch,
    required Uint8List? outerKey,
    required Map<String, _SenderChain> chains,
    required Map<int, _ArchivedEpoch> archive,
  }) : _epoch = epoch,
       _outerKey = outerKey,
       _chains = chains,
       _archive = archive;

  /// A fresh session with no epoch installed yet (epoch 0) — the state of a
  /// joiner waiting for its first rotation.
  factory GroupCryptoSession.empty(String groupId) {
    return GroupCryptoSession._(
      groupId: groupId,
      epoch: 0,
      outerKey: null,
      chains: {},
      archive: {},
    );
  }

  /// The current key epoch (0 = none installed).
  int get epoch => _epoch;

  /// True once an epoch is installed and messages can be sent/received.
  bool get hasEpoch => _epoch > 0 && _outerKey != null;

  /// Installs epoch [newEpoch] from its 32-byte [secret]: derives the outer
  /// key and one chain seed per member in [memberIdsHex], archives the
  /// previous epoch and lets the secret go out of scope (Decision 3).
  ///
  /// Rotations may arrive out of order; an epoch at or below the current one
  /// is ignored (returns false). Returns true when the epoch was installed.
  Future<bool> installEpoch(
    int newEpoch,
    List<int> secret,
    List<String> memberIdsHex,
  ) {
    return _synchronized(() async {
      if (secret.length != CryptoUtils.aesKeyLength) {
        throw ArgumentError.value(
          secret.length,
          'secret',
          'group secret must be ${CryptoUtils.aesKeyLength} bytes',
        );
      }
      if (newEpoch <= _epoch) return false;

      final outerKey = await CryptoUtils.hkdfSha256(
        secret,
        const [],
        _infoOuter,
        CryptoUtils.aesKeyLength,
      );
      final chains = <String, _SenderChain>{};
      for (final memberIdHex in memberIdsHex) {
        final memberId = HEX.decode(memberIdHex);
        final seed = await CryptoUtils.hkdfSha256(
          secret,
          memberId,
          _infoChain,
          CryptoUtils.keyLength,
        );
        chains[memberIdHex] = _SenderChain(chainKey: seed, next: 0);
      }

      if (hasEpoch) {
        _archive[_epoch] = _ArchivedEpoch(
          outerKey: _outerKey!,
          chains: Map.of(_chains),
          archivedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
      _epoch = newEpoch;
      _outerKey = outerKey;
      _chains
        ..clear()
        ..addAll(chains);
      _pruneArchive();
      return true;
    });
  }

  /// Encrypts [plaintext] into a v5 group envelope, advancing the own
  /// sender chain. The previous chain key and the message key are dropped.
  Future<Uint8List> encrypt(
    List<int> plaintext, {
    required String myMemberIdHex,
    required List<int> mySignSeed,
  }) {
    return _synchronized(() async {
      final outerKey = _outerKey;
      if (outerKey == null) {
        throw StateError('group $groupId has no epoch installed');
      }
      final chain = _chains[myMemberIdHex];
      if (chain == null) {
        throw StateError('own member id has no chain in epoch $_epoch');
      }

      final memberId = Uint8List.fromList(HEX.decode(myMemberIdHex));
      final counter = chain.next;
      final messageKey = await _messageKey(chain.chainKey);
      final aad = _innerAad(_epoch, memberId, counter);
      final innerNonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
      final innerCt = await CryptoUtils.aesGcmEncrypt(
        messageKey,
        innerNonce,
        plaintext,
        aad,
      );
      final signature = await CryptoUtils.sign(mySignSeed, [
        ...aad,
        ...innerNonce,
        ...innerCt,
      ]);

      final inner = BytesBuilder()
        ..add(memberId)
        ..add(_uint32be(counter))
        ..add(innerNonce)
        ..add(innerCt)
        ..add(signature);

      final outerNonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
      final outerCt = await CryptoUtils.aesGcmEncrypt(
        outerKey,
        outerNonce,
        inner.toBytes(),
        utf8.encode(groupId),
      );

      // Commit the advance only after everything above succeeded.
      chain.chainKey = await _stepChain(chain.chainKey);
      chain.next = counter + 1;

      final out = BytesBuilder()
        ..addByte(versionGroupMessage)
        ..add(_uint32be(_epoch))
        ..add(outerNonce)
        ..add(outerCt);
      return out.toBytes();
    });
  }

  /// Verifies and decrypts a v5 group envelope, advancing the sender's
  /// chain (out-of-order messages are served from / recorded into the
  /// bounded skipped-key store).
  ///
  /// Throws [GroupUnknownEpochException] when the epoch has no keys here
  /// (buffer the item), [GroupCryptoException] for unknown senders, bad
  /// signatures, replays or oversized gaps, [GcmAuthenticationException]
  /// for tampered ciphertexts and [FormatException] for malformed input.
  Future<GroupDecryptResult> decrypt(List<int> payload) {
    return _synchronized(() async {
      final data = Uint8List.fromList(payload);
      if (data.length < 1 + 4 + CryptoUtils.gcmNonceLength) {
        throw const FormatException('group envelope: truncated header');
      }
      if (data[0] != versionGroupMessage) {
        throw FormatException('group envelope: bad version ${data[0]}');
      }
      final epoch = ByteData.sublistView(data, 1, 5).getUint32(0);
      final outerNonce = Uint8List.sublistView(
        data,
        5,
        5 + CryptoUtils.gcmNonceLength,
      );
      final outerCt = Uint8List.sublistView(
        data,
        5 + CryptoUtils.gcmNonceLength,
      );

      final Uint8List outerKey;
      final Map<String, _SenderChain> chains;
      if (epoch == _epoch && _outerKey != null) {
        outerKey = _outerKey!;
        chains = _chains;
      } else {
        final archived = _archive[epoch];
        if (archived == null) throw GroupUnknownEpochException(epoch);
        outerKey = archived.outerKey;
        chains = archived.chains;
      }

      final inner = await CryptoUtils.aesGcmDecrypt(
        outerKey,
        outerNonce,
        outerCt,
        utf8.encode(groupId),
      );

      // inner: [member_id 32][N 4][nonce 12][ct+tag >= 16][sig 64]
      const headerLength = 32 + 4 + CryptoUtils.gcmNonceLength;
      if (inner.length <
          headerLength +
              CryptoUtils.gcmTagLength +
              CryptoUtils.signatureLength) {
        throw const FormatException('group envelope: truncated inner');
      }
      final memberId = Uint8List.sublistView(inner, 0, 32);
      final counter = ByteData.sublistView(inner, 32, 36).getUint32(0);
      final innerNonce = Uint8List.sublistView(inner, 36, headerLength);
      final innerCt = Uint8List.sublistView(
        inner,
        headerLength,
        inner.length - CryptoUtils.signatureLength,
      );
      final signature = Uint8List.sublistView(
        inner,
        inner.length - CryptoUtils.signatureLength,
      );
      final memberIdHex = HEX.encode(memberId);

      final chain = chains[memberIdHex];
      if (chain == null) {
        throw GroupCryptoException(
          'no chain for sender $memberIdHex in epoch $epoch '
          '(not a member at that epoch)',
        );
      }

      // The member id is the verify key (Decision 4).
      final aad = _innerAad(epoch, memberId, counter);
      final signatureValid = await CryptoUtils.verify(memberId, [
        ...aad,
        ...innerNonce,
        ...innerCt,
      ], signature);
      if (!signatureValid) {
        throw GroupCryptoException('invalid sender signature');
      }

      // Serve a skipped counter from the store (single-use).
      final skippedIndex = chain.skipped.indexWhere(
        (s) => s.counter == counter,
      );
      if (skippedIndex >= 0) {
        final plaintext = await CryptoUtils.aesGcmDecrypt(
          chain.skipped[skippedIndex].messageKey,
          innerNonce,
          innerCt,
          aad,
        );
        chain.skipped.removeAt(skippedIndex);
        return GroupDecryptResult(
          plaintext: plaintext,
          senderMemberIdHex: memberIdHex,
          epoch: epoch,
        );
      }
      if (counter < chain.next) {
        throw GroupCryptoException(
          'no message key for counter $counter '
          '(chain already at ${chain.next} — replayed or expired message)',
        );
      }
      if (counter - chain.next > maxSkip) {
        throw GroupCryptoException(
          'gap of ${counter - chain.next} messages exceeds the maximum of '
          '$maxSkip skipped keys',
        );
      }

      // Advance on locals; commit only after the GCM tag verified.
      final newSkipped = <_SkippedKey>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      var ck = chain.chainKey;
      for (var n = chain.next; n < counter; n++) {
        newSkipped.add(
          _SkippedKey(
            counter: n,
            messageKey: await _messageKey(ck),
            createdAtMs: now,
          ),
        );
        ck = await _stepChain(ck);
      }
      final messageKey = await _messageKey(ck);
      final plaintext = await CryptoUtils.aesGcmDecrypt(
        messageKey,
        innerNonce,
        innerCt,
        aad,
      );

      chain.chainKey = await _stepChain(ck);
      chain.next = counter + 1;
      chain.skipped.addAll(newSkipped);
      _pruneSkipped();

      return GroupDecryptResult(
        plaintext: plaintext,
        senderMemberIdHex: memberIdHex,
        epoch: epoch,
      );
    });
  }

  // -----------------------------------------------------------------------
  // Sealed controls (envelope v6, Decision 6)
  // -----------------------------------------------------------------------

  /// Seals [plaintext] for the member holding [memberX25519Pub]:
  /// `[0x06][eph_pub 32][nonce 12][ct+tag]` with
  /// key = HKDF(X25519(eph, member), salt = eph_pub, "ms08-sealed-v1")
  /// and AAD = utf8(group id).
  static Future<Uint8List> seal(
    List<int> plaintext, {
    required List<int> memberX25519Pub,
    required String groupId,
  }) async {
    final ephemeral = await CryptoUtils.generateEncryptionKeypair();
    final shared = await CryptoUtils.x25519(
      ephemeral.privateKey,
      memberX25519Pub,
    );
    final key = await CryptoUtils.hkdfSha256(
      shared,
      ephemeral.publicKey,
      _infoSealed,
      CryptoUtils.aesKeyLength,
    );
    final nonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
    final ciphertext = await CryptoUtils.aesGcmEncrypt(
      key,
      nonce,
      plaintext,
      utf8.encode(groupId),
    );
    final out = BytesBuilder()
      ..addByte(versionSealedControl)
      ..add(ephemeral.publicKey)
      ..add(nonce)
      ..add(ciphertext);
    return out.toBytes();
  }

  /// Opens a sealed v6 control with the member's own X25519 private key.
  /// Throws [FormatException] on malformed input and
  /// [GcmAuthenticationException] when the box was not sealed for this key
  /// or group.
  static Future<Uint8List> unseal(
    List<int> payload, {
    required List<int> myX25519Priv,
    required String groupId,
  }) async {
    final data = Uint8List.fromList(payload);
    const headerLength = 1 + CryptoUtils.keyLength + CryptoUtils.gcmNonceLength;
    if (data.length < headerLength + CryptoUtils.gcmTagLength) {
      throw const FormatException('sealed control: truncated');
    }
    if (data[0] != versionSealedControl) {
      throw FormatException('sealed control: bad version ${data[0]}');
    }
    final ephPub = Uint8List.sublistView(data, 1, 1 + CryptoUtils.keyLength);
    final nonce = Uint8List.sublistView(
      data,
      1 + CryptoUtils.keyLength,
      headerLength,
    );
    final ciphertext = Uint8List.sublistView(data, headerLength);
    final shared = await CryptoUtils.x25519(myX25519Priv, ephPub);
    final key = await CryptoUtils.hkdfSha256(
      shared,
      ephPub,
      _infoSealed,
      CryptoUtils.aesKeyLength,
    );
    return CryptoUtils.aesGcmDecrypt(
      key,
      nonce,
      ciphertext,
      utf8.encode(groupId),
    );
  }

  // -----------------------------------------------------------------------
  // Persistence
  // -----------------------------------------------------------------------

  /// Serializes the session (chains, skipped keys, epoch archive) to JSON
  /// for on-device persistence. Treat the result as key material.
  String toJson() {
    Map<String, dynamic> encodeChains(Map<String, _SenderChain> chains) => {
      for (final entry in chains.entries)
        entry.key: {
          'ck': HEX.encode(entry.value.chainKey),
          'n': entry.value.next,
          'skipped': [
            for (final s in entry.value.skipped)
              {
                'n': s.counter,
                'mk': HEX.encode(s.messageKey),
                'ts': s.createdAtMs,
              },
          ],
        },
    };
    return jsonEncode(<String, dynamic>{
      'v': 1,
      'epoch': _epoch,
      'ko': _outerKey != null ? HEX.encode(_outerKey!) : null,
      'chains': encodeChains(_chains),
      'archive': {
        for (final entry in _archive.entries)
          entry.key.toString(): {
            'ko': HEX.encode(entry.value.outerKey),
            'chains': encodeChains(entry.value.chains),
            'ts': entry.value.archivedAtMs,
          },
      },
    });
  }

  /// Restores a session persisted with [toJson]. Throws [FormatException]
  /// on malformed input.
  factory GroupCryptoSession.fromJson(String groupId, String json) {
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) {
        throw const FormatException('unsupported group crypto state');
      }
      Map<String, _SenderChain> decodeChains(Map<String, dynamic> raw) => {
        for (final entry in raw.entries)
          entry.key: _SenderChain(
            chainKey: Uint8List.fromList(
              HEX.decode((entry.value as Map<String, dynamic>)['ck'] as String),
            ),
            next: entry.value['n'] as int,
            skipped: [
              for (final s in entry.value['skipped'] as List)
                _SkippedKey(
                  counter: (s as Map<String, dynamic>)['n'] as int,
                  messageKey: Uint8List.fromList(HEX.decode(s['mk'] as String)),
                  createdAtMs: s['ts'] as int,
                ),
            ],
          ),
      };
      return GroupCryptoSession._(
        groupId: groupId,
        epoch: decoded['epoch'] as int,
        outerKey: decoded['ko'] != null
            ? Uint8List.fromList(HEX.decode(decoded['ko'] as String))
            : null,
        chains: decodeChains(decoded['chains'] as Map<String, dynamic>),
        archive: {
          for (final entry
              in (decoded['archive'] as Map<String, dynamic>).entries)
            int.parse(entry.key): _ArchivedEpoch(
              outerKey: Uint8List.fromList(
                HEX.decode(
                  (entry.value as Map<String, dynamic>)['ko'] as String,
                ),
              ),
              chains: decodeChains(
                entry.value['chains'] as Map<String, dynamic>,
              ),
              archivedAtMs: entry.value['ts'] as int,
            ),
        },
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('malformed group crypto state: $e');
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

  Uint8List _innerAad(int epoch, Uint8List memberId, int counter) {
    final aad = BytesBuilder()
      ..add(utf8.encode(groupId))
      ..add(_uint32be(epoch))
      ..add(memberId)
      ..add(_uint32be(counter));
    return aad.toBytes();
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

  void _pruneSkipped() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - epochLifetime.inMilliseconds;
    var total = 0;
    for (final chain in _chains.values) {
      chain.skipped.removeWhere((s) => s.createdAtMs < cutoff);
      total += chain.skipped.length;
    }
    if (total > maxSkippedKeys) {
      // Evict oldest first across all chains.
      final all = <(_SenderChain, _SkippedKey)>[
        for (final chain in _chains.values)
          for (final s in chain.skipped) (chain, s),
      ]..sort((a, b) => a.$2.createdAtMs.compareTo(b.$2.createdAtMs));
      for (final (chain, key) in all.take(total - maxSkippedKeys)) {
        chain.skipped.remove(key);
      }
    }
  }

  void _pruneArchive() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - epochLifetime.inMilliseconds;
    _archive.removeWhere((_, epoch) => epoch.archivedAtMs < cutoff);
  }

  static Uint8List _uint32be(int value) {
    final data = ByteData(4)..setUint32(0, value);
    return data.buffer.asUint8List();
  }
}

/// One sender's hash chain within an epoch.
class _SenderChain {
  Uint8List chainKey;
  int next;
  final List<_SkippedKey> skipped;

  _SenderChain({
    required this.chainKey,
    required this.next,
    List<_SkippedKey>? skipped,
  }) : skipped = skipped ?? [];
}

/// A message key retained for an out-of-order message.
class _SkippedKey {
  final int counter;
  final Uint8List messageKey;
  final int createdAtMs;

  const _SkippedKey({
    required this.counter,
    required this.messageKey,
    required this.createdAtMs,
  });
}

/// A superseded epoch kept for late arrivals (Decision 11).
class _ArchivedEpoch {
  final Uint8List outerKey;
  final Map<String, _SenderChain> chains;
  final int archivedAtMs;

  const _ArchivedEpoch({
    required this.outerKey,
    required this.chains,
    required this.archivedAtMs,
  });
}
