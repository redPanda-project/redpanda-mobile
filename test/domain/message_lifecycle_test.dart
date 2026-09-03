import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/domain/message_lifecycle.dart';

/// T112 — the outgoing-message lifecycle as an explicit state machine.
///
/// These assert the RULE. That the repository actually applies it (and that
/// the SQL guards are built from the same table) is pinned in
/// `message_repository_test.dart` and `outbox_service_test.dart`.
void main() {
  group('MessageLifecycle table', () {
    test('covers every defined status', () {
      expect(
        MessageLifecycle.allowed.keys.toSet(),
        equals(MessageStatus.all.toSet()),
      );
    });

    test('never allows a transition into a status that is not defined', () {
      for (final targets in MessageLifecycle.allowed.values) {
        expect(targets.difference(MessageStatus.all.toSet()), isEmpty);
      }
    });

    test('delivered is terminal (only a duplicate ACK is a legal no-op)', () {
      expect(
        MessageLifecycle.allowed[MessageStatus.delivered],
        equals({MessageStatus.delivered}),
      );
      for (final to in MessageStatus.all) {
        if (to == MessageStatus.delivered) continue;
        expect(
          MessageLifecycle.isAllowed(MessageStatus.delivered, to),
          isFalse,
          reason: 'delivered → ${MessageStatus.name(to)} must not be legal',
        );
      }
    });

    test('an incoming message never enters the outgoing lifecycle', () {
      for (final to in MessageStatus.all) {
        expect(MessageLifecycle.isAllowed(MessageStatus.received, to), isFalse);
      }
      expect(
        MessageLifecycle.sourcesOf(MessageStatus.delivered),
        isNot(contains(MessageStatus.received)),
      );
    });

    test('an ACK never downgrades a message', () {
      // routed may only be upgraded to delivered …
      expect(
        MessageLifecycle.allowed[MessageStatus.routed],
        equals({MessageStatus.delivered}),
      );
      // … and a late R-ACK cannot pull delivered or routed back.
      expect(
        MessageLifecycle.sourcesOf(MessageStatus.routed),
        unorderedEquals([
          MessageStatus.pending,
          MessageStatus.sent,
          MessageStatus.failed,
        ]),
      );
    });

    test('failed is not terminal: an ACK or the user may revive it', () {
      expect(
        MessageLifecycle.allowed[MessageStatus.failed],
        equals({
          MessageStatus.pending,
          MessageStatus.routed,
          MessageStatus.delivered,
        }),
      );
    });

    test('a message can only be marked sent out of the queue', () {
      expect(
        MessageLifecycle.sourcesOf(MessageStatus.sent),
        equals([MessageStatus.pending]),
      );
    });

    test('sourcesOf is the inverse of the table', () {
      for (final to in MessageStatus.all) {
        for (final from in MessageStatus.all) {
          expect(
            MessageLifecycle.sourcesOf(to).contains(from),
            equals(MessageLifecycle.isAllowed(from, to)),
            reason: '${MessageStatus.name(from)} → ${MessageStatus.name(to)}',
          );
        }
      }
    });

    test('check() rejects an illegal transition without throwing', () {
      expect(
        MessageLifecycle.check(
          MessageStatus.delivered,
          MessageStatus.sent,
          'row 1',
        ),
        isFalse,
      );
      expect(
        MessageLifecycle.check(
          MessageStatus.pending,
          MessageStatus.sent,
          'row 1',
        ),
        isTrue,
      );
    });
  });
}
