import 'dart:async';

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
  }

  Future<void> stop() async {
    await _messageSub?.cancel();
    await _updateSub?.cancel();
    _messageSub = null;
    _updateSub = null;
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

  /// Restores channel keys and persisted OH registrations into the network
  /// client so polling resumes from the persisted cursor after a restart.
  Future<void> restorePersistedState() async {
    final channels = await _db.select(_db.channels).get();
    for (final channel in channels) {
      _client.addChannelKeys(
        channel.uuid,
        HEX.decode(channel.encryptionKey),
        peerOhId: channel.peerOhId != null
            ? HEX.decode(channel.peerOhId!)
            : null,
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
