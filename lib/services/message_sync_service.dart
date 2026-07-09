import 'dart:async';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
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
  final GroupRepository _groups;

  final _overflowController = StreamController<OhMailboxUpdate>.broadcast();
  StreamSubscription<DecryptedMessage>? _messageSub;
  StreamSubscription<OhMailboxUpdate>? _updateSub;
  StreamSubscription<RatchetStateUpdate>? _ratchetSub;
  StreamSubscription<GarlicSessionUpdate>? _garlicSub;
  StreamSubscription<RoutingAckUpdate>? _routingAckSub;
  StreamSubscription<ChannelAckUpdate>? _channelAckSub;
  StreamSubscription<List<NodeScore>>? _nodeScoreSub;
  StreamSubscription<GroupStateUpdate>? _groupStateSub;

  /// Serializes ratchet-state DB writes so they are applied in emission
  /// order — a slow earlier write must not overwrite a newer state.
  Future<void> _ratchetPersistPending = Future.value();

  /// Same ordering guarantee for garlic-session snapshots (MS05).
  Future<void> _garlicPersistPending = Future.value();

  /// Same ordering guarantee for node-score snapshots (MS06).
  Future<void> _nodeScorePersistPending = Future.value();

  /// Same ordering guarantee for group state snapshots (MS08).
  Future<void> _groupStatePersistPending = Future.value();

  MessageSyncService(
    this._client,
    this._messages,
    this._outboundHandles,
    this._db,
    this._groups,
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
    _routingAckSub ??= _client.routingAckUpdates.listen(
      (update) => unawaited(
        handleRoutingAckUpdate(update).catchError(
          (Object e) =>
              debugPrint('MessageSyncService: failed to apply routing ack: $e'),
        ),
      ),
    );
    _channelAckSub ??= _client.channelAckUpdates.listen(
      (update) => unawaited(
        handleChannelAckUpdate(update).catchError(
          (Object e) =>
              debugPrint('MessageSyncService: failed to apply channel ack: $e'),
        ),
      ),
    );
    _nodeScoreSub ??= _client.nodeScoreUpdates.listen((scores) {
      _nodeScorePersistPending = _nodeScorePersistPending
          .then((_) => handleNodeScores(scores))
          .catchError(
            (Object e) => debugPrint(
              'MessageSyncService: failed to persist node scores: $e',
            ),
          );
    });
    _groupStateSub ??= _client.groupStateUpdates.listen((update) {
      _groupStatePersistPending = _groupStatePersistPending
          .then((_) => _groups.applyStateUpdate(update))
          .catchError(
            (Object e) => debugPrint(
              'MessageSyncService: failed to persist group state: $e',
            ),
          );
    });
  }

  Future<void> stop() async {
    await _messageSub?.cancel();
    await _updateSub?.cancel();
    await _ratchetSub?.cancel();
    await _garlicSub?.cancel();
    await _routingAckSub?.cancel();
    await _channelAckSub?.cancel();
    await _nodeScoreSub?.cancel();
    await _groupStateSub?.cancel();
    _messageSub = null;
    _updateSub = null;
    _ratchetSub = null;
    _garlicSub = null;
    _routingAckSub = null;
    _channelAckSub = null;
    _nodeScoreSub = null;
    _groupStateSub = null;
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
      // keep the channel id as sender (the peer).
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

  /// Applies routing-layer delivery feedback (MS06): an R-ACK confirms the
  /// message reached the recipient's OH mailbox (`routed`); HANDLE_EXPIRED,
  /// MAILBOX_FULL or a timeout re-queue the message for a retry over fresh
  /// hops (the node scorer already penalized the old ones on timeout).
  Future<void> handleRoutingAckUpdate(RoutingAckUpdate update) async {
    // MS08 (Decision 13): group deliveries ack per member — aggregate to
    // `routed` only once every other member's mailbox confirmed.
    final memberIdHex = update.memberIdHex;
    if (memberIdHex != null) {
      if (update.timedOut || update.status != RoutingAck.statusStored) {
        await _messages.requeueSentByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        return;
      }
      await _groups.markReceipt(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        memberId: memberIdHex,
        routed: true,
      );
      final group = await _groups.getGroup(update.channelId);
      if (group == null) return;
      final complete = await _groups.allMembersConfirmed(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        ownMemberId: group.myMemberId,
        delivered: false,
      );
      if (complete) {
        await _messages.markRoutedByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
      }
      return;
    }

    if (update.timedOut) {
      debugPrint(
        'MessageSyncService: no R-ACK for ${update.messageIdHex} — '
        're-queueing for fresh hops',
      );
      await _messages.requeueSentByNetworkId(
        update.channelId,
        update.messageIdHex,
      );
      return;
    }
    switch (update.status) {
      case RoutingAck.statusStored:
        await _messages.markRoutedByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        break;
      case RoutingAck.statusMailboxFull:
        // Reject-new (MS02b): retrying immediately cannot succeed; the
        // normal backoff applies via the re-queue.
        debugPrint(
          'MessageSyncService: recipient mailbox full for '
          '${update.messageIdHex}',
        );
        await _messages.requeueSentByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        break;
      case RoutingAck.statusHandleExpired:
      case RoutingAck.statusRejected:
      default:
        debugPrint(
          'MessageSyncService: deposit failed for ${update.messageIdHex} '
          '(status ${update.status})',
        );
        await _messages.requeueSentByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        break;
    }
  }

  /// Applies an application-layer delivery confirmation (Channel-ACK, MS06).
  Future<void> handleChannelAckUpdate(ChannelAckUpdate update) async {
    // MS08 (Decision 13): group acks aggregate per member — `delivered`
    // only once ALL other members confirmed. Acks are broadcast, so this
    // also fires for messages we merely received; those rows are excluded
    // by markDeliveredByNetworkId (status `received`).
    final memberIdHex = update.memberIdHex;
    if (memberIdHex != null) {
      await _groups.markReceipt(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        memberId: memberIdHex,
        routed: true,
        delivered: true,
      );
      final group = await _groups.getGroup(update.channelId);
      if (group == null) return;
      final complete = await _groups.allMembersConfirmed(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        ownMemberId: group.myMemberId,
        delivered: true,
      );
      if (!complete) return;
    }
    await _messages.markDeliveredByNetworkId(
      update.channelId,
      update.messageIdHex,
    );
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
  );
});

/// Mailbox overflow warnings for the UI.
final mailboxOverflowProvider = StreamProvider<OhMailboxUpdate>((ref) {
  return ref.watch(messageSyncServiceProvider).overflowEvents;
});
