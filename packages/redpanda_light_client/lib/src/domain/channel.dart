import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:hex/hex.dart';

import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

/// Represents a secure communication channel (key model v4, T44).
///
/// A channel **is** a keypair. QR v4 shares only the 32-byte channel secret
/// (`channel_sk`); everything else is derived deterministically:
///
/// - [encryptionKey] `k_enc = HKDF(channel_sk)` — the symmetric key for all
///   channel content (the message ratchet root and the rendezvous record).
/// - [authPublicKey] — the channel identity public key (`channel_pk`), the
///   Ed25519 verify key of the keypair seeded from `HKDF(channel_sk, auth)`.
///   Shared, deterministic, identical on both devices.
/// - [authPrivateKey] — present **only** on the device that generated the
///   channel; it is the local **role marker** (creator vs joiner) that drives
///   the ratchet asymmetry, exactly as in v3. It is never put in the QR (both
///   sides could derive it from `channel_sk`, but only the creator keeps it, so
///   `authPrivateKey != null` still means "I am the creator").
/// - [channelSecret] — the QR v4 secret; the single capability that defines a
///   participant. Required to compute the rendezvous derivations
///   ([ChannelRendezvous]).
/// - [counterpartOhDescriptor] — the counterpart's OH descriptor, learned from the rendezvous
///   record (no longer carried in the QR).
///
/// The channel id is `SHA256(channel_pk)` (spec Decision 1), so both sides
/// derive the same id from `channel_sk` alone.
class Channel extends Equatable {
  final String label;
  final List<int> channelSecret;
  final List<int> encryptionKey;
  final List<int>? authPrivateKey;
  final List<int> authPublicKey;
  final OHDescriptor? counterpartOhDescriptor;

  const Channel({
    required this.label,
    required this.channelSecret,
    required this.encryptionKey,
    required this.authPublicKey,
    this.authPrivateKey,
    this.counterpartOhDescriptor,
  });

  /// Current QR version.
  static const int qrVersion = 4;

  /// Whether this device generated the channel (holds the role marker).
  bool get isCreator => authPrivateKey != null;

  /// Builds a channel from a 32-byte [channelSecret] and a local role.
  /// The creator keeps the derived identity private seed as its role marker;
  /// a joiner holds only the public key.
  static Future<Channel> fromSecret(
    String label,
    List<int> channelSecret, {
    required bool isCreator,
    OHDescriptor? counterpartOhDescriptor,
  }) async {
    if (channelSecret.length != 32) {
      throw ArgumentError.value(
        channelSecret.length,
        'channelSecret',
        'channel secret must be 32 bytes',
      );
    }
    final encKey = await ChannelRendezvous.kEnc(channelSecret);
    final authSeed = await ChannelRendezvous.authSeed(channelSecret);
    final authKeys = await CryptoUtils.signingKeypairFromSeed(authSeed);
    return Channel(
      label: label,
      channelSecret: List<int>.from(channelSecret),
      encryptionKey: encKey.toList(),
      authPrivateKey: isCreator ? authKeys.privateSeed.toList() : null,
      authPublicKey: authKeys.publicKey.toList(),
      counterpartOhDescriptor: counterpartOhDescriptor,
    );
  }

  /// Generates a new random channel: a fresh 32-byte `channel_sk` from which
  /// `k_enc` and the channel identity keypair are derived. The generating
  /// device is the creator (keeps the role marker).
  static Future<Channel> generate(String label) {
    return fromSecret(label, CryptoUtils.randomBytes(32), isCreator: true);
  }

  /// Creates a copy of this channel with the given fields replaced.
  Channel copyWith({OHDescriptor? counterpartOhDescriptor}) {
    return Channel(
      label: label,
      channelSecret: channelSecret,
      encryptionKey: encryptionKey,
      authPrivateKey: authPrivateKey,
      authPublicKey: authPublicKey,
      counterpartOhDescriptor:
          counterpartOhDescriptor ?? this.counterpartOhDescriptor,
    );
  }

  /// Serializes the channel to the v4 QR JSON `{v, l, sk}` — nothing beyond the
  /// channel secret ever needs to be shared.
  String toJson() {
    return jsonEncode(<String, dynamic>{
      'v': qrVersion,
      'l': label,
      'sk': HEX.encode(channelSecret),
    });
  }

  /// Deserializes a channel from its v4 QR JSON. A device that reads a QR is a
  /// **joiner** (no role marker).
  ///
  /// v1/v2/v3 codes are rejected without a migration path (spec Decision 1:
  /// "QR v3 is invalid without replacement"): both sides must re-pair with a
  /// fresh v4 code from an updated app.
  static Future<Channel> fromJson(String jsonStr) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } on FormatException {
      rethrow;
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('channel code is not a JSON object');
    }
    final version = decoded['v'];
    if (version != qrVersion) {
      throw FormatException(
        'Unsupported channel version: $version (this app requires v$qrVersion '
        'codes; re-pair with a fresh QR code from an updated app)',
      );
    }
    final sk = decoded['sk'];
    final label = decoded['l'];
    if (sk is! String || label is! String) {
      throw const FormatException('channel code is missing "sk"/"l" strings');
    }
    final List<int> channelSecret;
    try {
      channelSecret = HEX.decode(sk);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('channel_sk is not valid hex');
    }
    if (channelSecret.length != 32) {
      throw FormatException(
        'Invalid channel_sk length: expected 32 bytes, '
        'got ${channelSecret.length}',
      );
    }
    return fromSecret(label, channelSecret, isCreator: false);
  }

  /// The channel identity public key (`channel_pk`).
  List<int> get channelPublicKey => authPublicKey;

  /// This device's participant id (the rendezvous merge key for our own entry).
  List<int> get ownParticipantId =>
      ChannelRendezvous.participantId(channelSecret, isCreator: isCreator);

  /// The counterpart's participant id (the opposite role — what recovery looks up).
  List<int> get counterpartParticipantId =>
      ChannelRendezvous.participantId(channelSecret, isCreator: !isCreator);

  /// Channel id: `SHA256(channel_pk)` as hex (spec Decision 1).
  String get id {
    final digest = sha256.convert(channelPublicKey);
    return HEX.encode(digest.bytes);
  }

  @override
  List<Object?> get props => [
    label,
    channelSecret,
    encryptionKey,
    authPrivateKey,
    authPublicKey,
    counterpartOhDescriptor,
  ];
}
