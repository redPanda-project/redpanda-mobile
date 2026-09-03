import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/domain/message_direction.dart';
import 'package:redpanda/domain/message_lifecycle.dart';
import 'package:redpanda/shared/providers.dart';

// T112: the status constants and the lifecycle rule live in the domain file
// now; re-exported here so the ~20 existing `MessageStatus` importers keep
// working and the state machine is available wherever a status is written.
export 'package:redpanda/domain/message_lifecycle.dart'
    show MessageStatus, MessageLifecycle;

// T114: direction is a property of the message, not something the UI derives
// from senderId/status. Re-exported here for the same reason as the status.
export 'package:redpanda/domain/message_direction.dart' show MessageDirection;

/// Data access for chat messages: pending-send queries, retry bookkeeping
/// and deduplicated inserts of fetched messages.
class MessageRepository {
  final AppDatabase _db;

  MessageRepository(this._db);

  /// Inserts a locally composed outgoing message with status pending.
  /// Returns the database row id.
  Future<int> insertOutgoing({
    required String conversationId,
    required String senderId,
    required String content,
    String? messageId,
  }) {
    return _db
        .into(_db.messages)
        .insert(
          MessagesCompanion.insert(
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            timestamp: DateTime.now(),
            status: MessageStatus.pending,
            type: 0,
            direction: const drift.Value(MessageDirection.outgoing),
            messageId: drift.Value(messageId),
          ),
        );
  }

  /// Inserts a fetched message unless one with the same sender [messageId]
  /// already exists **in the same [conversationId]**. Returns true if the
  /// message was stored.
  ///
  /// Dedup is scoped per conversation: the sender chooses the 16-byte
  /// message_id, which is only unique within a channel. An empty [messageId]
  /// is treated as never-seen and always inserted, so a malformed item (one
  /// whose decrypted message id is empty) can never black-hole the channel by
  /// matching every later message.
  ///
  /// Check and insert run in a transaction so concurrent handlers cannot
  /// race past the exists-check and misreport an ignored insert as new.
  Future<bool> insertIncomingIfNew({
    required String messageId,
    required String conversationId,
    required String senderId,
    required String content,
    required DateTime timestamp,
    String? senderMemberId,
  }) {
    return _db.transaction(() async {
      if (messageId.isNotEmpty) {
        final exists = await messageExists(
          messageId,
          conversationId: conversationId,
        );
        if (exists) return false;
      }

      await _db
          .into(_db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: conversationId,
              senderId: senderId,
              content: content,
              timestamp: timestamp,
              status: MessageStatus.received,
              type: 0,
              direction: const drift.Value(MessageDirection.incoming),
              // Store NULL (not empty string) for empty ids so the unique
              // index never groups malformed items together.
              messageId: drift.Value(messageId.isEmpty ? null : messageId),
              // MS08: authenticated sender attribution for group messages.
              senderMemberId: drift.Value(senderMemberId),
            ),
            mode: drift.InsertMode.insertOrIgnore,
          );
      return true;
    });
  }

  /// True if a message with the given sender [messageId] already exists in
  /// [conversationId]. An empty [messageId] is never considered to exist.
  Future<bool> messageExists(String messageId, {String? conversationId}) async {
    if (messageId.isEmpty) return false;
    final row =
        await (_db.select(_db.messages)
              ..where(
                (t) => conversationId == null
                    ? t.messageId.equals(messageId)
                    : t.messageId.equals(messageId) &
                          t.conversationId.equals(conversationId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// All messages still waiting to be sent (status pending).
  Future<List<Message>> getPendingMessages() {
    return (_db.select(
      _db.messages,
    )..where((t) => t.status.equals(MessageStatus.pending))).get();
  }

  /// Persists the stable network-level message id assigned to an outgoing
  /// message on its first send attempt, so retries reuse the same id (the
  /// receiver deduplicates on it). No-op if already set, to keep the id stable.
  Future<void> setNetworkMessageId(int id, String messageId) async {
    await (_db.update(_db.messages)
          ..where((t) => t.id.equals(id) & t.messageId.isNull()))
        .write(MessagesCompanion(messageId: drift.Value(messageId)));
  }

  /// Moves message [id] to [status], if [MessageLifecycle] allows it.
  ///
  /// T112: the ONE place a message's status changes by row id. It reads the
  /// current status, checks the transition against the state machine and
  /// writes with the SQL guard derived from the very same table — an
  /// illegal transition is logged and skipped instead of silently
  /// downgrading a message (a Channel-ACK landing between a successful
  /// deposit and `markSent` used to turn `delivered` back into `sent`).
  ///
  /// Returns true if the row was written.
  Future<bool> updateMessageStatus(
    int id,
    int status, {
    drift.Value<DateTime?> lastRetryAt = const drift.Value.absent(),
    drift.Value<int> retryCount = const drift.Value.absent(),
  }) async {
    final msg = await (_db.select(
      _db.messages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (msg == null) return false;
    if (!MessageLifecycle.check(msg.status, status, 'message $id')) {
      return false;
    }
    final written =
        await (_db.update(_db.messages)..where(
              // Second line of defence: the row may have moved on between
              // the read above and this write (the persistence chain and a
              // send pass run concurrently). Same rule, same table.
              (t) =>
                  t.id.equals(id) &
                  t.status.isIn(MessageLifecycle.sourcesOf(status)),
            ))
            .write(
              MessagesCompanion(
                status: drift.Value(status),
                lastRetryAt: lastRetryAt,
                retryCount: retryCount,
              ),
            );
    return written > 0;
  }

  /// Gives up on a message after [OutboxService.maxRetries] attempts (or on
  /// a permanent rejection such as BAD_REQUEST).
  Future<void> markFailed(int id) async {
    await updateMessageStatus(id, MessageStatus.failed);
  }

  /// Marks a message `sent` and stamps [Messages.lastRetryAt] with the
  /// current time (TD002/T51): [requeueStaleSent] uses that stamp as "since
  /// when has this been sitting in `sent`" — without it, a message that
  /// succeeded on its very first attempt would have a null `lastRetryAt` and
  /// never qualify for the staleness sweep. Use this instead of
  /// [updateMessageStatus] for every sent-transition.
  Future<void> markSent(int id) async {
    await updateMessageStatus(
      id,
      MessageStatus.sent,
      lastRetryAt: drift.Value(DateTime.now()),
    );
  }

  /// Safety net (TD002/T51): re-queues messages that have sat in `sent` for
  /// longer than [olderThan] for a fresh send attempt.
  ///
  /// Delivery feedback for a sent message normally comes from the R-ACK
  /// timeout path (MessageSyncService.handleRoutingAckUpdate via
  /// RedPandaLightClient's in-memory AckTagStore, ~90s) — but a send that
  /// got no ack tag at all (no own OH mailbox yet at send time, or an
  /// oversized payload — see RedPandaLightClient._buildReturnPath) produces
  /// no timeout event and no ack, ever. Without this sweep such a message
  /// stays `sent` for the rest of the running session; only the next app
  /// restart's [requeueStuckSent] would catch it. [olderThan] must stay well
  /// above the R-ACK timeout so a normally tag-tracked send always gets its
  /// own timeout requeue first — this only catches what falls through that
  /// net.
  ///
  /// Increments `retryCount` like [requeueSentByNetworkId] does, so a
  /// permanently ack-less send (e.g. a channel whose partner never has an
  /// OH) does not get resent every 3 minutes forever without backoff — once
  /// `retryCount` climbs, [OutboxService.backoffFor] pushes it out past the
  /// sweep's own cadence.
  ///
  /// Deliberately does **not** touch `lastRetryAt`: the field stays at its
  /// old (>= [olderThan] ago) value, so [OutboxService.isDue] sees a stale
  /// timestamp against the *new*, higher `retryCount` — a message with a
  /// low retryCount is still due immediately (same-pass resend, the
  /// intended fast heal), while one whose retryCount already climbed into
  /// the backoff tail waits out that window before the pending pass picks
  /// it up again, same as a normal failed-attempt backoff.
  ///
  /// Returns the number of re-queued messages.
  Future<int> requeueStaleSent({
    Duration olderThan = const Duration(minutes: 3),
  }) async {
    final cutoff = DateTime.now().subtract(olderThan);
    final stale =
        await (_db.select(_db.messages)..where(
              (t) =>
                  t.status.equals(MessageStatus.sent) &
                  t.lastRetryAt.isSmallerOrEqualValue(cutoff),
            ))
            .get();
    if (stale.isEmpty) return 0;

    var requeued = 0;
    await _db.transaction(() async {
      for (final msg in stale) {
        // T112: still `sent` at write time — an ACK that landed between the
        // select above and this write must not be pulled back to pending.
        requeued +=
            await (_db.update(_db.messages)..where(
                  (t) =>
                      t.id.equals(msg.id) & t.status.equals(MessageStatus.sent),
                ))
                .write(
                  MessagesCompanion(
                    status: const drift.Value(MessageStatus.pending),
                    retryCount: drift.Value(msg.retryCount + 1),
                  ),
                );
      }
    });
    return requeued;
  }

  /// MS06: marks the outgoing message with network id [messageIdHex] in
  /// [conversationId] as routed (R-ACK received). Only upgrades — a message
  /// already delivered (or failed after the ack raced the last retry) keeps
  /// its later status; failed is upgraded too, because the R-ACK proves the
  /// message reached the mailbox after all.
  ///
  /// T112: the `where` list is [MessageLifecycle.sourcesOf], not a
  /// hand-written set — the "only upgrades" rule is stated once.
  Future<void> markRoutedByNetworkId(
    String conversationId,
    String messageIdHex,
  ) async {
    await (_db.update(_db.messages)..where(
          (t) =>
              t.conversationId.equals(conversationId) &
              t.messageId.equals(messageIdHex) &
              t.status.isIn(MessageLifecycle.sourcesOf(MessageStatus.routed)),
        ))
        .write(
          const MessagesCompanion(status: drift.Value(MessageStatus.routed)),
        );
  }

  /// MS06: marks the outgoing message as delivered (Channel-ACK received).
  /// Delivered is terminal evidence the partner has the message, so every
  /// earlier state — including failed — is upgraded (T112: again straight
  /// from [MessageLifecycle.sourcesOf]; incoming rows are excluded because
  /// `received` is not part of the outgoing lifecycle).
  Future<void> markDeliveredByNetworkId(
    String conversationId,
    String messageIdHex,
  ) async {
    await (_db.update(_db.messages)..where(
          (t) =>
              t.conversationId.equals(conversationId) &
              t.messageId.equals(messageIdHex) &
              t.status.isIn(
                MessageLifecycle.sourcesOf(MessageStatus.delivered),
              ),
        ))
        .write(
          const MessagesCompanion(status: drift.Value(MessageStatus.delivered)),
        );
  }

  /// MS06: re-queues a sent message whose R-ACK timed out (or whose ack
  /// reported HANDLE_EXPIRED) for a retry over fresh hops. Increments
  /// retryCount and stamps lastRetryAt so the normal backoff applies;
  /// touches only messages still in `sent` — a late Channel-ACK or R-ACK
  /// must not resurrect an already confirmed message.
  ///
  /// T112: that `sent` guard is deliberately NARROWER than what
  /// [MessageLifecycle] permits into `pending`. The state machine says which
  /// transitions are legal at all; "only a message we are still waiting for
  /// feedback on may be re-queued" is a precondition of this operation.
  Future<void> requeueSentByNetworkId(
    String conversationId,
    String messageIdHex,
  ) async {
    final msg =
        await (_db.select(_db.messages)
              ..where(
                (t) =>
                    t.conversationId.equals(conversationId) &
                    t.messageId.equals(messageIdHex) &
                    t.status.equals(MessageStatus.sent),
              )
              ..limit(1))
            .getSingleOrNull();
    if (msg == null) return;

    // T112: re-check `sent` in the write, not only in the select above — an
    // ACK arriving in between must not be downgraded to pending.
    await (_db.update(_db.messages)..where(
          (t) => t.id.equals(msg.id) & t.status.equals(MessageStatus.sent),
        ))
        .write(
          MessagesCompanion(
            status: const drift.Value(MessageStatus.pending),
            retryCount: drift.Value(msg.retryCount + 1),
            lastRetryAt: drift.Value(DateTime.now()),
          ),
        );
  }

  /// Puts a message back into the send queue for an immediate attempt,
  /// clearing the retry bookkeeping. Used by the "send again" action on
  /// failed/stuck messages — the user explicitly asked, so the backoff
  /// window starts over.
  ///
  /// Returns false when the message moved on in the meantime and must NOT be
  /// re-queued: the UI decides whether to retry from a snapshot (the details
  /// sheet), so an ACK can land between rendering the button and the tap.
  /// Before T112 this was an unconditional write and would have re-sent a
  /// message the recipient already had.
  Future<bool> resetForImmediateRetry(int id) {
    return updateMessageStatus(
      id,
      MessageStatus.pending,
      retryCount: const drift.Value(0),
      lastRetryAt: const drift.Value(null),
    );
  }

  /// Re-queues every message stuck in `sent` for a fresh send attempt.
  ///
  /// Ack tags live only in memory (AckTagStore), so after an app restart a
  /// message that was handed to the network but not yet R-ACKed can never be
  /// confirmed or timed out — it would stay `sent` forever. Called once on
  /// startup; the re-send reuses the stable network message id, so receivers
  /// that already got the message deduplicate it. retryCount and lastRetryAt
  /// are kept so the normal backoff continues instead of restarting.
  /// Returns the number of re-queued messages.
  Future<int> requeueStuckSent() {
    return (_db.update(
      _db.messages,
    )..where((t) => t.status.equals(MessageStatus.sent))).write(
      const MessagesCompanion(status: drift.Value(MessageStatus.pending)),
    );
  }

  /// Number of messages still waiting to be sent, as a live stream.
  Stream<int> watchPendingCount() {
    final countExp = _db.messages.id.count();
    final query = _db.selectOnly(_db.messages)
      ..addColumns([countExp])
      ..where(_db.messages.status.equals(MessageStatus.pending));
    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  /// Records a failed send attempt: increments retryCount and stamps
  /// lastRetryAt so the backoff window starts now.
  ///
  /// [penalty] is the retryCount increment. The default 1 gives the normal
  /// exponential backoff; a larger penalty widens the next backoff window
  /// without a schema change (used for QUOTA_EXCEEDED, where an immediate
  /// retry is pointless until the recipient fetched their mailbox).
  ///
  /// T112: touches only a row that is still `pending`. The bookkeeping does
  /// not change the status, but a message the recipient acknowledged while
  /// this attempt was in flight is done — stamping a new backoff window on
  /// a `routed`/`delivered` row would contradict "delivered is terminal"
  /// even though the status column itself stays put.
  Future<void> markRetryAttempt(int id, {int penalty = 1}) async {
    final msg = await (_db.select(
      _db.messages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (msg == null) return;

    await (_db.update(_db.messages)..where(
          (t) => t.id.equals(id) & t.status.equals(MessageStatus.pending),
        ))
        .write(
          MessagesCompanion(
            retryCount: drift.Value(msg.retryCount + penalty),
            lastRetryAt: drift.Value(DateTime.now()),
          ),
        );
  }
}

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.watch(dbProvider));
});

/// Live count of messages waiting to be sent.
final pendingMessageCountProvider = StreamProvider<int>((ref) {
  return ref.watch(messageRepositoryProvider).watchPendingCount();
});
