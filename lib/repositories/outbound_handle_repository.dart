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

  Future<db.OutboundHandle?> getByChannelId(String channelId) {
    return (_db.select(
      _db.outboundHandles,
    )..where((t) => t.channelId.equals(channelId))).getSingleOrNull();
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
      final keypair = OHKeypair.fromPrivateKeyBytes(
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
