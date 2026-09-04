import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Latest mailbox fetch state of one channel. In-memory only — the polling
/// loop repopulates it within one cycle (30 s) after an app restart, so
/// nothing needs to be persisted.
class ChannelFetchInfo {
  /// Last time the node confirmed a mailbox check (fetch answered OK).
  final DateTime? lastOkAt;

  /// Last fetch attempt, successful or not.
  final DateTime? lastAttemptAt;

  /// Failure reason of the last attempt; null when it succeeded.
  final String? lastError;

  const ChannelFetchInfo({this.lastOkAt, this.lastAttemptAt, this.lastError});
}

/// conversationId → latest [ChannelFetchInfo], fed by the client's per-attempt
/// fetch outcomes.
class ChannelFetchInfoNotifier extends Notifier<Map<String, ChannelFetchInfo>> {
  @override
  Map<String, ChannelFetchInfo> build() {
    final sub = ref
        .watch(redPandaClientProvider)
        .stateUpdates
        .of<OhFetchStatus>()
        .listen(_onStatus);
    ref.onDispose(sub.cancel);
    return const {};
  }

  void _onStatus(OhFetchStatus status) {
    final conversationId = status.channelId;
    if (conversationId == null) return;
    final previous = state[conversationId];
    final at = DateTime.fromMillisecondsSinceEpoch(status.atMs);
    state = {
      ...state,
      conversationId: ChannelFetchInfo(
        lastOkAt: status.success ? at : previous?.lastOkAt,
        lastAttemptAt: at,
        lastError: status.success ? null : (status.detail ?? 'failed'),
      ),
    };
  }
}

final channelFetchInfoProvider =
    NotifierProvider<ChannelFetchInfoNotifier, Map<String, ChannelFetchInfo>>(
      ChannelFetchInfoNotifier.new,
    );

/// Aggregated outbox/inbox state of one conversation, folded live from the
/// messages table.
class ConversationStats {
  /// Messages waiting in the send queue.
  final int pendingCount;

  /// Messages handed to the network, R-ACK still outstanding.
  final int sentCount;

  /// Messages given up after the maximum retries.
  final int failedCount;

  /// Earliest time the retry queue will attempt a pending message again.
  final DateTime? nextRetryAt;

  /// Newest own message confirmed at least `routed` (reached the counterpart's
  /// mailbox). Timestamps are creation times — good enough as "last time
  /// sending demonstrably worked".
  final DateTime? lastConfirmedAt;

  /// Newest incoming message.
  final DateTime? lastReceivedAt;

  const ConversationStats({
    this.pendingCount = 0,
    this.sentCount = 0,
    this.failedCount = 0,
    this.nextRetryAt,
    this.lastConfirmedAt,
    this.lastReceivedAt,
  });

  static ConversationStats fromMessages(List<Message> messages, DateTime now) {
    var pending = 0, sent = 0, failed = 0;
    DateTime? nextRetryAt, lastConfirmedAt, lastReceivedAt;
    for (final msg in messages) {
      switch (msg.status) {
        case MessageStatus.pending:
          pending++;
          // Mirrors OutboxService.isDue: no lastRetryAt means due now.
          final due = msg.lastRetryAt == null
              ? now
              : msg.lastRetryAt!.add(OutboxService.backoffFor(msg.retryCount));
          if (nextRetryAt == null || due.isBefore(nextRetryAt)) {
            nextRetryAt = due;
          }
        case MessageStatus.sent:
          sent++;
        case MessageStatus.failed:
          failed++;
        case MessageStatus.routed:
        case MessageStatus.delivered:
          if (lastConfirmedAt == null ||
              msg.timestamp.isAfter(lastConfirmedAt)) {
            lastConfirmedAt = msg.timestamp;
          }
        case MessageStatus.received:
          if (lastReceivedAt == null || msg.timestamp.isAfter(lastReceivedAt)) {
            lastReceivedAt = msg.timestamp;
          }
      }
    }
    return ConversationStats(
      pendingCount: pending,
      sentCount: sent,
      failedCount: failed,
      nextRetryAt: nextRetryAt,
      lastConfirmedAt: lastConfirmedAt,
      lastReceivedAt: lastReceivedAt,
    );
  }
}

final conversationStatsProvider =
    StreamProvider.family<ConversationStats, String>((ref, conversationId) {
      final db = ref.watch(dbProvider);
      return (db.select(db.messages)
            ..where((t) => t.conversationId.equals(conversationId)))
          .watch()
          .map((rows) => ConversationStats.fromMessages(rows, DateTime.now()));
    });

/// The newest own Outbound Handle registration for a channel (null when
/// receiving is not set up yet). Newest first: a re-registration after
/// expiry inserts a fresh row.
final ownHandleProvider = StreamProvider.family<OutboundHandle?, String>((
  ref,
  conversationId,
) {
  final db = ref.watch(dbProvider);
  return (db.select(db.outboundHandles)
        ..where((t) => t.conversationId.equals(conversationId))
        ..orderBy([(t) => OrderingTerm.desc(t.expiresAt)])
        ..limit(1))
      .watchSingleOrNull();
});

/// One channels-table row, live.
final channelRowProvider = StreamProvider.family<ChannelRow?, String>((
  ref,
  conversationId,
) {
  final db = ref.watch(dbProvider);
  return (db.select(db.channels)
        ..where((t) => t.conversationId.equals(conversationId))
        ..limit(1))
      .watchSingleOrNull();
});

/// Rebuild trigger so time-based health (fetch staleness, retry countdown)
/// stays current while a screen is open.
final healthTickProvider = StreamProvider<int>((ref) {
  return Stream<int>.periodic(const Duration(seconds: 5), (i) => i);
});

enum ChannelHealthLevel { unknown, healthy, degraded, problem }

class ChannelHealth {
  final ChannelHealthLevel level;
  final List<String> reasons;
  const ChannelHealth(this.level, this.reasons);
}

/// A successful mailbox check older than this counts as stale (three
/// 30-second polling cycles).
const staleFetchThreshold = Duration(seconds: 90);

/// Pure health rules — kept free of providers for unit testing.
ChannelHealth computeChannelHealth({
  required ConnectionStatus? connection,
  required ChannelFetchInfo? fetchInfo,
  required OutboundHandle? ownHandle,
  required bool counterpartOhKnown,
  required ConversationStats? stats,
  required DateTime now,
}) {
  final problems = <String>[];
  final degradations = <String>[];

  if (connection == ConnectionStatus.disconnected ||
      connection == ConnectionStatus.offline) {
    problems.add('Not connected to the network');
  } else if (connection != ConnectionStatus.connected) {
    degradations.add('Connecting to the network…');
  }

  if (ownHandle == null) {
    degradations.add('Receiving not set up yet (no own mailbox)');
  } else if (ownHandle.expiresAt.isBefore(now)) {
    problems.add('Own mailbox registration expired');
  } else if (connection == ConnectionStatus.connected) {
    final lastOkAt = fetchInfo?.lastOkAt;
    if (lastOkAt != null && now.difference(lastOkAt) > staleFetchThreshold) {
      degradations.add('Mailbox not checked recently');
    } else if (lastOkAt == null && fetchInfo?.lastError != null) {
      degradations.add('Mailbox check failing: ${fetchInfo!.lastError}');
    }
  }

  if (!counterpartOhKnown) {
    degradations.add("Recipient's mailbox unknown — scan their QR code");
  }

  if (stats != null) {
    if (stats.failedCount > 0) {
      problems.add('${stats.failedCount} message(s) failed after all retries');
    }
    if (stats.pendingCount > 0) {
      degradations.add('${stats.pendingCount} message(s) waiting to be sent');
    }
  }

  if (problems.isNotEmpty) {
    return ChannelHealth(ChannelHealthLevel.problem, [
      ...problems,
      ...degradations,
    ]);
  }
  if (degradations.isNotEmpty) {
    return ChannelHealth(ChannelHealthLevel.degraded, degradations);
  }
  if (connection == null) {
    return const ChannelHealth(ChannelHealthLevel.unknown, []);
  }
  return const ChannelHealth(ChannelHealthLevel.healthy, []);
}

/// Live health of one 1:1 channel, for the home-screen dot and the status
/// page banner.
final channelHealthProvider = Provider.family<ChannelHealth, String>((
  ref,
  conversationId,
) {
  ref.watch(healthTickProvider);
  final connection = ref.watch(connectionStatusProvider).value;
  final fetchInfo = ref.watch(channelFetchInfoProvider)[conversationId];
  final ownHandle = ref.watch(ownHandleProvider(conversationId)).value;
  final channelRow = ref.watch(channelRowProvider(conversationId)).value;
  final stats = ref.watch(conversationStatsProvider(conversationId)).value;
  return computeChannelHealth(
    connection: connection,
    fetchInfo: fetchInfo,
    ownHandle: ownHandle,
    counterpartOhKnown: channelRow?.counterpartOhId != null,
    stats: stats,
    now: DateTime.now(),
  );
});
