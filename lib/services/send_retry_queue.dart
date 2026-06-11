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
          await _client.sendMessage(msg.conversationId, msg.content);
          await _messages.updateMessageStatus(msg.id, MessageStatus.sent);
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
