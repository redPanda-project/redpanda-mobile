import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda/database/database.dart' as db;
import 'package:redpanda/shared/providers.dart';

/// Persists our own Outbound Handle registrations (one per channel) and
/// provides the descriptor that gets embedded into the channel QR code so
/// peers know where to deposit messages for us.
class OutboundHandleRepository {
  final db.AppDatabase _db;

  OutboundHandleRepository(this._db);

  /// The newest still-valid own OH for [channelId] (T42: a channel can hold
  /// more than one own mailbox now, so this returns the freshest non-expired
  /// row instead of asserting a single row).
  Future<db.OutboundHandle?> getByChannelId(String channelId) {
    return (_db.select(_db.outboundHandles)
          ..where(
            (t) =>
                t.channelId.equals(channelId) &
                t.expiresAt.isBiggerThanValue(DateTime.now()),
          )
          ..orderBy([(t) => drift.OrderingTerm.desc(t.expiresAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// All persisted own OHs for [channelId] (T42 multi-OH).
  Future<List<db.OutboundHandle>> getAllByChannelId(String channelId) {
    return (_db.select(
      _db.outboundHandles,
    )..where((t) => t.channelId.equals(channelId))).get();
  }

  /// All persisted OHs that have not expired yet.
  Future<List<db.OutboundHandle>> getAllValid() {
    return (_db.select(
      _db.outboundHandles,
    )..where((t) => t.expiresAt.isBiggerThanValue(DateTime.now()))).get();
  }

  /// Persists the latest acknowledged fetch cursor for [ohIdHex].
  Future<void> updateCursor(String ohIdHex, int lastCursor) async {
    await (_db.update(
      _db.outboundHandles,
    )..where((t) => t.ohId.equals(ohIdHex))).write(
      db.OutboundHandlesCompanion(lastCursor: drift.Value(lastCursor)),
    );
  }

  /// Persists the new expiry after a successful OH renewal.
  Future<void> updateExpiry(String ohIdHex, DateTime expiresAt) async {
    await (_db.update(_db.outboundHandles)
          ..where((t) => t.ohId.equals(ohIdHex)))
        .write(db.OutboundHandlesCompanion(expiresAt: drift.Value(expiresAt)));
  }

  /// Maps a persisted row back to an [OHRegistration] for restoring into
  /// the network client after an app restart.
  Future<OHRegistration> toRegistration(db.OutboundHandle row) async {
    return OHRegistration(
      ohId: HEX.decode(row.ohId),
      keypair: await OHKeypair.fromPrivateKeyBytes(
        Uint8List.fromList(row.keypairBytes),
      ),
      expiresAtMs: row.expiresAt.millisecondsSinceEpoch,
      channelId: row.channelId,
      serverEndpoint: row.serverEndpoint,
      lastCursor: row.lastCursor,
    );
  }

  Future<void> save(OHRegistration registration) async {
    await _db
        .into(_db.outboundHandles)
        .insert(
          db.OutboundHandlesCompanion.insert(
            ohId: HEX.encode(registration.ohId),
            keypairBytes: registration.keypair.privateKeyBytes,
            serverEndpoint: registration.serverEndpoint!,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              registration.expiresAtMs,
            ),
            channelId: drift.Value(registration.channelId),
          ),
        );
  }

  /// Syncs the channel's persisted own-OH rows to exactly [registrations]
  /// (T42 multi-OH): dead mailboxes after a failover are dropped, redundancy
  /// top-ups are added. A row that already existed (same OH id) keeps its
  /// original [OutboundHandles.failedOverAt] marker; brand-new rows are NOT
  /// stamped as failed-over — a redundancy top-up or the very first mailbox is
  /// a normal registration, not a failover, so the channel status page must
  /// not mislabel it.
  Future<void> replaceAllForChannel(
    String channelId,
    List<OHRegistration> registrations,
  ) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.outboundHandles,
      )..where((t) => t.channelId.equals(channelId))).get();
      final failedOverByOhId = {
        for (final row in existing)
          if (row.failedOverAt != null) row.ohId: row.failedOverAt!,
      };
      await (_db.delete(
        _db.outboundHandles,
      )..where((t) => t.channelId.equals(channelId))).go();
      for (final registration in registrations) {
        if (registration.serverEndpoint == null) continue;
        final ohIdHex = HEX.encode(registration.ohId);
        await _db
            .into(_db.outboundHandles)
            .insert(
              db.OutboundHandlesCompanion.insert(
                ohId: ohIdHex,
                keypairBytes: registration.keypair.privateKeyBytes,
                serverEndpoint: registration.serverEndpoint!,
                expiresAt: DateTime.fromMillisecondsSinceEpoch(
                  registration.expiresAtMs,
                ),
                channelId: drift.Value(channelId),
                lastCursor: drift.Value(registration.lastCursor),
                failedOverAt: drift.Value(failedOverByOhId[ohIdHex]),
              ),
            );
      }
    });
  }

  /// Returns our own OH descriptor for [channelId], registering a new OH via
  /// [client] if no valid one is persisted yet.
  ///
  /// Returns null when registration is currently not possible (e.g. no
  /// connected Full Node) — callers should then fall back to a v1 QR code
  /// without an `oh` field.
  Future<OHDescriptor?> ensureOwnDescriptor(
    RedPandaClient client,
    String channelId,
  ) async {
    final existing = await getByChannelId(channelId);
    if (existing != null && existing.expiresAt.isAfter(DateTime.now())) {
      final keypair = await OHKeypair.fromPrivateKeyBytes(
        Uint8List.fromList(existing.keypairBytes),
      );
      return OHDescriptor(
        serverEndpoint: existing.serverEndpoint,
        handleId: HEX.decode(existing.ohId),
        authPublicKey: keypair.publicKeyBytes,
      );
    }

    try {
      final registration = await client.registerOutboundHandle(
        channelId: channelId,
      );
      // Without a server endpoint the registration never reached a Full Node;
      // don't persist it and let the caller fall back to a v1 QR code.
      if (registration.serverEndpoint == null) return null;

      await save(registration);
      return OHDescriptor(
        serverEndpoint: registration.serverEndpoint!,
        handleId: registration.ohId,
        authPublicKey: registration.keypair.publicKeyBytes,
      );
    } catch (_) {
      return null;
    }
  }
}

final outboundHandleRepositoryProvider = Provider<OutboundHandleRepository>((
  ref,
) {
  final database = ref.watch(dbProvider);
  return OutboundHandleRepository(database);
});
