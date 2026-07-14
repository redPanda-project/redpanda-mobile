import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Periodically re-sends pending messages with a fast-early / exponential-tail
/// backoff.
///
/// A message stays in status pending until a send attempt succeeds (then
/// sent) or [maxRetries] attempts failed (then failed). Backoff between
/// attempts follows [backoffFor]: the first few retries fire within seconds
/// (a first-attempt drop from the DHT announce race re-sends quickly), then
/// the tail doubles like before, capped at [maxBackoff].
class SendRetryQueue {
  final MessageRepository _messages;
  final RedPandaClient _client;
  final GroupRepository _groups;

  /// Worst-case total retry timespan is the sum of the backoff windows a
  /// message can incur, i.e. sum(backoffFor(0..maxRetries-1)):
  ///   10s+30s+1m+2m+4m+8m+16m + 5x30m = ~182 min (~3.0 h).
  /// The old 60s/2^n schedule with maxRetries=10 summed to ~181 min, so
  /// bumping maxRetries from 10 to 12 keeps the total window in the same
  /// (~3 h) ballpark despite the much faster early retries.
  static const int maxRetries = 12;

  /// Periodic tick. Lowered from 60s to 10s to match the 10s first backoff —
  /// a 60s tick would make the first fast retry no faster than one full
  /// minute. Each pass is a cheap indexed DB query (getPendingMessages on
  /// status=pending) and overlapping passes are skipped (see [retryPending]),
  /// so ticking every 10s is safe.
  static const Duration checkInterval = Duration(seconds: 10);
  static const Duration maxBackoff = Duration(minutes: 30);

  /// How much retryCount is incremented by when the recipient mailbox is
  /// full (QUOTA_EXCEEDED, reject-new). With the fast-early schedule a small
  /// penalty would only defer a few seconds, so it is 4: it lands the next
  /// backoff window at backoffFor(4) = 4 minutes (>= 4 min) — retrying sooner
  /// cannot succeed until the recipient fetched and acknowledged their
  /// mailbox.
  static const int quotaExceededPenalty = 4;

  Timer? _timer;
  bool _passInProgress = false;

  SendRetryQueue(this._messages, this._client, this._groups);

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
  ///
  /// Fast early retries, exponential tail (static and pure):
  ///   retryCount 0 -> 10s
  ///   retryCount 1 -> 30s
  ///   retryCount 2 -> 1m
  ///   retryCount 3 -> 2m
  ///   retryCount 4 -> 4m
  ///   retryCount 5 -> 8m
  ///   retryCount 6 -> 16m
  ///   retryCount >= 7 -> 30m (doubling from retryCount 2 on, i.e.
  ///                           2^(retryCount-2) min, capped at [maxBackoff]).
  static Duration backoffFor(int retryCount) {
    const earlySeconds = <int>[10, 30];
    if (retryCount < earlySeconds.length) {
      return Duration(seconds: earlySeconds[retryCount]);
    }
    // From retryCount 2 onward: 1, 2, 4, ... minutes = 2^(retryCount-2) min.
    final minutes = min(1 << (retryCount - 2), maxBackoff.inMinutes);
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
          // MS08: rows whose conversation is a group fan out via
          // sendGroupMessage instead.
          final usedId = await _groups.isGroup(msg.conversationId)
              ? await _client.sendGroupMessage(
                  msg.conversationId,
                  msg.content,
                  messageId: msg.messageId,
                )
              : await _client.sendMessage(
                  msg.conversationId,
                  msg.content,
                  messageId: msg.messageId,
                );
          if (msg.messageId == null || msg.messageId!.isEmpty) {
            await _messages.setNetworkMessageId(msg.id, usedId);
          }
          await _messages.updateMessageStatus(msg.id, MessageStatus.sent);
        } on GroupSendException catch (e) {
          // MS08: some members were not reached — normal backoff. Persist
          // the id the partial fan-out used so the re-send deduplicates at
          // the members that already got it.
          if ((msg.messageId == null || msg.messageId!.isEmpty) &&
              e.messageIdHex != null) {
            await _messages.setNetworkMessageId(msg.id, e.messageIdHex!);
          }
          await _messages.markRetryAttempt(msg.id);
        } on UnknownPeerException catch (e) {
          // Peer OH still unknown — normal backoff, becomes sendable once
          // the peer OH is registered (see redpanda_light_client.dart
          // sendMessage / REDPANDAJ-2DR).
          debugPrint(
            'SendRetryQueue: message ${msg.id} deferred, peer OH unknown '
            'for channel ${e.channelId}',
          );
          await _messages.markRetryAttempt(msg.id);
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
    ref.watch(groupRepositoryProvider),
  );
});
