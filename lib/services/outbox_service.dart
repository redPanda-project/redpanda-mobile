import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Why a delivery attempt did not hand the message to the network.
enum DeliveryFailure {
  /// MS08: the fan-out reached some, but not all, group members.
  groupPartial,

  /// BAD_REQUEST — over the per-item size limit; retrying cannot help.
  tooLarge,

  /// QUOTA_EXCEEDED — the recipient's mailbox is full (reject-new).
  mailboxFull,

  /// Any other deposit rejection (e.g. NOT_FOUND / hop limit).
  depositRejected,

  /// The channel's partner mailbox is not known yet (REDPANDAJ-2DR).
  unknownCounterpart,

  /// Anything else (not connected, socket error, isolate timeout …).
  transport,
}

/// The outcome of ONE delivery attempt for ONE message (T112).
///
/// The outbox emits these for every attempt it makes, successful or not. It
/// is what makes the send path observable from outside without giving anyone
/// else a way into it: the chat screen renders a snackbar for the attempt
/// the user just triggered instead of running the send itself.
@immutable
class DeliveryAttempt {
  /// `Messages.id` of the row the attempt was made for.
  final int messageRowId;

  final String conversationId;

  /// 1 for the first attempt (`retryCount` 0), 2 for the first retry, …
  final int attempt;

  /// Null when the message was handed to the network.
  final DeliveryFailure? failure;

  /// MS08: number of members the fan-out did not reach
  /// ([DeliveryFailure.groupPartial] only).
  final int unreachedMembers;

  const DeliveryAttempt({
    required this.messageRowId,
    required this.conversationId,
    required this.attempt,
    this.failure,
    this.unreachedMembers = 0,
  });

  bool get succeeded => failure == null;

  @override
  String toString() =>
      'DeliveryAttempt(row $messageRowId, attempt $attempt, '
      '${failure?.name ?? 'ok'})';
}

/// The app's outbox: the ONE component that hands a message to the network
/// (T112).
///
/// Before this, the send attempt existed twice — `chat_screen._sendMessage`
/// for the composer and `SendRetryQueue.retryPending` for every later
/// attempt — with two different policies for the same failures (the queue
/// applied the QUOTA_EXCEEDED penalty and the retry cap, the screen did
/// not), and the UI reached into the network client, the message repository
/// and the group repository to do it
/// (`DDD_ARCHITEKTUR_REVIEW_2026-08-31.md` §6 P1, `mobile-opus.md` §4/§6.1).
/// Now the UI only [enqueue]s and this class owns send, retry, backoff,
/// every failure policy and every ACK transition.
///
/// Retry schedule (unchanged from `SendRetryQueue`): a message stays
/// `pending` until an attempt succeeds (then `sent`) or [maxRetries]
/// attempts failed (then `failed`); the wait between attempts follows
/// [backoffFor] — the first retries fire within seconds (a first-attempt
/// drop from the DHT announce race re-sends quickly), then the tail doubles,
/// capped at [maxBackoff].
///
/// This is deliberately NOT part of `MessageSyncService`'s persistence chain
/// (T110): that chain serializes every state write, and a send attempt can
/// block for seconds on the network. The two meet only where they must —
/// the chain routes ACK updates into [onRoutingAck]/[onChannelAck] so the
/// lifecycle stays owned by one class.
class OutboxService {
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
  /// status=pending) and overlapping passes are skipped (see [runPass]),
  /// so ticking every 10s is safe.
  static const Duration checkInterval = Duration(seconds: 10);
  static const Duration maxBackoff = Duration(minutes: 30);

  /// Safety-net threshold for [MessageRepository.requeueStaleSent] (TD002/
  /// T51): well above the R-ACK timeout (90s, RedPandaLightClient.ackTimeout)
  /// so a normally tag-tracked send always gets its own timeout requeue via
  /// [onRoutingAck] first — this only catches sends that got no ack tag at
  /// all and would otherwise stay `sent` for the rest of the running session
  /// (no self-heal without an app restart).
  static const Duration staleSentThreshold = Duration(minutes: 3);

  /// How much retryCount is incremented by when the recipient mailbox is
  /// full (QUOTA_EXCEEDED, reject-new). With the fast-early schedule a small
  /// penalty would only defer a few seconds, so it is 4: it lands the next
  /// backoff window at backoffFor(4) = 4 minutes (>= 4 min) — retrying sooner
  /// cannot succeed until the recipient fetched and acknowledged their
  /// mailbox.
  static const int quotaExceededPenalty = 4;

  Timer? _timer;
  bool _passInProgress = false;
  Future<void>? _passFuture;
  bool _rerunRequested = false;
  bool _rerunIgnoresBackoff = false;
  StreamSubscription<ConnectionStatus>? _connectionSub;
  ConnectionStatus? _lastSeenStatus;
  final _attemptController = StreamController<DeliveryAttempt>.broadcast();

  OutboxService(this._messages, this._client, this._groups);

  /// Every attempt this outbox makes, in order. Broadcast and lossy by
  /// design — a listener that subscribes late has missed nothing that is
  /// not already in the message row's status.
  Stream<DeliveryAttempt> get attempts => _attemptController.stream;

  /// The pass currently running (including a rerun it may still trigger), or
  /// a completed future when the outbox is idle. [enqueue] and [retryNow]
  /// kick a pass without waiting for it, so this is how a test — or anything
  /// that wants to observe the result rather than the queueing — waits for
  /// the attempt to have happened.
  Future<void> get settled => _passFuture ?? Future<void>.value();

  void start() {
    _timer ??= Timer.periodic(
      checkInterval,
      (_) => unawaited(
        runPass().catchError(
          (Object e) => debugPrint('OutboxService: retry pass failed: $e'),
        ),
      ),
    );
    // T27: on (re)connect, re-send pending messages immediately instead of
    // waiting out their backoff window — a message that failed because the
    // device was offline is deliverable the moment the connection is back
    // (before this, an airplane-mode send waited up to a full backoff
    // window of minutes after reconnecting).
    _connectionSub ??= _client.connectionStatus.listen((status) {
      final wasConnected = _lastSeenStatus == ConnectionStatus.connected;
      _lastSeenStatus = status;
      if (status == ConnectionStatus.connected && !wasConnected) {
        unawaited(
          runPass(ignoreBackoff: true).catchError(
            (Object e) =>
                debugPrint('OutboxService: reconnect pass failed: $e'),
          ),
        );
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_connectionSub?.cancel());
    _connectionSub = null;
    _lastSeenStatus = null;
  }

  Future<void> dispose() async {
    stop();
    await _attemptController.close();
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

  /// Queues a locally composed message and kicks a send pass. The ONLY way
  /// into the send path from the app — the composer does not send.
  ///
  /// Returns the `Messages.id` of the queued row. The returned future
  /// completes once the row exists, NOT once it was delivered: delivery is
  /// the outbox's business and is reported through [attempts] and the row's
  /// status.
  Future<int> enqueue({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    final rowId = await _messages.insertOutgoing(
      conversationId: conversationId,
      senderId: senderId,
      content: content,
    );
    unawaited(
      runPass().catchError(
        (Object e) => debugPrint('OutboxService: send pass failed: $e'),
      ),
    );
    return rowId;
  }

  /// "Send again now" from the UI: clears the backoff bookkeeping of a
  /// pending/failed message and attempts it immediately.
  Future<void> retryNow(int messageRowId) async {
    await _messages.resetForImmediateRetry(messageRowId);
    unawaited(
      runPass().catchError(
        (Object e) => debugPrint('OutboxService: manual retry failed: $e'),
      ),
    );
  }

  /// One pass over all pending messages: sweeps stale `sent` rows back into
  /// the queue, then attempts every message whose backoff window elapsed.
  ///
  /// Passes never overlap — a pass requested while one is running is
  /// deferred to a rerun right after it, so a message enqueued during a
  /// slow pass still goes out immediately (the composer used to bypass the
  /// queue for exactly that reason) without two passes racing over the same
  /// row.
  ///
  /// [ignoreBackoff] re-sends every pending message regardless of its
  /// backoff window (used on reconnect); the [maxRetries] cap still holds.
  Future<void> runPass({bool ignoreBackoff = false}) {
    if (_passInProgress) {
      _rerunRequested = true;
      _rerunIgnoresBackoff = _rerunIgnoresBackoff || ignoreBackoff;
      // The in-flight loop will do the rerun, so its future is also the
      // answer to "when is what I just asked for done?".
      return _passFuture!;
    }
    // Set here, not inside the loop: `_passInProgress` and `_passFuture` must
    // become visible together, and nothing between these two statements can
    // re-enter runPass (`_passLoop` only awaits DB and network work).
    _passInProgress = true;
    return _passFuture = _passLoop(ignoreBackoff);
  }

  Future<void> _passLoop(bool ignoreBackoff) async {
    try {
      var ignore = ignoreBackoff;
      while (true) {
        _rerunRequested = false;
        _rerunIgnoresBackoff = false;
        await _pass(ignoreBackoff: ignore);
        if (!_rerunRequested) break;
        ignore = _rerunIgnoresBackoff;
      }
    } finally {
      _passInProgress = false;
      _rerunRequested = false;
      _rerunIgnoresBackoff = false;
    }
  }

  Future<void> _pass({required bool ignoreBackoff}) async {
    // TD002/T51: pull back anything stuck `sent` without an ack tag before
    // looking at the pending set, so a message this sweep just requeued is
    // picked up by the very same pass instead of waiting another tick.
    await _messages.requeueStaleSent(olderThan: staleSentThreshold);
    final pending = await _messages.getPendingMessages();
    final now = DateTime.now();

    for (final msg in pending) {
      if (msg.retryCount >= maxRetries) {
        await _messages.markFailed(msg.id);
        continue;
      }
      if (!ignoreBackoff && !isDue(msg, now)) continue;
      await _attempt(msg);
    }
  }

  /// ONE delivery attempt for [msg], plus the ONE policy for what each
  /// failure means. Every branch either moves the message on in the
  /// lifecycle or records a retry attempt — nothing is left in limbo.
  Future<void> _attempt(Message msg) async {
    final attemptNo = msg.retryCount + 1;
    DeliveryFailure? failure;
    var unreached = 0;
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
      await _messages.markSent(msg.id);
    } on GroupSendException catch (e) {
      // MS08: some members were not reached — normal backoff. Persist the
      // id the partial fan-out used so the re-send deduplicates at the
      // members that already got it.
      if ((msg.messageId == null || msg.messageId!.isEmpty) &&
          e.messageIdHex != null) {
        await _messages.setNetworkMessageId(msg.id, e.messageIdHex!);
      }
      await _messages.markRetryAttempt(msg.id);
      failure = DeliveryFailure.groupPartial;
      unreached = e.failedMemberIds.length;
    } on UnknownPeerException catch (e) {
      // Peer OH still unknown — normal backoff, becomes sendable once the
      // peer OH is registered (see redpanda_light_client.dart sendMessage /
      // REDPANDAJ-2DR).
      debugPrint(
        'OutboxService: message ${msg.id} deferred, counterpart mailbox '
        'unknown for channel ${e.channelId}',
      );
      await _messages.markRetryAttempt(msg.id);
      failure = DeliveryFailure.unknownCounterpart;
    } on DepositException catch (e) {
      // MS02b: the node reported why the deposit was rejected.
      if (e.isBadRequest) {
        // Item exceeds the per-item size limit (64 KiB) — re-sending the
        // same payload can never succeed.
        await _messages.markFailed(msg.id);
        failure = DeliveryFailure.tooLarge;
      } else if (e.isQuotaExceeded) {
        // Recipient mailbox full (reject-new): back off harder than for
        // transient network failures.
        await _messages.markRetryAttempt(msg.id, penalty: quotaExceededPenalty);
        failure = DeliveryFailure.mailboxFull;
      } else {
        // e.g. NOT_FOUND (hop limit) — normal backoff, routing may recover.
        await _messages.markRetryAttempt(msg.id);
        failure = DeliveryFailure.depositRejected;
      }
    } catch (_) {
      await _messages.markRetryAttempt(msg.id);
      failure = DeliveryFailure.transport;
    }
    if (!_attemptController.isClosed) {
      _attemptController.add(
        DeliveryAttempt(
          messageRowId: msg.id,
          conversationId: msg.conversationId,
          attempt: attemptNo,
          failure: failure,
          unreachedMembers: unreached,
        ),
      );
    }
  }

  /// Applies routing-layer delivery feedback (MS06): an R-ACK confirms the
  /// message reached the recipient's OH mailbox (`routed`); HANDLE_EXPIRED,
  /// MAILBOX_FULL or a timeout re-queue the message for a retry over fresh
  /// hops (the node scorer already penalized the old ones on timeout).
  ///
  /// T112: called from `MessageSyncService`'s persistence chain, which owns
  /// the subscription — but the transition itself belongs here, with the
  /// rest of the delivery lifecycle.
  Future<void> onRoutingAck(RoutingAckUpdate update) async {
    // MS08 (Decision 13): group deliveries ack per member — aggregate to
    // `routed` only once every other member's mailbox confirmed.
    final memberIdHex = update.memberIdHex;
    if (memberIdHex != null) {
      if (update.timedOut || update.status != RoutingAck.statusStored) {
        await _messages.requeueSentByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        return;
      }
      await _groups.markReceipt(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        memberId: memberIdHex,
        routed: true,
      );
      final group = await _groups.getGroup(update.channelId);
      if (group == null) return;
      final complete = await _groups.allMembersConfirmed(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        ownMemberId: group.myMemberId,
        delivered: false,
      );
      if (complete) {
        await _messages.markRoutedByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
      }
      return;
    }

    if (update.timedOut) {
      debugPrint(
        'OutboxService: no R-ACK for ${update.messageIdHex} — '
        're-queueing for fresh hops',
      );
      await _messages.requeueSentByNetworkId(
        update.channelId,
        update.messageIdHex,
      );
      return;
    }
    switch (update.status) {
      case RoutingAck.statusStored:
        await _messages.markRoutedByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        break;
      case RoutingAck.statusMailboxFull:
        // Reject-new (MS02b): retrying immediately cannot succeed; the
        // normal backoff applies via the re-queue.
        debugPrint(
          'OutboxService: recipient mailbox full for ${update.messageIdHex}',
        );
        await _messages.requeueSentByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        break;
      case RoutingAck.statusHandleExpired:
      case RoutingAck.statusRejected:
      default:
        debugPrint(
          'OutboxService: deposit failed for ${update.messageIdHex} '
          '(status ${update.status})',
        );
        await _messages.requeueSentByNetworkId(
          update.channelId,
          update.messageIdHex,
        );
        break;
    }
  }

  /// Applies an application-layer delivery confirmation (Channel-ACK, MS06).
  Future<void> onChannelAck(ChannelAckUpdate update) async {
    // MS08 (Decision 13): group acks aggregate per member — `delivered`
    // only once ALL other members confirmed. Acks are broadcast, so this
    // also fires for messages we merely received; those rows are excluded
    // by markDeliveredByNetworkId (status `received`).
    final memberIdHex = update.memberIdHex;
    if (memberIdHex != null) {
      await _groups.markReceipt(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        memberId: memberIdHex,
        routed: true,
        delivered: true,
      );
      final group = await _groups.getGroup(update.channelId);
      if (group == null) return;
      final complete = await _groups.allMembersConfirmed(
        conversationId: update.channelId,
        messageId: update.messageIdHex,
        ownMemberId: group.myMemberId,
        delivered: true,
      );
      if (!complete) return;
    }
    await _messages.markDeliveredByNetworkId(
      update.channelId,
      update.messageIdHex,
    );
  }
}

final outboxServiceProvider = Provider<OutboxService>((ref) {
  return OutboxService(
    ref.watch(messageRepositoryProvider),
    ref.watch(redPandaClientProvider),
    ref.watch(groupRepositoryProvider),
  );
});

/// Delivery attempts made by the outbox; the chat UI surfaces the ones the
/// user just triggered.
final deliveryAttemptProvider = StreamProvider<DeliveryAttempt>((ref) {
  return ref.watch(outboxServiceProvider).attempts;
});
