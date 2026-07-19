import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';

/// T44 client-side rendezvous state and record builder — the pure business
/// logic behind publish/refresh and recovery, decoupled from the garlic
/// transport so it can be unit-tested in isolation.
///
/// For each channel it keeps the channel secret, the local role and the
/// newest-known entry per participant (the merge state). It builds the signed
/// record to publish (own fresh entry merged with the known peer entries, so
/// the newest surviving KadContent carries everyone) and, on a resolved record,
/// merges it in and surfaces the peer's current OH list.
class RendezvousManager {
  final Map<String, _ChannelRendezvousState> _states = {};

  /// Registers (or refreshes) a channel's rendezvous state. Idempotent — keeps
  /// the accumulated merge state across re-registrations.
  void register(
    String channelId, {
    required List<int> channelSecret,
    required bool isCreator,
    required String ownName,
  }) {
    final existing = _states[channelId];
    if (existing != null) {
      existing.ownName = ownName;
      return;
    }
    _states[channelId] = _ChannelRendezvousState(
      channelSecret: Uint8List.fromList(channelSecret),
      isCreator: isCreator,
      ownName: ownName,
    );
  }

  void remove(String channelId) => _states.remove(channelId);

  bool knows(String channelId) => _states.containsKey(channelId);

  /// All channel ids with rendezvous state (used by the daily republish).
  Iterable<String> get channels => _states.keys;

  List<int>? channelSecretOf(String channelId) =>
      _states[channelId]?.channelSecret;

  /// The `[today, yesterday]` Kademlia record keys to look a channel's record
  /// up under (records rotate under the UTC-day key, TTL 48 h).
  Future<List<Uint8List>> lookupKeys(String channelId, int nowMs) async {
    final state = _states[channelId];
    if (state == null) return const [];
    const dayMs = 1000 * 60 * 60 * 24;
    return [
      await ChannelRendezvous.rendezvousKademliaId(state.channelSecret, nowMs),
      await ChannelRendezvous.rendezvousKademliaId(
        state.channelSecret,
        nowMs - dayMs,
      ),
    ];
  }

  /// The Kademlia key to publish under (today's UTC-day key).
  Future<Uint8List?> publishKey(String channelId, int nowMs) async {
    final state = _states[channelId];
    if (state == null) return null;
    return ChannelRendezvous.rendezvousKademliaId(state.channelSecret, nowMs);
  }

  /// Records our own current OH set for [channelId] and returns whether it
  /// changed (a change is a publish trigger).
  bool setOwnOhs(String channelId, List<OHDescriptor> ohs) {
    final state = _states[channelId];
    if (state == null) return false;
    if (_sameOhList(state.ownOhs, ohs)) return false;
    state.ownOhs = List<OHDescriptor>.from(ohs);
    return true;
  }

  /// Builds the serialized `KademliaStore` proto to publish for [channelId] at
  /// [nowMs]: our own fresh entry (`entry_ts = nowMs`) merged with the
  /// newest-known peer entries, encrypted and signed with the channel record
  /// key. Returns null if the channel is unknown or we have no own OH yet.
  Future<Uint8List?> buildSignedStore(String channelId, int nowMs) async {
    final state = _states[channelId];
    if (state == null || state.ownOhs.isEmpty) return null;

    final ownId = ChannelRendezvous.participantId(
      state.channelSecret,
      isCreator: state.isCreator,
    );
    final ownEntry = RendezvousEntry(
      participantId: ownId,
      name: state.ownName,
      entryTs: nowMs,
      ohs: state.ownOhs,
    );
    // Merge our fresh entry over everything we know so the published record
    // carries the whole participant set (newest-wins per participant).
    final merged = ChannelRendezvous.mergeEntries(state.knownEntries.values, [
      ownEntry,
    ]);
    state.absorb(merged);

    final signed = await ChannelRendezvous.buildSignedRecord(
      state.channelSecret,
      merged,
      nowMs,
    );
    return KademliaStore(
      timestamp: Int64(signed.timestampMs),
      publicKey: signed.publicKey,
      content: signed.content,
      signature: signed.signature,
    ).writeToBuffer();
  }

  /// Reconstructs a [SignedRendezvousRecord] from a `record_lookup` answer's
  /// `KademliaStore` proto bytes.
  static SignedRendezvousRecord recordFromStoreBytes(List<int> storeBytes) {
    final store = KademliaStore.fromBuffer(storeBytes);
    return SignedRendezvousRecord(
      timestampMs: store.timestamp.toInt(),
      publicKey: store.publicKey,
      content: store.content,
      signature: store.signature,
    );
  }

  /// Applies a resolved record to [channelId]: verifies the self-certifying
  /// signature and TTL, decrypts, merges the entries per participant
  /// (newest-wins) and returns the peer's current OH list if it advanced —
  /// i.e. the fresh peer mailbox set to adopt on recovery. Returns null when
  /// the record is invalid/stale, undecryptable, or carries nothing newer for
  /// the peer.
  Future<List<OHDescriptor>?> applyResolvedRecord(
    String channelId,
    SignedRendezvousRecord record,
    int nowMs,
  ) async {
    final state = _states[channelId];
    if (state == null) return null;
    if (!await ChannelRendezvous.verifyRecord(record)) return null;
    if (nowMs - record.timestampMs > ChannelRendezvous.maxRecordAgeMs) {
      return null; // stale (TTL)
    }
    final List<RendezvousEntry> entries;
    try {
      entries = await ChannelRendezvous.decryptRecordContent(
        state.channelSecret,
        record.content,
      );
    } catch (_) {
      return null; // wrong key / tampered / malformed
    }

    final peerId = ChannelRendezvous.participantId(
      state.channelSecret,
      isCreator: !state.isCreator,
    );
    final peerIdHex = _hex(peerId);
    final before = state.knownEntries[peerIdHex];
    state.absorb(
      ChannelRendezvous.mergeEntries(state.knownEntries.values, entries),
    );
    final after = state.knownEntries[peerIdHex];
    if (after == null) return null;
    if (before != null && after.entryTs <= before.entryTs) {
      return null; // nothing newer for the peer
    }
    return after.ohs;
  }

  static bool _sameOhList(List<OHDescriptor> a, List<OHDescriptor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

class _ChannelRendezvousState {
  final Uint8List channelSecret;
  final bool isCreator;
  String ownName;
  List<OHDescriptor> ownOhs = const [];

  /// Newest-known entry per participant id (hex), the client-side merge state.
  final Map<String, RendezvousEntry> knownEntries = {};

  _ChannelRendezvousState({
    required this.channelSecret,
    required this.isCreator,
    required this.ownName,
  });

  void absorb(List<RendezvousEntry> merged) {
    for (final e in merged) {
      knownEntries[RendezvousManager._hex(e.participantId)] = e;
    }
  }
}
