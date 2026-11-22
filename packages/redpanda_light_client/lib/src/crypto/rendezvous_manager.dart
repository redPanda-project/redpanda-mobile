import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';

/// T44 client-side rendezvous state and record builder — the pure business
/// logic behind publish/refresh and recovery, decoupled from the garlic
/// transport so it can be unit-tested in isolation.
///
/// For each channel it keeps the channel secret, the local role and the
/// newest-known entry per participant (the merge state). It builds the signed
/// record to publish (own fresh entry merged with the known counterpart
/// entries, so the newest surviving KadContent carries everyone) and, on a
/// resolved record,
/// merges it in and surfaces the counterpart's current OH list.
class RendezvousManager {
  final Map<String, _ChannelRendezvousState> _states = {};

  /// How far ahead of the own clock a record timestamp may be pushed to stay
  /// monotonic (T160/P5): the node's limit (`ChannelDht.MAX_FUTURE_SKEW_MS`,
  /// 15 min) minus one minute for the node's own clock error.
  static const int maxFutureLeadMs = 14 * 60 * 1000;

  /// Registers (or refreshes) a channel's rendezvous state. Idempotent — keeps
  /// the accumulated merge state across re-registrations.
  ///
  /// T111: [ownName] is nullable so a re-registration that does NOT know the
  /// display name (a partial re-register from a caller holding only the
  /// channel row) cannot blank the name already being published in the DHT
  /// record. A null name means "unchanged"; an empty string is a real,
  /// explicit "no name".
  void register(
    String channelId, {
    required List<int> channelSecret,
    required bool isCreator,
    required String? ownName,
  }) {
    final existing = _states[channelId];
    if (existing != null) {
      if (ownName != null) existing.ownName = ownName;
      return;
    }
    _states[channelId] = _ChannelRendezvousState(
      channelSecret: Uint8List.fromList(channelSecret),
      isCreator: isCreator,
      ownName: ownName ?? '',
    );
  }

  void remove(String channelId) => _states.remove(channelId);

  bool knows(String channelId) => _states.containsKey(channelId);

  /// All channel ids with rendezvous state (used by the daily republish).
  Iterable<String> get channels => _states.keys;

  /// The display name currently advertised for [channelId] in the rendezvous
  /// record (read-only view, for tests and diagnostics).
  String? ownNameOf(String channelId) => _states[channelId]?.ownName;

  List<int>? channelSecretOf(String channelId) =>
      _states[channelId]?.channelSecret;

  /// Whether the local side created [channelId] (null for an unknown
  /// channel).
  bool? isCreatorOf(String channelId) => _states[channelId]?.isCreator;

  /// Whether the merge state of [channelId] holds an entry of the
  /// counterpart role — i.e. a resolved record (or a restored snapshot) has
  /// told us about the other side. T160: a side without one must READ the
  /// record before it writes, or its publish erases what it never saw.
  bool knowsCounterpartEntry(String channelId) {
    final state = _states[channelId];
    if (state == null) return false;
    final counterpartId = ChannelRendezvous.participantId(
      state.channelSecret,
      isCreator: !state.isCreator,
    );
    return state.knownEntries.containsKey(_hex(counterpartId));
  }

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
  /// newest-known counterpart entries, encrypted and signed with the channel record
  /// key. Returns null if the channel is unknown or we have no own OH yet.
  ///
  /// T160/P5: the record timestamp is MONOTONIC over every record this side
  /// has seen or built — `max(nowMs, newest seen + 1)` — because the node
  /// replaces a record only by a strictly newer one (`KadStoreManager.put`).
  /// A writer whose clock runs behind the other participant's would
  /// otherwise never get a record accepted, and its read-repair would be
  /// rejected on every attempt. Capped at [maxFutureLeadMs] ahead of the own
  /// clock: the node rejects records more than 15 min in its future
  /// (`ChannelDht.MAX_FUTURE_SKEW_MS`), so past the cap the write would be
  /// lost anyway. The own entry's `entry_ts` is monotonic the same way (it
  /// orders our entries at the other participants' merge).
  Future<Uint8List?> buildSignedStore(String channelId, int nowMs) async {
    final state = _states[channelId];
    if (state == null || state.ownOhs.isEmpty) return null;

    final ownId = ChannelRendezvous.participantId(
      state.channelSecret,
      isCreator: state.isCreator,
    );
    final ownIdHex = _hex(ownId);
    final previousOwnTs = state.knownEntries[ownIdHex]?.entryTs;
    final cap = nowMs + maxFutureLeadMs;
    final entryTs = previousOwnTs != null && previousOwnTs >= nowMs
        ? (previousOwnTs + 1 > cap ? cap : previousOwnTs + 1)
        : nowMs;
    final seen = state.newestSeenRecordTs;
    final recordTs = seen != null && seen >= nowMs
        ? (seen + 1 > cap ? cap : seen + 1)
        : nowMs;
    final ownEntry = RendezvousEntry(
      participantId: ownId,
      name: state.ownName,
      entryTs: entryTs,
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
      recordTs,
    );
    state.lastBuiltRecordTs = signed.timestampMs;
    state.noteSeenRecordTs(signed.timestampMs);
    state.lastBuiltEntryTs = {
      for (final e in merged) _hex(e.participantId): e.entryTs,
    };
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
  /// (newest-wins) and returns the counterpart's current OH list if it advanced —
  /// i.e. the fresh counterpart mailbox set to adopt on recovery. Returns null when
  /// the record is invalid/stale, undecryptable, or carries nothing newer for
  /// the counterpart.
  Future<List<OHDescriptor>?> applyResolvedRecord(
    String channelId,
    SignedRendezvousRecord record,
    int nowMs,
  ) async => (await applyResolvedRecordDetailed(
    channelId,
    record,
    nowMs,
  ))?.counterpartOhs;

  /// [applyResolvedRecord] plus the read-repair verdict (T160): whether the
  /// record is NEWER than the last one we built ourselves, carries another
  /// participant's entry, and lacks our own current entry (missing, or with
  /// an OH list that is not our current one). Such a record was written by
  /// someone who had not seen our entry — the node keeps only the newest
  /// record, so our entry is gone from the DHT until we write the merged
  /// record back. Returns null when the record is invalid (signature, TTL,
  /// key pin, decryption) — then nothing was merged and nothing is repaired.
  Future<ResolvedRecord?> applyResolvedRecordDetailed(
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
    // Pin the record key: only the keypair derived from THIS channel's secret
    // may sign our rendezvous record. verifyRecord is self-certifying (checks
    // against the record's own embedded key), so without the pin a node could
    // re-sign a captured legitimate ciphertext under a throwaway key with a
    // rolled-forward timestamp and defeat the newest-wins ordering. Runs after
    // the cheaper signature/TTL checks so junk answers fail before the key
    // derivation this pin needs.
    final expectedPub = await ChannelRendezvous.recordPublicExport(
      state.channelSecret,
    );
    if (!CryptoUtils.constantTimeEquals(record.publicKey, expectedPub)) {
      return null;
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

    final ownIdHex = _hex(
      ChannelRendezvous.participantId(
        state.channelSecret,
        isCreator: state.isCreator,
      ),
    );
    final ownInRecord = entries
        .where((e) => _hex(e.participantId) == ownIdHex)
        .firstOrNull;
    final hasForeignEntry = entries.any(
      (e) => _hex(e.participantId) != ownIdHex,
    );
    final lastBuilt = state.lastBuiltRecordTs;
    // (A) Someone wrote a newer record without our current entry.
    final overwritten =
        state.ownOhs.isNotEmpty &&
        hasForeignEntry &&
        (lastBuilt == null || record.timestampMs > lastBuilt) &&
        (ownInRecord == null || !_sameOhList(ownInRecord.ohs, state.ownOhs));
    state.noteSeenRecordTs(record.timestampMs);

    final counterpartId = ChannelRendezvous.participantId(
      state.channelSecret,
      isCreator: !state.isCreator,
    );
    final counterpartIdHex = _hex(counterpartId);
    final before = state.knownEntries[counterpartIdHex];
    state.absorb(
      ChannelRendezvous.mergeEntries(state.knownEntries.values, entries),
    );
    final after = state.knownEntries[counterpartIdHex];
    final advanced =
        after != null && (before == null || after.entryTs > before.entryTs);
    // (B) T160/P3: a record NOT newer than our own last write taught us an
    // entry of another participant that this write did not carry (or carried
    // older) — typically a late answer with the creator's older record after
    // our hold had timed out and we had published only ourselves. The node
    // most likely still holds our write, which lacks that entry, and (A)
    // cannot see it because the answer is older. Republish the merged
    // record. A NEWER record that carries our current entry needs nothing
    // (the node holds everything already) — firing there would make every
    // read a write, and two reading sides could keep re-stamping each other.
    // Only once we have written at all: a side that has never published
    // writes the merged record anyway.
    final builtEntries = state.lastBuiltEntryTs;
    final learnedUnwritten =
        lastBuilt != null &&
        record.timestampMs <= lastBuilt &&
        state.ownOhs.isNotEmpty &&
        state.knownEntries.entries.any((e) {
          if (e.key == ownIdHex) return false;
          final written = builtEntries[e.key];
          return written == null || e.value.entryTs > written;
        });
    final needsRepair = overwritten || learnedUnwritten;
    return ResolvedRecord(
      counterpartOhs: advanced ? after.ohs : null,
      needsRepair: needsRepair,
    );
  }

  /// Serializes the merge state of [channelId] — the newest-known entry per
  /// participant — so the main isolate can replay it into a respawned worker
  /// (TD117). Returns null for an unknown channel or an empty merge state
  /// (nothing worth restoring).
  ///
  /// On-device only: the entries are the already-decrypted contents of our own
  /// rendezvous record, no channel secret and no key material is included.
  String? exportMergeState(String channelId) {
    final state = _states[channelId];
    if (state == null || state.knownEntries.isEmpty) return null;
    final entries = state.knownEntries.values.toList()
      ..sort((a, b) => _hex(a.participantId).compareTo(_hex(b.participantId)));
    return jsonEncode([
      for (final e in entries)
        {
          'pid': _hex(e.participantId),
          'name': e.name,
          'ts': e.entryTs,
          'ohs': [for (final oh in e.ohs) oh.toJsonMap()],
        },
    ]);
  }

  /// Feeds an [exportMergeState] snapshot back into [channelId] after a worker
  /// respawn. Merged with the same newest-wins rule the DHT path uses, so a
  /// restore can only ever ADD knowledge: anything the fresh worker already
  /// learned (a newer record resolved before the restore arrived) wins.
  ///
  /// A malformed snapshot is discarded WHOLE (never half-applied): the restore
  /// is a best-effort optimization, and a worker that cannot parse it is
  /// exactly as well off as before this method existed. An unknown channel is
  /// ignored too — the channel registration comes first in the replay order.
  void restoreMergeState(String channelId, String mergeStateJson) {
    final state = _states[channelId];
    if (state == null) return;
    final List<RendezvousEntry> restored = [];
    try {
      final decoded = jsonDecode(mergeStateJson) as List<dynamic>;
      for (final raw in decoded) {
        final map = raw as Map<String, dynamic>;
        restored.add(
          RendezvousEntry(
            participantId: _unhex(map['pid'] as String),
            name: map['name'] as String,
            entryTs: map['ts'] as int,
            ohs: [
              for (final oh in map['ohs'] as List<dynamic>)
                OHDescriptor.fromJsonMap(oh as Map<String, dynamic>),
            ],
          ),
        );
      }
    } catch (_) {
      return; // malformed snapshot — keep the live state untouched
    }
    if (restored.isEmpty) return;
    state.absorb(
      ChannelRendezvous.mergeEntries(state.knownEntries.values, restored),
    );
  }

  static bool _sameOhList(List<OHDescriptor> a, List<OHDescriptor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Uint8List _unhex(String hex) {
    if (hex.length.isOdd) throw FormatException('odd-length hex', hex);
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// The outcome of applying a resolved rendezvous record
/// ([RendezvousManager.applyResolvedRecordDetailed]).
class ResolvedRecord {
  /// The counterpart's OH list if the record advanced it, else null.
  final List<OHDescriptor>? counterpartOhs;

  /// Whether the record overwrote our own current entry (T160 read-repair):
  /// publish the merged record again.
  final bool needsRepair;

  const ResolvedRecord({
    required this.counterpartOhs,
    required this.needsRepair,
  });
}

class _ChannelRendezvousState {
  final Uint8List channelSecret;
  final bool isCreator;
  String ownName;
  List<OHDescriptor> ownOhs = const [];

  /// Timestamp of the last record this side built for publishing (null:
  /// never, or not since a worker respawn). A resolved record that is not
  /// newer than this one predates our own write and is no reason to repair.
  int? lastBuiltRecordTs;

  /// Participant id (hex) → `entry_ts` of every entry in the last record
  /// this side built (T160/P3: what our write in the DHT carries).
  Map<String, int> lastBuiltEntryTs = const {};

  /// The newest record timestamp seen (resolved) or built (T160/P5: the
  /// floor for the next record timestamp).
  int? newestSeenRecordTs;

  void noteSeenRecordTs(int ts) {
    final seen = newestSeenRecordTs;
    if (seen == null || ts > seen) newestSeenRecordTs = ts;
  }

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
