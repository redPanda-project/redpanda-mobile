import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

/// T44 channel-rendezvous DHT primitives — the mobile counterpart of the
/// backend `im.redpanda.outbound.ChannelDht` (T43,
/// `docs/docs/channel_rendezvous_dht.md`).
///
/// A channel is a keypair; QR v4 shares the 32-byte channel secret, so every
/// participant — and only they — can compute the derived rendezvous keypair,
/// hence the same daily-rotating Kademlia key, sign records and decrypt their
/// content. The rendezvous record maps a channel to its participants' current
/// OH lists so a channel heals purely over the DHT even when all host nodes are
/// unreachable.
///
/// Byte-compatibility with the backend is asserted by cross-check vectors in
/// the unit tests (`channel_rendezvous_test.dart`): the derived `recordPubkey`,
/// the `rendezvousKademliaId` and the record signature all match the values the
/// reference `redpanda.jar` produces for the same channel secret.
class ChannelRendezvous {
  ChannelRendezvous._();

  /// Domain-separation tag for the rendezvous record signing key — matches the
  /// backend `ChannelDht.DOMAIN_TAG`. Keeps record keys in their own namespace,
  /// disjoint from node ids and OH-announce records.
  static const String domainTag = 'redpanda.channel.rendezvous.v1';

  /// HKDF info for `k_enc`, the symmetric key that encrypts all channel content
  /// (message ratchet root and the rendezvous record value). Derived purely
  /// from the channel secret — the QR v4 secret is the single capability.
  static const String kEncInfo = 'redpanda.channel.kenc.v4';

  /// HKDF info for the channel identity keypair seed (`channel_pk`).
  static const String authSeedInfo = 'redpanda.channel.auth.v4';

  /// SHA-256 domain tag for the per-role participant id (the merge key). A
  /// channel is 2-party; the creator and the joiner get distinct, derivable
  /// ids (`H(tag || sk || role)`), so neither side needs to store the peer's
  /// id — the recovering side simply looks up the opposite role.
  static const String participantTag = 'redpanda.channel.participant.v4';

  /// The 32-byte Ed25519 seed of the channel identity keypair:
  /// `HKDF(channelSecret, info=authSeedInfo)`.
  static Future<Uint8List> authSeed(List<int> channelSecret) {
    return CryptoUtils.hkdfSha256(
      channelSecret,
      const [],
      authSeedInfo,
      CryptoUtils.keyLength,
    );
  }

  /// The stable per-membership participant id (merge key) for a given role:
  /// `SHA256(participantTag || channelSecret || role)`, role 0 = creator,
  /// 1 = joiner.
  static Uint8List participantId(
    List<int> channelSecret, {
    required bool isCreator,
  }) {
    final input = Uint8List.fromList([
      ...latin1.encode(participantTag),
      ...channelSecret,
      isCreator ? 0 : 1,
    ]);
    return Uint8List.fromList(sha256.convert(input).bytes);
  }

  /// Fixed serialized size of every rendezvous record content — one bucket for
  /// all channels so record size leaks nothing (backend
  /// `ChannelDht.RECORD_SIZE_BYTES`). Layout: `[12 nonce][ciphertext+tag]`.
  /// Sized for the k=3 OH redundancy: two participants with three OH
  /// descriptors each (~74 bytes per descriptor at IPv4) need ~556 of the 996
  /// usable bytes, which no longer fit the previous 512-byte bucket. Must stay
  /// in lockstep with the backend — nodes reject every record of a different
  /// size.
  static const int recordSizeBytes = 1024;

  /// Length of the padded plaintext that lives inside the AEAD:
  /// `1024 - 12 nonce - 16 GCM tag`. All length/padding metadata is structural
  /// and lives inside this plaintext — no cleartext length field ever reveals
  /// the real payload size.
  static const int plaintextLength =
      recordSizeBytes - CryptoUtils.gcmNonceLength - CryptoUtils.gcmTagLength;

  /// Version byte of the encrypted plaintext framing.
  static const int plaintextVersion = 1;

  /// TTL for a rendezvous record: 48 h plus 2 h rotation slack — mirrors the
  /// backend `ChannelDht.MAX_RECORD_AGE_MS`. Records rotate under the UTC-day
  /// key, so a record published late yesterday stays usable through today.
  static const int maxRecordAgeMs = 1000 * 60 * 60 * (48 + 2);

  // ---------------------------------------------------------------------
  // Key derivation
  // ---------------------------------------------------------------------

  /// The 32-byte seed of the rendezvous record signing key:
  /// `SHA256(domainTag || channelSecret)`. Backend
  /// `ChannelDht.deriveRecordNodeId` seeds `NodeId.fromSeed` from exactly this.
  static Uint8List recordSeed(List<int> channelSecret) {
    final input = Uint8List.fromList([
      ...latin1.encode(domainTag),
      ...channelSecret,
    ]);
    return Uint8List.fromList(sha256.convert(input).bytes);
  }

  /// The 64-byte public export of the rendezvous record NodeId:
  /// `[32 Ed25519 verify key][32 X25519 encryption key]`. Matches the backend
  /// `NodeId.fromSeed(recordSeed).exportPublic()`: the Ed25519 key is seeded
  /// from `recordSeed`, the X25519 key from `SHA256(recordSeed)` (key
  /// separation).
  static Future<Uint8List> recordPublicExport(List<int> channelSecret) async {
    final seed = recordSeed(channelSecret);
    final signing = await CryptoUtils.signingKeypairFromSeed(seed);
    final x25519Seed = Uint8List.fromList(sha256.convert(seed).bytes);
    final encryption = await CryptoUtils.encryptionKeypairFromSeed(x25519Seed);
    return Uint8List.fromList([...signing.publicKey, ...encryption.publicKey]);
  }

  /// `k_enc = HKDF-SHA256(channelSecret, info=kEncInfo)` — the symmetric key
  /// for message content and rendezvous records.
  static Future<Uint8List> kEnc(List<int> channelSecret) {
    return CryptoUtils.hkdfSha256(
      channelSecret,
      const [],
      kEncInfo,
      CryptoUtils.aesKeyLength,
    );
  }

  /// Formats [timestampMs] as the backend's UTC `dd.MM.yy` day string used in
  /// the self-certifying Kademlia key. Manual formatting (no `intl`) to stay
  /// byte-for-byte identical to `java.text.SimpleDateFormat("dd.MM.yy")`.
  static String utcDayString(int timestampMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$dd.$mm.$yy';
  }

  /// The Kademlia key the rendezvous record lives under at [timestampMs]:
  /// `SHA256(dateUTC || recordPubkey)`, first 20 bytes. Rotates with the UTC
  /// date like every KadContent (backend `ChannelDht.rendezvousKademliaId` →
  /// `KadContent.createKademliaId`).
  static Future<Uint8List> rendezvousKademliaId(
    List<int> channelSecret,
    int timestampMs,
  ) async {
    final pub = await recordPublicExport(channelSecret);
    final dateBytes = latin1.encode(utcDayString(timestampMs));
    final digest = sha256.convert([...dateBytes, ...pub]).bytes;
    return Uint8List.fromList(digest.sublist(0, 20));
  }

  // ---------------------------------------------------------------------
  // Record plaintext codec (structural, fixed-length, padded inside AEAD)
  // ---------------------------------------------------------------------

  /// Serializes [entries] into the fixed [plaintextLength]-byte padded
  /// plaintext. Structural, count-driven — trailing zero padding carries no
  /// length metadata. Throws [ArgumentError] if the entries do not fit.
  static Uint8List encodeEntries(List<RendezvousEntry> entries) {
    final out = BytesBuilder();
    out.addByte(plaintextVersion);
    out.addByte(entries.length);
    for (final e in entries) {
      out.add(e.participantId);
      out.add(_uint64be(e.entryTs));
      final name = utf8.encode(e.name);
      if (name.length > 255) {
        throw ArgumentError.value(e.name, 'name', 'name too long (>255 bytes)');
      }
      out.addByte(name.length);
      out.add(name);
      if (e.ohs.length > 255) {
        throw ArgumentError.value(e.ohs.length, 'ohs', 'too many OHs');
      }
      out.addByte(e.ohs.length);
      for (final oh in e.ohs) {
        final ep = utf8.encode(oh.serverEndpoint);
        if (ep.length > 255) {
          throw ArgumentError.value(
            oh.serverEndpoint,
            'serverEndpoint',
            'endpoint too long (>255 bytes)',
          );
        }
        out.addByte(ep.length);
        out.add(ep);
        out.add(oh.handleId);
        out.add(oh.authPublicKey);
      }
    }
    final body = out.toBytes();
    if (body.length > plaintextLength) {
      throw ArgumentError.value(
        body.length,
        'entries',
        'rendezvous record exceeds $plaintextLength-byte bucket',
      );
    }
    final padded = Uint8List(plaintextLength);
    padded.setRange(0, body.length, body);
    return padded;
  }

  /// Parses the padded plaintext back into entries. Trailing padding after the
  /// declared participant count is ignored. Throws [FormatException] on a
  /// structurally invalid buffer.
  static List<RendezvousEntry> decodeEntries(Uint8List plaintext) {
    if (plaintext.length != plaintextLength) {
      throw FormatException(
        'rendezvous plaintext must be $plaintextLength bytes, '
        'got ${plaintext.length}',
      );
    }
    var offset = 0;
    int readByte() {
      if (offset >= plaintext.length) {
        throw const FormatException('rendezvous plaintext truncated');
      }
      return plaintext[offset++];
    }

    Uint8List readBytes(int n) {
      if (offset + n > plaintext.length) {
        throw const FormatException('rendezvous plaintext truncated');
      }
      final b = plaintext.sublist(offset, offset + n);
      offset += n;
      return b;
    }

    final version = readByte();
    if (version != plaintextVersion) {
      throw FormatException(
        'unsupported rendezvous plaintext version $version',
      );
    }
    final count = readByte();
    final entries = <RendezvousEntry>[];
    for (var i = 0; i < count; i++) {
      final participantId = readBytes(32);
      final ts = _uint64beToInt(readBytes(8));
      final nameLen = readByte();
      final name = utf8.decode(readBytes(nameLen));
      final ohCount = readByte();
      final ohs = <OHDescriptor>[];
      for (var j = 0; j < ohCount; j++) {
        final epLen = readByte();
        final ep = utf8.decode(readBytes(epLen));
        final handleId = readBytes(20);
        final authPub = readBytes(32);
        ohs.add(
          OHDescriptor(
            serverEndpoint: ep,
            handleId: handleId,
            authPublicKey: authPub,
          ),
        );
      }
      entries.add(
        RendezvousEntry(
          participantId: participantId,
          name: name,
          entryTs: ts,
          ohs: ohs,
        ),
      );
    }
    return entries;
  }

  // ---------------------------------------------------------------------
  // Record encrypt / decrypt
  // ---------------------------------------------------------------------

  /// Encrypts [entries] into the opaque fixed-size record content
  /// `[12 nonce][AEAD ciphertext of the padded plaintext]` (exactly
  /// [recordSizeBytes] bytes). The plaintext is padded to a fixed length inside
  /// the AEAD, so the ciphertext size never reveals the payload size.
  static Future<Uint8List> encryptRecordContent(
    List<int> channelSecret,
    List<RendezvousEntry> entries,
  ) async {
    final plaintext = encodeEntries(entries);
    final key = await kEnc(channelSecret);
    final nonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
    final ciphertext = await CryptoUtils.aesGcmEncrypt(
      key,
      nonce,
      plaintext,
      const [],
    );
    final content = Uint8List(recordSizeBytes);
    content.setRange(0, CryptoUtils.gcmNonceLength, nonce);
    content.setRange(CryptoUtils.gcmNonceLength, recordSizeBytes, ciphertext);
    return content;
  }

  /// Decrypts and parses the opaque record content. Throws
  /// [GcmAuthenticationException] on a wrong key/tampered content and
  /// [FormatException] on a structurally invalid buffer.
  static Future<List<RendezvousEntry>> decryptRecordContent(
    List<int> channelSecret,
    Uint8List content,
  ) async {
    if (content.length != recordSizeBytes) {
      throw FormatException(
        'rendezvous record content must be $recordSizeBytes bytes, '
        'got ${content.length}',
      );
    }
    final key = await kEnc(channelSecret);
    final nonce = content.sublist(0, CryptoUtils.gcmNonceLength);
    final ciphertext = content.sublist(CryptoUtils.gcmNonceLength);
    final plaintext = await CryptoUtils.aesGcmDecrypt(
      key,
      nonce,
      ciphertext,
      const [],
    );
    return decodeEntries(plaintext);
  }

  // ---------------------------------------------------------------------
  // Record signing (KademliaStore build) & newest-wins merge
  // ---------------------------------------------------------------------

  /// Builds the signed rendezvous record for [entries] at [timestampMs],
  /// returning the four `KademliaStore` fields the backend `record_store` needs:
  /// timestamp, 64-byte record public key, 1024-byte content and 64-byte
  /// signature. The signature is `Ed25519(recordSeed, SHA256(int64_be(ts) ||
  /// content))` — matches `KadContent.signWith`.
  static Future<SignedRendezvousRecord> buildSignedRecord(
    List<int> channelSecret,
    List<RendezvousEntry> entries,
    int timestampMs,
  ) async {
    final content = await encryptRecordContent(channelSecret, entries);
    return signContent(channelSecret, content, timestampMs);
  }

  /// Signs an already-encrypted [content] blob (must be [recordSizeBytes]).
  static Future<SignedRendezvousRecord> signContent(
    List<int> channelSecret,
    Uint8List content,
    int timestampMs,
  ) async {
    if (content.length != recordSizeBytes) {
      throw ArgumentError.value(
        content.length,
        'content',
        'record content must be $recordSizeBytes bytes',
      );
    }
    final seed = recordSeed(channelSecret);
    final pub = await recordPublicExport(channelSecret);
    final hash = sha256.convert([..._uint64be(timestampMs), ...content]).bytes;
    final signature = await CryptoUtils.sign(seed, hash);
    return SignedRendezvousRecord(
      timestampMs: timestampMs,
      publicKey: pub,
      content: content,
      signature: signature,
    );
  }

  /// Verifies a record's self-certifying Ed25519 signature over
  /// `SHA256(int64_be(ts) || content)` against its embedded verify key. Does
  /// not check TTL (that is the caller's decision at merge time).
  static Future<bool> verifyRecord(SignedRendezvousRecord record) async {
    if (record.publicKey.length != 64 ||
        record.content.length != recordSizeBytes ||
        record.signature.length != CryptoUtils.signatureLength) {
      return false;
    }
    final hash = sha256.convert([
      ..._uint64be(record.timestampMs),
      ...record.content,
    ]).bytes;
    return CryptoUtils.verify(
      record.publicKey.sublist(0, 32),
      hash,
      record.signature,
    );
  }

  /// Merges [existing] entries with [incoming], keeping the newest [entryTs]
  /// per `participantId`. This is the client-side per-participant newest-wins
  /// merge (the node/DHT layer only keeps the newest KadContent per key; a node
  /// cannot read the opaque value).
  static List<RendezvousEntry> mergeEntries(
    Iterable<RendezvousEntry> existing,
    Iterable<RendezvousEntry> incoming,
  ) {
    final byId = <String, RendezvousEntry>{};
    void absorb(RendezvousEntry e) {
      final key = _hex(e.participantId);
      final prev = byId[key];
      if (prev == null || e.entryTs > prev.entryTs) {
        byId[key] = e;
      }
    }

    for (final e in existing) {
      absorb(e);
    }
    for (final e in incoming) {
      absorb(e);
    }
    final merged = byId.values.toList()
      ..sort((a, b) => _hex(a.participantId).compareTo(_hex(b.participantId)));
    return merged;
  }

  static Uint8List _uint64be(int value) {
    final data = ByteData(8)..setUint64(0, value);
    return data.buffer.asUint8List();
  }

  static int _uint64beToInt(Uint8List bytes) {
    return ByteData.sublistView(bytes).getUint64(0);
  }

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// One participant's entry in a rendezvous record: a stable per-membership
/// [participantId] (the merge key), the display [name], the freshness
/// [entryTs] (ms) and the participant's current OH list.
class RendezvousEntry {
  final Uint8List participantId;
  final String name;
  final int entryTs;
  final List<OHDescriptor> ohs;

  RendezvousEntry({
    required List<int> participantId,
    required this.name,
    required this.entryTs,
    required this.ohs,
  }) : participantId = Uint8List.fromList(participantId) {
    if (this.participantId.length != 32) {
      throw ArgumentError.value(
        this.participantId.length,
        'participantId',
        'participant id must be 32 bytes',
      );
    }
  }
}

/// The four fields of a signed rendezvous record, ready to be wrapped into a
/// backend `KademliaStore` for `record_store` or reconstructed from a
/// `record_lookup` answer.
class SignedRendezvousRecord {
  final int timestampMs;
  final Uint8List publicKey;
  final Uint8List content;
  final Uint8List signature;

  SignedRendezvousRecord({
    required this.timestampMs,
    required List<int> publicKey,
    required List<int> content,
    required List<int> signature,
  }) : publicKey = Uint8List.fromList(publicKey),
       content = Uint8List.fromList(content),
       signature = Uint8List.fromList(signature);
}
