import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda/database/counterpart_oh.dart';
import 'package:redpanda/database/database.dart' as db;
import 'package:drift/drift.dart' as drift;
import 'package:hex/hex.dart';
import 'package:redpanda/shared/providers.dart';

abstract class ChannelRepository {
  /// Persists [channel], returning `true` when it was newly added and `false`
  /// when a row for [Channel.id] already existed.
  ///
  /// Re-adding an existing channel is **non-destructive**: all on-device state
  /// the [Channel] value object does not carry — the ratchet state, the pending
  /// reverse-garlic block, the known counterpart mailbox set and the creator role
  /// marker — is preserved. Callers should treat `false` as "already joined"
  /// rather than as a fresh join.
  Future<bool> addChannel(Channel channel);
  Future<List<Channel>> getChannels();
  Stream<List<Channel>> watchChannels();
}

class DriftChannelRepository implements ChannelRepository {
  final db.AppDatabase _db;

  DriftChannelRepository(this._db);

  @override
  Future<bool> addChannel(Channel channel) async {
    // H8: the channel id is deterministic from `channel_sk`, so re-scanning a
    // QR code for an already-joined channel hits an existing row. This used to
    // be an `INSERT OR REPLACE`, which in SQLite *deletes* the old row — every
    // column the companion does not set (ratchetState, pendingRgb, counterpartOhSet)
    // came back NULL and the two ratchets silently diverged. Existing rows are
    // therefore updated in place, and only with the columns the QR actually
    // carries.
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.channels,
      )..where((t) => t.conversationId.equals(channel.id))).getSingleOrNull();

      if (existing != null) {
        // The counterpart descriptor is only ever added, never cleared: a
        // re-scan carries no OH data and must not drop what the rendezvous
        // lookup already found. When it does carry one, it becomes the
        // primary and the already known mailboxes stay behind it, so the
        // "first entry mirrors the primary" invariant holds (TD118).
        // `authPrivateKey` is deliberately absent — a creator re-scanning
        // their own QR is a joiner as far as `Channel.fromJson` is concerned,
        // and losing the role marker would break the ratchet asymmetry.
        final descriptor = channel.counterpartOhDescriptor;
        final ohColumns = counterpartOhColumns(
          descriptor == null
              ? const <OHDescriptor>[]
              : promoteToPrimary(
                  descriptor,
                  decodeCounterpartOhSet(existing.counterpartOhSet),
                ),
        );
        await (_db.update(_db.channels)
              ..where((t) => t.conversationId.equals(channel.id)))
            .write(ohColumns.copyWith(label: drift.Value(channel.label)));
        return false;
      }

      final newDescriptor = channel.counterpartOhDescriptor;
      final newOhColumns = counterpartOhColumns(
        newDescriptor == null ? const <OHDescriptor>[] : [newDescriptor],
      );
      await _db
          .into(_db.channels)
          .insert(
            db.ChannelsCompanion.insert(
              conversationId: channel.id,
              label: channel.label,
              encryptionKey: HEX.encode(channel.encryptionKey),
              channelSecret: drift.Value(HEX.encode(channel.channelSecret)),
              authPrivateKey: drift.Value(
                channel.authPrivateKey != null
                    ? HEX.encode(channel.authPrivateKey!)
                    : null,
              ),
              authPublicKey: HEX.encode(channel.authPublicKey),
              // All four counterpart mailbox columns come from one place so
              // the primary stays the head of the set (TD118).
              counterpartOhEndpoint: newOhColumns.counterpartOhEndpoint,
              counterpartOhId: newOhColumns.counterpartOhId,
              counterpartOhPublicKey: newOhColumns.counterpartOhPublicKey,
              counterpartOhSet: newOhColumns.counterpartOhSet,
              lastSeen: drift.Value(DateTime.now()),
            ),
          );
      return true;
    });
  }

  @override
  Future<List<Channel>> getChannels() async {
    final channelDataList = await _db.select(_db.channels).get();
    return channelDataList.map(_mapToDomain).toList();
  }

  @override
  Stream<List<Channel>> watchChannels() {
    return _db.select(_db.channels).watch().map((rows) {
      return rows.map(_mapToDomain).toList();
    });
  }

  Channel _mapToDomain(db.ChannelRow data) {
    OHDescriptor? ohDescriptor;
    if (data.counterpartOhEndpoint != null &&
        data.counterpartOhId != null &&
        data.counterpartOhPublicKey != null) {
      ohDescriptor = OHDescriptor(
        serverEndpoint: data.counterpartOhEndpoint!,
        handleId: HEX.decode(data.counterpartOhId!),
        authPublicKey: HEX.decode(data.counterpartOhPublicKey!),
      );
    }

    return Channel(
      label: data.label,
      // v4 channels always persist the secret; the `??` only guards the
      // impossible legacy-row case (v3 rows are wiped by the v17 migration).
      channelSecret: data.channelSecret != null
          ? HEX.decode(data.channelSecret!)
          : const <int>[],
      encryptionKey: HEX.decode(data.encryptionKey),
      authPrivateKey: data.authPrivateKey != null
          ? HEX.decode(data.authPrivateKey!)
          : null,
      authPublicKey: HEX.decode(data.authPublicKey),
      counterpartOhDescriptor: ohDescriptor,
    );
  }
}

final channelRepositoryProvider = Provider<ChannelRepository>((ref) {
  final db = ref.watch(dbProvider);
  return DriftChannelRepository(db);
});

final channelsProvider = StreamProvider<List<Channel>>((ref) {
  final repo = ref.watch(channelRepositoryProvider);
  return repo.watchChannels();
});
