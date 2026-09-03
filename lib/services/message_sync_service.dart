import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda/shared/providers.dart';
// `hide Channel`: the light client's domain `Channel` collides with the Drift
// row class of the same name, and this file only ever handles the row.
import 'package:redpanda_light_client/redpanda_light_client.dart' hide Channel;

/// The app's persistence channel: it owns the ONE subscription to the network
/// client's [RedPandaClient.stateUpdates] and writes every state change to the
/// local database, plus the incoming-message stream and the startup restore.
///
/// - persists fetched messages (deduplicated by network message id),
/// - persists OH fetch cursors and renewed expiries,
/// - persists ratchet/garlic session state, own- and counterpart-OH sets, node
///   scores and group state, and routes routing-/channel-ACKs into the
///   outbox (T112: the delivery lifecycle is owned by [OutboxService], this
///   service only owns the subscription that carries the acks),
/// - re-broadcasts mailbox overflow warnings for the UI,
/// - restores persisted OH registrations and channel keys on startup.
///
/// T111: it also owns the ONE restore entry point into the network worker
/// ([restorePersistedState] for startup, [registerChannel] for a channel
/// created or joined afterwards — both via [_registerChannel]). Nothing else
/// in the app hands channel state to the worker; the chat screen used to do
/// it from `build()` with a subset of the arguments.
///
/// T110: a new state event is handled by adding one `case` to [_persist] —
/// there is no protocol class, isolate-client branch or facade stream to
/// extend. State this service does NOT own stays out of [_persist]
/// (fetch status → `channel_health`, group handshakes → `GroupService`).
class MessageSyncService {
  final RedPandaClient _client;
  final MessageRepository _messages;
  final OutboundHandleRepository _outboundHandles;
  final AppDatabase _db;
  final GroupRepository _groups;
  final OutboxService _outbox;

  final _overflowController = StreamController<OhMailboxUpdate>.broadcast();
  StreamSubscription<DecryptedMessage>? _messageSub;
  StreamSubscription<StateUpdate>? _stateSub;
  StreamSubscription<List<String>>? _channelIdsSub;

  /// Channel ids already handed to the network worker in this app run (T111).
  /// Guards the watcher below so a channel is restored once, not on every
  /// write to the `Channels` table (the ratchet state is written per message).
  final Set<String> _registeredChannelIds = {};

  /// The ONE persistence chain (T110): every state update is written in
  /// emission order. Replaces the four per-kind future chains (ratchet,
  /// garlic, node scores, group state) and the fire-and-forget writes for
  /// mailbox/own-OH/counterpart-OH/ACK updates — a slow earlier write can no longer
  /// be overtaken by a newer one, within a kind or across kinds.
  ///
  /// Deliberate trade-off: this also serializes writes that used to run
  /// concurrently (an ACK for channel A now queues behind a garlic snapshot
  /// for channel B). That costs little in practice — all handlers share ONE
  /// Drift connection, and the garlic/node-score handlers already held it
  /// exclusively inside a transaction — and it buys the ordering guarantee
  /// that the four separate chains could not give across kinds. If a slow
  /// write ever does hold up unrelated UI state, split this per aggregate
  /// (channel id), not back into per-kind chains.
  Future<void> _persistPending = Future.value();

  MessageSyncService(
    this._client,
    this._messages,
    this._outboundHandles,
    this._db,
    this._groups,
    this._outbox,
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
    // ONE subscription for every state change; the dispatch below decides
    // what a given update persists. A new state event costs one `case` here
    // and nothing anywhere else in the isolate/protocol/facade plumbing.
    _stateSub ??= _client.stateUpdates.listen((update) {
      _persistPending = _persistPending
          .then((_) => _persist(update))
          .catchError(
            (Object e) => debugPrint(
              'MessageSyncService: failed to persist '
              '${update.runtimeType}: $e',
            ),
          );
    });
    // T111: a channel row is the trigger to hand the channel to the worker —
    // not whichever screen happened to create it. Before, `chat_screen.build`
    // registered the keys, so "is this channel live?" depended on the user
    // opening the chat; anything that adds a row another way (the duo-E2E
    // harness joins straight through the repository, and a future deep link
    // or import would too) silently ended up with a channel the worker has no
    // key for. The watcher makes it a property of the DATA instead.
    _channelIdsSub ??= _db
        .select(_db.channels)
        .map((c) => c.uuid)
        .watch()
        .listen((ids) {
          for (final id in ids) {
            // Claim the id BEFORE the async restore so a burst of writes
            // cannot start two restores for the same channel.
            if (!_registeredChannelIds.add(id)) continue;
            unawaited(
              registerChannel(id).catchError((Object e) {
                // Un-claim so the next write to the table retries instead of
                // leaving a channel the worker has no key for.
                _registeredChannelIds.remove(id);
                debugPrint(
                  'MessageSyncService: failed to register channel $id: $e',
                );
              }),
            );
          }
        });
  }

  /// Applies one state update to the local database. The single dispatch
  /// point of the persistence channel; runs inside [_persistPending], so
  /// writes never interleave and a failure cannot break the chain.
  Future<void> _persist(StateUpdate update) async {
    switch (update) {
      case OhMailboxUpdate():
        await handleMailboxUpdate(update);
      case RatchetStateUpdate():
        await handleRatchetStateUpdate(update);
      case GarlicSessionUpdate():
        await handleGarlicSessionUpdate(update);
      case RoutingAckUpdate():
        // T112: delivery lifecycle transitions belong to the outbox.
        await _outbox.onRoutingAck(update);
      case ChannelAckUpdate():
        await _outbox.onChannelAck(update);
      case NodeScoreUpdate():
        await handleNodeScores(update.scores);
      case OwnOhSetUpdate():
        await handleOhRegistrationUpdate(update);
      case CounterpartOhUpdate():
        await handleCounterpartOhUpdate(update);
      case GroupStateUpdate():
        await _groups.applyStateUpdate(update);
      default:
        // Not persisted here: OhFetchStatus (UI-only, channel_health) and
        // GroupHandshakeEvent (owned by GroupService).
        break;
    }
  }

  Future<void> stop() async {
    await _messageSub?.cancel();
    await _stateSub?.cancel();
    await _channelIdsSub?.cancel();
    _messageSub = null;
    _stateSub = null;
    _channelIdsSub = null;
    // Drain what is still queued: the subscriptions are gone, so no new link
    // can be appended, and callers (tests, app teardown) may close the
    // database right after stop() — a write still in flight would then fail.
    // Safe to await: every link carries its own catchError, so the chain
    // never completes with an error.
    await _persistPending;
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
      // MS08: group messages carry their authenticated sender; 1:1 messages
      // keep the channel id as sender (the counterpart).
      senderId: msg.senderMemberIdHex ?? channelId,
      content: msg.content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.receivedAtMs),
      senderMemberId: msg.senderMemberIdHex,
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

  /// Syncs the channel's persisted own-OH rows to the current set (T42
  /// multi-OH) so the redundancy top-up and failover replacements survive an
  /// app restart. Dead mailboxes are dropped, new ones added.
  Future<void> handleOhRegistrationUpdate(OwnOhSetUpdate update) async {
    // [OwnOhSetUpdate.handles] is never empty by contract; the guard stays
    // because the alternative reading of an empty set here would be
    // destructive (delete every persisted mailbox row of the channel).
    if (update.handles.isEmpty) return;
    final channelId = update.channelId;
    if (channelId == null) return;
    await _outboundHandles.replaceAllForChannel(channelId, update.handles);
  }

  /// Persists the partner's full mailbox set announced in-band via `oh_update`
  /// (T42 multi-OH) so the deposit fan-out keeps reaching every mailbox after
  /// a restart. The primary (first) also feeds the single-target columns.
  Future<void> handleCounterpartOhUpdate(CounterpartOhUpdate update) async {
    if (update.descriptors.isEmpty) return;
    final primary = update.descriptors.first;
    final setJson = jsonEncode(
      update.descriptors.map((d) => d.toJsonMap()).toList(),
    );
    await (_db.update(
      _db.channels,
    )..where((c) => c.uuid.equals(update.channelId))).write(
      ChannelsCompanion(
        counterpartOhEndpoint: Value(primary.serverEndpoint),
        counterpartOhId: Value(HEX.encode(primary.handleId)),
        counterpartOhPublicKey: Value(HEX.encode(primary.authPublicKey)),
        counterpartOhSet: Value(setJson),
      ),
    );
  }

  /// Decodes the persisted counterpart OH set JSON (T42) into descriptors, or null
  /// when absent/malformed (the client then falls back to the primary OH).
  static List<OHDescriptor>? decodeCounterpartOhSet(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      final out = [
        for (final entry in decoded)
          OHDescriptor.fromJsonMap(entry as Map<String, dynamic>),
      ];
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
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

  /// Persists a node-score snapshot (MS06) so hop selection keeps its
  /// R-ACK history across app restarts.
  Future<void> handleNodeScores(List<NodeScore> scores) async {
    await _db.transaction(() async {
      for (final score in scores) {
        await _db
            .into(_db.nodeScores)
            .insert(
              NodeScoresCompanion.insert(
                nodeId: score.nodeIdHex,
                successCount: Value(score.successCount),
                failureCount: Value(score.failureCount),
                avgLatencyMs: Value(score.avgLatencyMs),
                lastUpdated: Value(
                  DateTime.fromMillisecondsSinceEpoch(score.lastUpdatedMs),
                ),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
    });
  }

  /// Restores channel keys and persisted OH registrations into the network
  /// client so polling resumes from the persisted cursor after a restart.
  ///
  /// One of the two callers of [_registerChannel] — see [registerChannel].
  Future<void> restorePersistedState() async {
    final channels = await _db.select(_db.channels).get();
    final allTags = await _db.select(_db.sessionTags).get();
    for (final channel in channels) {
      _registerChannel(channel, {
        for (final tag in allTags)
          if (tag.channelId == channel.uuid)
            tag.tag: tag.createdAt.millisecondsSinceEpoch,
      });
    }

    final handles = await _outboundHandles.getAllValid();
    for (final handle in handles) {
      await _client.restoreOutboundHandle(
        await _outboundHandles.toRegistration(handle),
      );
    }

    // MS06: feed persisted node scores back into the hop selection.
    final scores = await _db.select(_db.nodeScores).get();
    if (scores.isNotEmpty) {
      _client.restoreNodeScores([
        for (final score in scores)
          NodeScore(
            nodeIdHex: score.nodeId,
            successCount: score.successCount,
            failureCount: score.failureCount,
            avgLatencyMs: score.avgLatencyMs,
            lastUpdatedMs: score.lastUpdated?.millisecondsSinceEpoch ?? 0,
          ),
      ]);
    }
  }

  /// Hands ONE channel's persisted state to the network worker (T111).
  ///
  /// Call this whenever a channel becomes relevant to the network layer that
  /// was not there at [restorePersistedState] time — i.e. right after
  /// creating or joining one. Both paths funnel into [_registerChannel], so
  /// the worker is never handed a SUBSET of a channel's state: the chat
  /// screen used to re-register from `build()` without the garlic session and
  /// display name, which the worker-respawn projection then cached as the
  /// channel's entire state (the H8 bug class).
  ///
  /// The worker is authoritative — it adopts this snapshot only for a channel
  /// it does not know yet — so calling this more than once is harmless.
  Future<void> registerChannel(String channelId) async {
    final channel = await (_db.select(
      _db.channels,
    )..where((c) => c.uuid.equals(channelId))).getSingleOrNull();
    if (channel == null) return;
    final tags = await (_db.select(
      _db.sessionTags,
    )..where((t) => t.channelId.equals(channelId))).get();
    _registerChannel(channel, {
      for (final tag in tags) tag.tag: tag.createdAt.millisecondsSinceEpoch,
    });
  }

  /// The ONE place that translates a persisted channel row into the network
  /// worker's restore call — with the COMPLETE argument set. Anything that
  /// registers a channel with fewer arguments is a bug, not an optimization.
  void _registerChannel(Channel channel, Map<String, int> sessionTags) {
    _registeredChannelIds.add(channel.uuid);
    _client.addChannelKeys(
      channel.uuid,
      HEX.decode(channel.encryptionKey),
      // T44: the channel secret enables the rendezvous DHT layer.
      channelSecret: channel.channelSecret != null
          ? HEX.decode(channel.channelSecret!)
          : null,
      counterpartOhId: channel.counterpartOhId != null
          ? HEX.decode(channel.counterpartOhId!)
          : null,
      counterpartOhEndpoint: channel.counterpartOhEndpoint,
      // T42: restore the full persisted counterpart OH set so the deposit fan-out
      // survives a restart (the partner only re-announces on change).
      counterpartOhSet: decodeCounterpartOhSet(channel.counterpartOhSet),
      // The creator is the device holding the channel auth private key;
      // a device that joined via QR code holds only the public key.
      isChannelCreator: channel.authPrivateKey != null,
      ratchetState: channel.ratchetState,
      sessionTags: sessionTags.isEmpty ? null : sessionTags,
      pendingRgbHex: channel.pendingRgb,
    );
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
    ref.watch(groupRepositoryProvider),
    ref.watch(outboxServiceProvider),
  );
});

/// Mailbox overflow warnings for the UI.
final mailboxOverflowProvider = StreamProvider<OhMailboxUpdate>((ref) {
  return ref.watch(messageSyncServiceProvider).overflowEvents;
});
