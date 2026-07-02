import 'dart:async';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Bridges the network client and the local database:
///
/// - persists fetched messages (deduplicated by network message id),
/// - persists OH fetch cursors and renewed expiries,
/// - re-broadcasts mailbox overflow warnings for the UI,
/// - restores persisted OH registrations and channel keys on startup.
class MessageSyncService {
  final RedPandaClient _client;
  final MessageRepository _messages;
  final OutboundHandleRepository _outboundHandles;
  final AppDatabase _db;

  final _overflowController = StreamController<OhMailboxUpdate>.broadcast();
  StreamSubscription<DecryptedMessage>? _messageSub;
  StreamSubscription<OhMailboxUpdate>? _updateSub;
  StreamSubscription<RatchetStateUpdate>? _ratchetSub;
  StreamSubscription<GarlicSessionUpdate>? _garlicSub;

  /// Serializes ratchet-state DB writes so they are applied in emission
  /// order — a slow earlier write must not overwrite a newer state.
  Future<void> _ratchetPersistPending = Future.value();

  /// Same ordering guarantee for garlic-session snapshots (MS05).
  Future<void> _garlicPersistPending = Future.value();

  MessageSyncService(
    this._client,
    this._messages,
    this._outboundHandles,
    this._db,
  );

  /// Mailbox overflow warnings; the chat UI surfaces these to the user.
  Stream<OhMailboxUpdate> get overflowEvents => _overflowController.stream;

  void start() {
    // Guard the async handlers: a persistence failure for one event must
    // not become an unhandled zone error or kill the subscription.
    _messageSub ??= _client.incomingMessages.listen(
      (msg) => unawaited(
        handleIncomingMessage(msg).catchError(
          (Object e) => debugPrint(
            'MessageSyncService: failed to persist incoming message: $e',
          ),
        ),
      ),
    );
    _updateSub ??= _client.ohMailboxUpdates.listen(
      (update) => unawaited(
        handleMailboxUpdate(update).catchError(
          (Object e) => debugPrint(
            'MessageSyncService: failed to persist mailbox update: $e',
          ),
        ),
      ),
    );
    _ratchetSub ??= _client.ratchetStateUpdates.listen((update) {
      _ratchetPersistPending = _ratchetPersistPending
          .then((_) => handleRatchetStateUpdate(update))
          .catchError(
            (Object e) => debugPrint(
              'MessageSyncService: failed to persist ratchet state: $e',
            ),
          );
    });
    _garlicSub ??= _client.garlicSessionUpdates.listen((update) {
      _garlicPersistPending = _garlicPersistPending
          .then((_) => handleGarlicSessionUpdate(update))
          .catchError(
            (Object e) => debugPrint(
              'MessageSyncService: failed to persist garlic session: $e',
            ),
          );
    });
  }

  Future<void> stop() async {
    await _messageSub?.cancel();
    await _updateSub?.cancel();
    await _ratchetSub?.cancel();
    await _garlicSub?.cancel();
    _messageSub = null;
    _updateSub = null;
    _ratchetSub = null;
    _garlicSub = null;
  }

  /// Persists a fetched message unless it was already stored (dedup via
  /// network-level message id — covers re-deliveries after failed AckFetch).
  Future<void> handleIncomingMessage(DecryptedMessage msg) async {
    final channelId = msg.channelId;
    if (channelId == null) {
      // Without a channel association the message cannot be shown anywhere.
      return;
    }
    await _messages.insertIncomingIfNew(
      messageId: msg.id,
      conversationId: channelId,
      senderId: channelId,
      content: msg.content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.receivedAtMs),
    );
  }

  /// Persists cursor/expiry after fetches and renewals; forwards overflow.
  Future<void> handleMailboxUpdate(OhMailboxUpdate update) async {
    final ohIdHex = HEX.encode(update.ohId);
    await _outboundHandles.updateCursor(ohIdHex, update.lastCursor);
    await _outboundHandles.updateExpiry(
      ohIdHex,
      DateTime.fromMillisecondsSinceEpoch(update.expiresAtMs),
    );
    if (update.mailboxOverflow && !_overflowController.isClosed) {
      _overflowController.add(update);
    }
  }

  /// Persists advanced ratchet state (MS03b) so the channel ratchet
  /// survives app restarts. On-device only — `ratchetState` never travels
  /// in the QR code or any off-device backup.
  Future<void> handleRatchetStateUpdate(RatchetStateUpdate update) async {
    await (_db.update(_db.channels)
          ..where((c) => c.uuid.equals(update.channelId)))
        .write(ChannelsCompanion(ratchetState: Value(update.stateJson)));
  }

  /// Persists a reverse-garlic session snapshot (MS05): replaces the
  /// channel's outstanding session tags and pending RGB. On-device only —
  /// like the ratchet state, this never leaves the device.
  Future<void> handleGarlicSessionUpdate(GarlicSessionUpdate update) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.sessionTags,
      )..where((t) => t.channelId.equals(update.channelId))).go();
      for (final entry in update.sessionTags.entries) {
        await _db
            .into(_db.sessionTags)
            .insert(
              SessionTagsCompanion.insert(
                tag: entry.key,
                channelId: update.channelId,
                createdAt: DateTime.fromMillisecondsSinceEpoch(entry.value),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      await (_db.update(_db.channels)
            ..where((c) => c.uuid.equals(update.channelId)))
          .write(ChannelsCompanion(pendingRgb: Value(update.pendingRgbHex)));
    });
  }

  /// Restores channel keys and persisted OH registrations into the network
  /// client so polling resumes from the persisted cursor after a restart.
  Future<void> restorePersistedState() async {
    final channels = await _db.select(_db.channels).get();
    final allTags = await _db.select(_db.sessionTags).get();
    for (final channel in channels) {
      final sessionTags = {
        for (final tag in allTags)
          if (tag.channelId == channel.uuid)
            tag.tag: tag.createdAt.millisecondsSinceEpoch,
      };
      _client.addChannelKeys(
        channel.uuid,
        HEX.decode(channel.encryptionKey),
        peerOhId: channel.peerOhId != null
            ? HEX.decode(channel.peerOhId!)
            : null,
        // The creator is the device holding the channel auth private key;
        // a device that joined via QR code holds only the public key.
        isChannelCreator: channel.authPrivateKey != null,
        ratchetState: channel.ratchetState,
        sessionTags: sessionTags.isEmpty ? null : sessionTags,
        pendingRgbHex: channel.pendingRgb,
      );
    }

    final handles = await _outboundHandles.getAllValid();
    for (final handle in handles) {
      await _client.restoreOutboundHandle(
        await _outboundHandles.toRegistration(handle),
      );
    }
  }

  Future<void> dispose() async {
    await stop();
    await _overflowController.close();
  }
}

final messageSyncServiceProvider = Provider<MessageSyncService>((ref) {
  return MessageSyncService(
    ref.watch(redPandaClientProvider),
    ref.watch(messageRepositoryProvider),
    ref.watch(outboundHandleRepositoryProvider),
    ref.watch(dbProvider),
  );
});

/// Mailbox overflow warnings for the UI.
final mailboxOverflowProvider = StreamProvider<OhMailboxUpdate>((ref) {
  return ref.watch(messageSyncServiceProvider).overflowEvents;
});
