import 'package:flutter/foundation.dart';

/// Message status values stored in `Messages.status`.
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

  /// Given up after [OutboxService.maxRetries] failed attempts.
  static const int failed = 5;

  /// Every defined status, for diagnostics and the lifecycle table.
  static const List<int> all = [
    pending,
    sent,
    routed,
    delivered,
    received,
    failed,
  ];

  static String name(int status) => switch (status) {
    pending => 'pending',
    sent => 'sent',
    routed => 'routed',
    delivered => 'delivered',
    received => 'received',
    failed => 'failed',
    _ => 'unknown($status)',
  };
}

/// The delivery lifecycle of a message as an EXPLICIT state machine (T112).
///
/// Before this class the lifecycle existed only as the int constants above
/// plus hand-written SQL `where` guards spread over `MessageRepository`
/// (`status.isIn([pending, sent, failed])` for the R-ACK, `status.isNotIn(
/// [received])` for the Channel-ACK, nothing at all for `markSent`), so
/// "delivered is terminal" and "an ACK never downgrades a message" were
/// invariants of four independent queries rather than of one rule
/// (`DDD_ARCHITEKTUR_REVIEW_2026-08-31.md` §6 P1, `mobile-opus.md` §6.1).
///
/// The table below is that rule. It is BOTH the pre-write check in
/// [MessageRepository] AND — via [sourcesOf] — the source of the SQL guards,
/// so the two lines of defence cannot drift apart: the check catches a
/// transition the app should never have attempted (and says so in the log),
/// the SQL guard still catches the race where the row changed underneath us
/// between the read and the write.
///
/// Deliberately does NOT throw on an illegal transition. Every rejection
/// reachable in production is a benign race (a Channel-ACK landing between
/// a successful deposit and the `markSent` write, a late R-ACK for a message
/// the user already re-sent), and crashing the app — or, worse, killing the
/// persistence chain — over one of those would trade a no-op write for lost
/// state. Illegal transitions are logged and skipped; the unit tests assert
/// the table directly.
class MessageLifecycle {
  MessageLifecycle._();

  /// Status → the statuses it may move to. A status listed in its own set
  /// means the transition is idempotent (re-applying it is a legal no-op).
  ///
  /// - `pending` is the queue state: it can be handed to the network
  ///   (`sent`), given up on (`failed`), re-queued by the user
  ///   (`pending`), or confirmed directly by an ACK that raced the retry
  ///   (`routed`/`delivered`).
  /// - `sent` waits for delivery feedback: R-ACK (`routed`), Channel-ACK
  ///   (`delivered`) or an ack timeout / rejection that re-queues it
  ///   (`pending`).
  /// - `routed` may only be upgraded by the Channel-ACK.
  /// - `failed` is NOT terminal: an R-ACK or Channel-ACK arriving after the
  ///   last attempt proves the message got through after all, and the user
  ///   can re-queue it by hand.
  /// - `delivered` is terminal (a duplicate Channel-ACK is a no-op), and
  ///   `received` is not part of the outgoing lifecycle at all.
  static const Map<int, Set<int>> allowed = {
    MessageStatus.pending: {
      MessageStatus.pending,
      MessageStatus.sent,
      MessageStatus.routed,
      MessageStatus.delivered,
      MessageStatus.failed,
    },
    MessageStatus.sent: {
      MessageStatus.pending,
      MessageStatus.routed,
      MessageStatus.delivered,
    },
    MessageStatus.routed: {MessageStatus.delivered},
    MessageStatus.delivered: {MessageStatus.delivered},
    MessageStatus.failed: {
      MessageStatus.pending,
      MessageStatus.routed,
      MessageStatus.delivered,
    },
    MessageStatus.received: <int>{},
  };

  /// True if a message may move from [from] to [to].
  static bool isAllowed(int from, int to) =>
      allowed[from]?.contains(to) ?? false;

  /// Every status a message may be in for a transition to [to] to be legal.
  ///
  /// This is what the repository's SQL `where` guards are built from, so the
  /// guard and the table are the same rule expressed twice instead of two
  /// rules that can disagree.
  static List<int> sourcesOf(int to) => [
    for (final entry in allowed.entries)
      if (entry.value.contains(to)) entry.key,
  ];

  /// Checks a transition, logging (never throwing) when it is illegal.
  /// Returns true when the caller may go ahead with the write.
  static bool check(int from, int to, String what) {
    if (isAllowed(from, to)) return true;
    debugPrint(
      'MessageLifecycle: refused ${MessageStatus.name(from)} → '
      '${MessageStatus.name(to)} for $what',
    );
    return false;
  }
}
