import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/shared/providers.dart';

/// Message status values stored in [Messages.status].
class MessageStatus {
  MessageStatus._();

  /// Queued locally, not yet handed to the network.
  static const int pending = 0;

  /// Handed to a connected Full Node.
  static const int sent = 1;

  /// MS06: R-ACK received — the message reached the recipient's OH mailbox.
  static const int routed = 2;

  /// MS06: Channel-ACK received — the recipient's client has the message.
  static const int delivered = 3;

  /// Incoming message fetched from our OH mailbox.
  ///
  /// Note: the master-spec lifecycle reserves 4 for a future Read-ACK; this
  /// app has used 4 for incoming messages since MS01. Incoming and outgoing
  /// rows never mix status semantics (the UI only renders status icons for
  /// own messages), so the double use is safe — a Read-ACK would need a new
  /// value (6) if it ever lands.
  static const int received = 4;

  /// Given up after [SendRetryQueue.maxRetries] failed attempts.
  static const int failed = 5;
}

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
              // Store NULL (not empty string) for empty ids so the unique
              // index never groups malformed items together.
              messageId: drift.Value(messageId.isEmpty ? null : messageId),
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

  Future<void> updateMessageStatus(int id, int status) async {
    await (_db.update(_db.messages)..where((t) => t.id.equals(id))).write(
      MessagesCompanion(status: drift.Value(status)),
    );
  }

  /// MS06: marks the outgoing message with network id [messageIdHex] in
  /// [conversationId] as routed (R-ACK received). Only upgrades — a message
  /// already delivered (or failed after the ack raced the last retry) keeps
  /// its later status; failed is upgraded too, because the R-ACK proves the
  /// message reached the mailbox after all.
  Future<void> markRoutedByNetworkId(
    String conversationId,
    String messageIdHex,
  ) async {
    await (_db.update(_db.messages)..where(
          (t) =>
              t.conversationId.equals(conversationId) &
              t.messageId.equals(messageIdHex) &
              t.status.isIn(const [
                MessageStatus.pending,
                MessageStatus.sent,
                MessageStatus.failed,
              ]),
        ))
        .write(
          const MessagesCompanion(status: drift.Value(MessageStatus.routed)),
        );
  }

  /// MS06: marks the outgoing message as delivered (Channel-ACK received).
  /// Delivered is terminal evidence the partner has the message, so every
  /// earlier state — including failed — is upgraded.
  Future<void> markDeliveredByNetworkId(
    String conversationId,
    String messageIdHex,
  ) async {
    await (_db.update(_db.messages)..where(
          (t) =>
              t.conversationId.equals(conversationId) &
              t.messageId.equals(messageIdHex) &
              t.status.isNotIn(const [MessageStatus.received]),
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

    await (_db.update(_db.messages)..where((t) => t.id.equals(msg.id))).write(
      MessagesCompanion(
        status: const drift.Value(MessageStatus.pending),
        retryCount: drift.Value(msg.retryCount + 1),
        lastRetryAt: drift.Value(DateTime.now()),
      ),
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
  Future<void> markRetryAttempt(int id, {int penalty = 1}) async {
    final msg = await (_db.select(
      _db.messages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (msg == null) return;

    await (_db.update(_db.messages)..where((t) => t.id.equals(id))).write(
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
