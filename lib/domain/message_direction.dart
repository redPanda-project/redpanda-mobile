/// Which way a message travelled, stored in `Messages.direction` (T114).
///
/// Before this existed, direction was a HEURISTIC read off two other fields
/// in `chat_screen.build`: `senderId != conversationId` for 1:1 chats and
/// `status != MessageStatus.received` for groups
/// (`DDD_ARCHITEKTUR_REVIEW_2026-08-31.md` §4,
/// `plans/ddd-review-2026-08-31/mobile-opus.md` §2.4 — "`senderId` has three
/// meanings … consequently message *direction* is a heuristic").
///
/// Both readings were derivations that happened to hold, not facts the model
/// stated:
///
/// - `senderId` is the local user's uuid for own messages, the conversation
///   id standing in for "them" for incoming 1:1 messages, and a group member
///   id for incoming group messages. Comparing it against the conversation id
///   only worked because the second case exists.
/// - The group reading rests on `received` being unreachable from any other
///   status. That is true today (see [MessageLifecycle]) and the master spec
///   already wants 4 back for a Read-ACK (review §4, "Status-Drift"): the day
///   a status is added, every outgoing group message flips side.
///
/// Direction is a property of the message, so the message stores it.
abstract final class MessageDirection {
  /// Composed on this device and handed to the outbox.
  static const int outgoing = 0;

  /// Fetched from our own mailbox.
  static const int incoming = 1;

  static String name(int direction) => switch (direction) {
    outgoing => 'outgoing',
    incoming => 'incoming',
    _ => 'unknown($direction)',
  };
}
