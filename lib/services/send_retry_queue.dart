import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Periodically re-sends pending messages with exponential backoff.
///
/// A message stays in status pending until a send attempt succeeds (then
/// sent) or [maxRetries] attempts failed (then failed). Backoff between
/// attempts is 2^retryCount minutes, capped at [maxBackoff].
class SendRetryQueue {
  final MessageRepository _messages;
  final RedPandaClient _client;

  static const int maxRetries = 10;
  static const Duration checkInterval = Duration(seconds: 60);
  static const Duration maxBackoff = Duration(minutes: 30);

  /// How much retryCount is incremented by when the recipient mailbox is
  /// full (QUOTA_EXCEEDED, reject-new). Jumps the next backoff window to
  /// >= 2^3 = 8 minutes — retrying sooner cannot succeed until the
  /// recipient fetched and acknowledged their mailbox.
  static const int quotaExceededPenalty = 3;

  Timer? _timer;
  bool _passInProgress = false;

  SendRetryQueue(this._messages, this._client);

  void start() {
    _timer ??= Timer.periodic(
      checkInterval,
      (_) => unawaited(
        retryPending().catchError(
          (Object e) => debugPrint('SendRetryQueue: retry pass failed: $e'),
        ),
      ),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Backoff window after [retryCount] failed attempts.
  static Duration backoffFor(int retryCount) {
    final minutes = min(1 << retryCount, maxBackoff.inMinutes);
    return Duration(minutes: minutes);
  }

  /// True if the backoff window for [msg] has elapsed.
  static bool isDue(Message msg, DateTime now) {
    final lastRetryAt = msg.lastRetryAt;
    if (lastRetryAt == null) return true;
    return now.difference(lastRetryAt) >= backoffFor(msg.retryCount);
  }

  /// Single retry pass over all pending messages. Public for testing;
  /// normally invoked by the periodic timer. Overlapping passes are
  /// skipped so slow sends cannot update the same rows out of order.
  Future<void> retryPending() async {
    if (_passInProgress) return;
    _passInProgress = true;
    try {
      final pending = await _messages.getPendingMessages();
      final now = DateTime.now();

      for (final msg in pending) {
        if (msg.retryCount >= maxRetries) {
          await _messages.updateMessageStatus(msg.id, MessageStatus.failed);
          continue;
        }
        if (!isDue(msg, now)) continue;

        try {
          // Reuse the stable network message id across attempts so re-sends
          // deduplicate at the receiver. On the very first attempt the row has
          // no id yet; sendMessage generates one which we then persist.
          final usedId = await _client.sendMessage(
            msg.conversationId,
            msg.content,
            messageId: msg.messageId,
          );
          if (msg.messageId == null || msg.messageId!.isEmpty) {
            await _messages.setNetworkMessageId(msg.id, usedId);
          }
          await _messages.updateMessageStatus(msg.id, MessageStatus.sent);
        } on DepositException catch (e) {
          // MS02b: the node reported why the deposit was rejected.
          if (e.isBadRequest) {
            // Item exceeds the per-item size limit (64 KiB) — re-sending the
            // same payload can never succeed.
            await _messages.updateMessageStatus(msg.id, MessageStatus.failed);
          } else if (e.isQuotaExceeded) {
            // Recipient mailbox full (reject-new): back off harder than for
            // transient network failures.
            await _messages.markRetryAttempt(
              msg.id,
              penalty: quotaExceededPenalty,
            );
          } else {
            // e.g. NOT_FOUND (hop limit) — normal backoff, routing may
            // recover.
            await _messages.markRetryAttempt(msg.id);
          }
        } catch (_) {
          await _messages.markRetryAttempt(msg.id);
        }
      }
    } finally {
      _passInProgress = false;
    }
  }
}

final sendRetryQueueProvider = Provider<SendRetryQueue>((ref) {
  return SendRetryQueue(
    ref.watch(messageRepositoryProvider),
    ref.watch(redPandaClientProvider),
  );
});
