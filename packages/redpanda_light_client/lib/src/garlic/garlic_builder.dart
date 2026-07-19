import 'dart:typed_data';

import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/garlic/return_path.dart';

/// A relay hop for a Flaschenpost v2 garlic path: the node's 20-byte
/// KademliaId and its 32-byte X25519 encryption public key.
class GarlicHop {
  final Uint8List nodeId;
  final Uint8List encryptionPublicKey;

  GarlicHop({required List<int> nodeId, required List<int> encryptionPublicKey})
    : nodeId = Uint8List.fromList(nodeId),
      encryptionPublicKey = Uint8List.fromList(encryptionPublicKey) {
    if (this.nodeId.length != nodeIdLength) {
      throw ArgumentError.value(
        this.nodeId.length,
        'nodeId',
        'hop KademliaId must be $nodeIdLength bytes',
      );
    }
    if (this.encryptionPublicKey.length != CryptoUtils.keyLength) {
      throw ArgumentError.value(
        this.encryptionPublicKey.length,
        'encryptionPublicKey',
        'hop X25519 key must be ${CryptoUtils.keyLength} bytes',
      );
    }
  }

  static const int nodeIdLength = 20;
}

/// Builds fixed-size multi-hop Flaschenpost v2 garlic packets (Frontend MS04).
///
/// Wire format (master spec, Decisions Backend-MS04 — mirrors the backend
/// `FlaschenpostV2.java`); every packet is exactly [packetSize] (2048) bytes:
///
/// ```
/// [1  version = 0x02]
/// [4  packet_id]          // random, dedup + loop protection
/// [20 next_hop]           // KademliaId of the relay that peels this layer
/// [12 nonce]              // AES-256-GCM nonce
/// [32 ephemeral_pub]      // X25519 ephemeral public key for this layer
/// [4  ciphertext_len]     // includes the 16-byte GCM tag
/// [N  ciphertext + tag]
/// [P  random padding]     // fill to 2048 bytes total
/// ```
///
/// Key derivation per layer: `key = HKDF-SHA256(ikm = X25519(ephemeralPriv,
/// hop.encryptionPub), salt = ephemeral_pub, info = "flaschenpost-v2", 32)`,
/// AES-256-GCM with the hop's 20-byte KademliaId as AAD (a packet redirected
/// to another relay fails authentication there).
///
/// Layer plaintexts start with a command byte:
///
/// ```
/// CMD_FORWARD        (0x01): [1 cmd][20 inner next_hop][12 nonce][32 eph_pub][4 ct_len][ct+tag]
/// CMD_DELIVER        (0x02): [1 cmd][20 oh_id][4 payload_len][payload][optional padding]
/// CMD_DELIVER_TAGGED (0x03): [1 cmd][20 oh_id][16 session_tag][4 payload_len][payload][opt. padding]
/// CMD_DELIVER_ACKED  (0x04): [1 cmd][20 oh_id][1 tag_len (0|16)][tag][return_path][4 payload_len][payload]
/// ```
///
/// `CMD_DELIVER_TAGGED` (MS05, Decisions Backend-MS05) is the reverse-garlic
/// deliver: the final hop deposits payload plus 16-byte session tag into the
/// OH mailbox so the fetching client can correlate the reply.
///
/// `CMD_DELIVER_ACKED` (MS06, Decisions Backend-MS06) additionally carries a
/// return-path block of hop descriptors; the node with the final deposit
/// decision builds an R-ACK onion over it. The length-prefixed session tag
/// lets untagged forward sends and tagged RGB replies use the same command.
///
/// FORWARD plaintexts carry the next layer's body without own padding — the
/// relay re-pads to 2048 bytes when it rebuilds the peeled packet.
class GarlicBuilder {
  GarlicBuilder._();

  /// Version byte of the fixed-size garlic packet format.
  static const int version = 0x02;

  /// Every Flaschenpost v2 packet is exactly this many bytes.
  static const int packetSize = 2048;

  /// HKDF info, domain-separated from the single-layer garlic ("garlic-v2").
  static const String hkdfInfo = 'flaschenpost-v2';

  /// Layer command: peel and forward to the contained inner next hop.
  static const int cmdForward = 0x01;

  /// Layer command: final hop — deposit the payload into the OH mailbox.
  static const int cmdDeliver = 0x02;

  /// Layer command (MS05): final hop — deposit payload plus session tag
  /// into the OH mailbox (reverse-garlic reply).
  static const int cmdDeliverTagged = 0x03;

  /// Layer command (MS06): like deliver/deliver-tagged, but carries a
  /// return-path block — the depositing node sends an R-ACK back over it.
  static const int cmdDeliverAcked = 0x04;

  /// Layer command (T44): final hop — store a channel-rendezvous record in the
  /// DHT. Plaintext `[1 cmd][4 len][KademliaStore proto]`. Best-effort, no
  /// response (the client confirms by a later lookup).
  static const int cmdRecordStore = 0x05;

  /// Layer command (T44): final hop — look a channel-rendezvous record up in
  /// the DHT and answer via the return path. Plaintext
  /// `[1 cmd][20 recordKey][ReturnPath]`.
  static const int cmdRecordLookup = 0x06;

  /// Reverse-garlic session tags are exactly this many bytes (backend
  /// `FlaschenpostV2.SESSION_TAG_LEN`).
  static const int sessionTagLength = 16;

  /// Layer body prefix: [12 nonce][32 ephemeral_pub][4 ciphertext_len] (48).
  static const int bodyHeaderLength =
      CryptoUtils.gcmNonceLength + CryptoUtils.keyLength + 4;

  /// Packet header before the ciphertext:
  /// version + packet_id + next_hop + body header (73).
  static const int headerLength =
      1 + 4 + GarlicHop.nodeIdLength + bodyHeaderLength;

  /// Maximum ciphertext length (including tag) fitting a packet (1975).
  static const int maxCiphertextLength = packetSize - headerLength;

  /// Minimum ciphertext: GCM tag + at least the 1-byte layer command (17).
  static const int minCiphertextLength = CryptoUtils.gcmTagLength + 1;

  /// Bytes each FORWARD layer adds to the outermost plaintext:
  /// 21 (cmd + inner next_hop) + 48 (body header) + 16 (GCM tag) = 85.
  static const int forwardLayerOverhead =
      1 + GarlicHop.nodeIdLength + bodyHeaderLength + CryptoUtils.gcmTagLength;

  /// Fixed bytes of the DELIVER plaintext: cmd + oh_id + payload_len (25).
  static const int deliverHeaderLength = 1 + GarlicHop.nodeIdLength + 4;

  /// Fixed bytes of the DELIVER_TAGGED plaintext:
  /// cmd + oh_id + session_tag + payload_len (41).
  static const int taggedDeliverHeaderLength =
      deliverHeaderLength + sessionTagLength;

  /// Maximum deliver payload for a path of [hopCount] hops.
  /// 3 hops: 1764 bytes untagged (master spec MS04, Decision 6),
  /// 1748 bytes tagged (master spec MS05, Decision 7).
  static int maxPayloadLength(int hopCount, {bool tagged = false}) =>
      maxCiphertextLength -
      CryptoUtils.gcmTagLength -
      (tagged ? taggedDeliverHeaderLength : deliverHeaderLength) -
      (hopCount - 1) * forwardLayerOverhead;

  /// Fixed bytes of the DELIVER_ACKED plaintext before the return path:
  /// cmd + oh_id + tag_len byte + tag (0|16) + payload_len (26 + tag).
  static int ackedDeliverHeaderLength({required bool tagged}) =>
      1 + GarlicHop.nodeIdLength + 1 + (tagged ? sessionTagLength : 0) + 4;

  /// Maximum DELIVER_ACKED payload for [hopCount] forward hops and a return
  /// path with [returnHopCount] hops. Tagged, 3 forward + 3 return hops:
  /// **1554 bytes** (master spec MS06, Decision 6).
  static int maxAckedPayloadLength(
    int hopCount, {
    required bool tagged,
    required int returnHopCount,
  }) =>
      maxCiphertextLength -
      CryptoUtils.gcmTagLength -
      ackedDeliverHeaderLength(tagged: tagged) -
      ReturnPathBlock.serializedLength(returnHopCount) -
      (hopCount - 1) * forwardLayerOverhead;

  /// Builds a layered 2048-byte garlic packet along [hops]: CMD_FORWARD
  /// layers for all but the last hop and a CMD_DELIVER layer (to the OH
  /// mailbox [ohId]) for the last hop. The packet is handed to the connected
  /// full node, which routes it to `hops[0]` by KademliaId.
  ///
  /// With a 16-byte [sessionTag] (MS05 reverse-garlic reply), the innermost
  /// layer is CMD_DELIVER_TAGGED instead, depositing payload plus tag.
  ///
  /// With a [returnPath] (MS06), the innermost layer is CMD_DELIVER_ACKED:
  /// the depositing node sends an R-ACK back over the contained hop
  /// descriptors. The length-prefixed tag makes the tagged and untagged
  /// variants one command.
  ///
  /// Throws [ArgumentError] for an empty path, a non-20-byte [ohId], a
  /// malformed [sessionTag] or a [payload] exceeding [maxPayloadLength]
  /// (or [maxAckedPayloadLength] with a return path) for the path length.
  static Future<Uint8List> build({
    required List<GarlicHop> hops,
    required List<int> ohId,
    required List<int> payload,
    List<int>? sessionTag,
    ReturnPathBlock? returnPath,
  }) async {
    if (hops.isEmpty) {
      throw ArgumentError.value(hops.length, 'hops', 'need at least one hop');
    }
    if (ohId.length != GarlicHop.nodeIdLength) {
      throw ArgumentError.value(
        ohId.length,
        'ohId',
        'oh_id must be ${GarlicHop.nodeIdLength} bytes',
      );
    }
    if (sessionTag != null && sessionTag.length != sessionTagLength) {
      throw ArgumentError.value(
        sessionTag.length,
        'sessionTag',
        'session_tag must be $sessionTagLength bytes',
      );
    }
    final maxPayload = returnPath != null
        ? maxAckedPayloadLength(
            hops.length,
            tagged: sessionTag != null,
            returnHopCount: returnPath.hops.length,
          )
        : maxPayloadLength(hops.length, tagged: sessionTag != null);
    if (payload.length > maxPayload) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'payload exceeds $maxPayload bytes for ${hops.length} hops',
      );
    }

    // Innermost layer (last hop): CMD_DELIVER / CMD_DELIVER_TAGGED /
    // CMD_DELIVER_ACKED with explicit payload_len.
    final deliver = BytesBuilder();
    if (returnPath != null) {
      deliver
        ..addByte(cmdDeliverAcked)
        ..add(ohId)
        ..addByte(sessionTag?.length ?? 0)
        ..add(sessionTag ?? const [])
        ..add(returnPath.serialize());
    } else {
      deliver
        ..addByte(sessionTag != null ? cmdDeliverTagged : cmdDeliver)
        ..add(ohId)
        ..add(sessionTag ?? const []);
    }
    deliver
      ..add(_uint32be(payload.length))
      ..add(payload);
    return _wrap(hops, deliver.toBytes());
  }

  /// Builds a garlic packet whose innermost layer is `CMD_RECORD_STORE` (T44):
  /// a channel-rendezvous record is stored in the DHT on behalf of this
  /// DHT-fremd client. The record travels to a **remote** node so the directly
  /// connected node never sees the query interest. Best-effort, no response.
  ///
  /// [kademliaStore] is the serialized backend `KademliaStore` proto
  /// (timestamp, 64-byte record pubkey, 512-byte content, 64-byte signature).
  static Future<Uint8List> buildRecordStore({
    required List<GarlicHop> hops,
    required List<int> kademliaStore,
  }) {
    if (hops.isEmpty) {
      throw ArgumentError.value(hops.length, 'hops', 'need at least one hop');
    }
    final inner = BytesBuilder()
      ..addByte(cmdRecordStore)
      ..add(_uint32be(kademliaStore.length))
      ..add(kademliaStore);
    return _wrap(hops, inner.toBytes());
  }

  /// Builds a garlic packet whose innermost layer is `CMD_RECORD_LOOKUP` (T44):
  /// the remote node resolves the rendezvous record for [recordKey] and answers
  /// via [returnPath] (reverse garlic into the client's own OH mailbox).
  static Future<Uint8List> buildRecordLookup({
    required List<GarlicHop> hops,
    required List<int> recordKey,
    required ReturnPathBlock returnPath,
  }) {
    if (hops.isEmpty) {
      throw ArgumentError.value(hops.length, 'hops', 'need at least one hop');
    }
    if (recordKey.length != GarlicHop.nodeIdLength) {
      throw ArgumentError.value(
        recordKey.length,
        'recordKey',
        'record key must be ${GarlicHop.nodeIdLength} bytes',
      );
    }
    final inner = BytesBuilder()
      ..addByte(cmdRecordLookup)
      ..add(recordKey)
      ..add(returnPath.serialize());
    return _wrap(hops, inner.toBytes());
  }

  /// Wraps an already-built innermost layer plaintext in CMD_FORWARD layers
  /// from the second-to-last hop outward and assembles the fixed-size packet.
  /// The plaintext of each FORWARD layer is exactly the next layer's body — no
  /// own padding (the relay re-pads to [packetSize]).
  static Future<Uint8List> _wrap(
    List<GarlicHop> hops,
    List<int> innermostPlaintext,
  ) async {
    var body = await encryptLayer(
      hops.last.encryptionPublicKey,
      hops.last.nodeId,
      innermostPlaintext,
    );
    for (var i = hops.length - 2; i >= 0; i--) {
      final forward = BytesBuilder()
        ..addByte(cmdForward)
        ..add(hops[i + 1].nodeId)
        ..add(body);
      body = await encryptLayer(
        hops[i].encryptionPublicKey,
        hops[i].nodeId,
        forward.toBytes(),
      );
    }
    return buildPacket(hops.first.nodeId, body);
  }

  /// Assembles the fixed-size packet from the outermost layer [body]
  /// (`[nonce][ephemeral_pub][ct_len][ct+tag]`) with a random packet_id and
  /// random padding to exactly [packetSize] bytes.
  static Uint8List buildPacket(List<int> nextHop, List<int> body) {
    final packet = BytesBuilder()
      ..addByte(version)
      ..add(CryptoUtils.randomBytes(4)) // packet_id
      ..add(nextHop)
      ..add(body);
    final padding = packetSize - packet.length;
    if (padding < 0) {
      throw ArgumentError.value(
        body.length,
        'body',
        'flaschenpost v2 body does not fit the $packetSize-byte packet',
      );
    }
    packet.add(CryptoUtils.randomBytes(padding));
    return packet.toBytes();
  }

  /// Encrypts one garlic layer for a hop: fresh ephemeral X25519 key, random
  /// nonce, HKDF-derived AES-256-GCM key, the hop's KademliaId as AAD.
  ///
  /// Returns the layer body `[12 nonce][32 ephemeral_pub][4 ct_len][ct+tag]`
  /// (the counterpart of the backend's `FlaschenpostV2.encryptLayer`).
  static Future<Uint8List> encryptLayer(
    List<int> hopEncryptionPublicKey,
    List<int> hopNodeId,
    List<int> plaintext,
  ) async {
    final ephemeral = await CryptoUtils.generateEncryptionKeypair();
    final shared = await CryptoUtils.x25519(
      ephemeral.privateKey,
      hopEncryptionPublicKey,
    );
    final key = await CryptoUtils.hkdfSha256(
      shared,
      ephemeral.publicKey,
      hkdfInfo,
      CryptoUtils.aesKeyLength,
    );
    final nonce = CryptoUtils.randomBytes(CryptoUtils.gcmNonceLength);
    final ciphertext = await CryptoUtils.aesGcmEncrypt(
      key,
      nonce,
      plaintext,
      hopNodeId,
    );

    final body = BytesBuilder()
      ..add(nonce)
      ..add(ephemeral.publicKey)
      ..add(_uint32be(ciphertext.length))
      ..add(ciphertext);
    return body.toBytes();
  }

  static Uint8List _uint32be(int value) {
    final data = ByteData(4)..setUint32(0, value);
    return data.buffer.asUint8List();
  }
}
