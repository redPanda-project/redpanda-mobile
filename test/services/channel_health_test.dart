import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/services/channel_health.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart' hide Channel;

final now = DateTime(2026, 7, 15, 12);

Message _message({
  int id = 1,
  int status = MessageStatus.pending,
  DateTime? timestamp,
  int retryCount = 0,
  DateTime? lastRetryAt,
}) {
  return Message(
    id: id,
    conversationId: 'chan',
    senderId: 'me',
    content: 'hi',
    timestamp: timestamp ?? now,
    status: status,
    type: 0,
    retryCount: retryCount,
  ).copyWith(lastRetryAt: Value(lastRetryAt));
}

OutboundHandle _handle({DateTime? expiresAt}) {
  return OutboundHandle(
    id: 1,
    ohId: 'aa' * 20,
    keypairBytes: Uint8List(32),
    serverEndpoint: 'node:59558',
    expiresAt: expiresAt ?? now.add(const Duration(days: 2)),
    lastCursor: 0,
  );
}

ChannelHealth _health({
  ConnectionStatus? connection = ConnectionStatus.connected,
  ChannelFetchInfo? fetchInfo,
  OutboundHandle? ownHandle,
  bool peerOhKnown = true,
  ConversationStats? stats = const ConversationStats(),
}) {
  return computeChannelHealth(
    connection: connection,
    fetchInfo:
        fetchInfo ??
        ChannelFetchInfo(lastOkAt: now.subtract(const Duration(seconds: 10))),
    ownHandle: ownHandle ?? _handle(),
    peerOhKnown: peerOhKnown,
    stats: stats,
    now: now,
  );
}

void main() {
  group('computeChannelHealth', () {
    test('healthy when connected, fresh fetch, peer known, outbox empty', () {
      final health = _health();
      expect(health.level, ChannelHealthLevel.healthy);
      expect(health.reasons, isEmpty);
    });

    test('disconnected is a problem', () {
      final health = _health(connection: ConnectionStatus.disconnected);
      expect(health.level, ChannelHealthLevel.problem);
    });

    test('connecting is only a degradation', () {
      final health = _health(connection: ConnectionStatus.connecting);
      expect(health.level, ChannelHealthLevel.degraded);
    });

    test('failed messages are a problem', () {
      final health = _health(stats: const ConversationStats(failedCount: 2));
      expect(health.level, ChannelHealthLevel.problem);
      expect(health.reasons.single, contains('2 message(s) failed'));
    });

    test('expired own mailbox registration is a problem', () {
      final health = _health(
        ownHandle: _handle(expiresAt: now.subtract(const Duration(minutes: 1))),
      );
      expect(health.level, ChannelHealthLevel.problem);
    });

    test('missing own mailbox degrades (receiving not set up)', () {
      final health = computeChannelHealth(
        connection: ConnectionStatus.connected,
        fetchInfo: null,
        ownHandle: null,
        peerOhKnown: true,
        stats: const ConversationStats(),
        now: now,
      );
      expect(health.level, ChannelHealthLevel.degraded);
      expect(health.reasons.single, contains('Receiving not set up'));
    });

    test('unknown peer mailbox degrades', () {
      final health = _health(peerOhKnown: false);
      expect(health.level, ChannelHealthLevel.degraded);
    });

    test('queued sends degrade', () {
      final health = _health(stats: const ConversationStats(pendingCount: 1));
      expect(health.level, ChannelHealthLevel.degraded);
    });

    test('stale mailbox check degrades', () {
      final health = _health(
        fetchInfo: ChannelFetchInfo(
          lastOkAt: now.subtract(const Duration(minutes: 5)),
        ),
      );
      expect(health.level, ChannelHealthLevel.degraded);
      expect(health.reasons.single, contains('not checked recently'));
    });

    test('never-checked mailbox with a failing attempt degrades', () {
      final health = _health(
        fetchInfo: ChannelFetchInfo(
          lastAttemptAt: now.subtract(const Duration(seconds: 5)),
          lastError: 'timeout',
        ),
      );
      expect(health.level, ChannelHealthLevel.degraded);
      expect(health.reasons.single, contains('timeout'));
    });

    test('never-checked mailbox without attempts stays healthy (startup)', () {
      final health = _health(fetchInfo: null);
      expect(health.level, ChannelHealthLevel.healthy);
    });

    test('problems rank above degradations and keep all reasons', () {
      final health = _health(
        connection: ConnectionStatus.disconnected,
        peerOhKnown: false,
        stats: const ConversationStats(pendingCount: 3),
      );
      expect(health.level, ChannelHealthLevel.problem);
      expect(health.reasons, hasLength(3));
    });
  });

  group('ConversationStats.fromMessages', () {
    test('counts statuses and folds timestamps', () {
      final stats = ConversationStats.fromMessages([
        _message(id: 1, status: MessageStatus.pending),
        _message(id: 2, status: MessageStatus.sent),
        _message(id: 3, status: MessageStatus.failed),
        _message(
          id: 4,
          status: MessageStatus.routed,
          timestamp: now.subtract(const Duration(minutes: 10)),
        ),
        _message(
          id: 5,
          status: MessageStatus.delivered,
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
        _message(
          id: 6,
          status: MessageStatus.received,
          timestamp: now.subtract(const Duration(minutes: 2)),
        ),
      ], now);

      expect(stats.pendingCount, 1);
      expect(stats.sentCount, 1);
      expect(stats.failedCount, 1);
      expect(stats.lastConfirmedAt, now.subtract(const Duration(minutes: 5)));
      expect(stats.lastReceivedAt, now.subtract(const Duration(minutes: 2)));
    });

    test('nextRetryAt is the earliest due pending message', () {
      final stats = ConversationStats.fromMessages([
        // retryCount 2 -> 1 min backoff, last attempt 30s ago -> due in 30s.
        _message(
          id: 1,
          retryCount: 2,
          lastRetryAt: now.subtract(const Duration(seconds: 30)),
        ),
        // retryCount 5 -> 8 min backoff, last attempt 1min ago -> due in 7min.
        _message(
          id: 2,
          retryCount: 5,
          lastRetryAt: now.subtract(const Duration(minutes: 1)),
        ),
      ], now);

      expect(stats.nextRetryAt, now.add(const Duration(seconds: 30)));
    });

    test('a pending message without attempts is due immediately', () {
      final stats = ConversationStats.fromMessages([_message()], now);
      expect(stats.nextRetryAt, now);
    });
  });
}
