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

  /// The row's backoff step at attempt time: `retryCount + 1`.
  ///
  /// NOT a count of network attempts — `markRetryAttempt` may advance
  /// `retryCount` by more than one (the QUOTA_EXCEEDED penalty adds
  /// [OutboxService.quotaExceededPenalty]), so the step after a full mailbox
  /// jumps from 1 to 5. What it does say reliably is `attempt == 1`: the
  /// very first attempt of a message, or the first after the user reset it
  /// with [OutboxService.retryNow]. That is the one the composer reports.
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
/// T164: two signals from the network client cut a backoff window short —
/// [onCounterpartOhUpdate] (the partner's mailbox became known: the
/// channel's pending messages go out at once) and a negative R-ACK or R-ACK
/// timeout in [onRoutingAck] (a 1:1 message is re-sent at once, at most
/// [maxImmediateAckRetries] times). Both still count every attempt against
/// [maxRetries].
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

  /// T164: how many times ONE 1:1 message may be re-sent immediately after a
  /// negative R-ACK (HANDLE_EXPIRED, REJECTED, unknown status) or an R-ACK
  /// timeout, per process. Beyond that the re-queue falls back to the normal
  /// [backoffFor] window — this is what keeps "send, negative R-ACK, send
  /// again at once" from becoming a send loop: a node that rejects in
  /// milliseconds would otherwise burn all [maxRetries] attempts within
  /// seconds and fail a message that the old schedule kept trying for ~3 h.
  /// Two is a judgement call, not a measurement: the testnet losses (lab
  /// 2026-11-22) were single sends whose re-send takes a different route
  /// (the reply block is single-use), so one or two fresh routes should
  /// cover the transient case; a third consecutive negative R-ACK points at
  /// persistent trouble, where the schedule's spacing is what matters.
  static const int maxImmediateAckRetries = 2;

  Timer? _timer;
  bool _passInProgress = false;
  Future<void>? _passFuture;
  bool _rerunRequested = false;
  bool _rerunIgnoresBackoff = false;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  /// T164: conversations whose pending messages the next pass attempts
  /// regardless of their backoff window (the counterpart's mailbox became
  /// known). Drained by [_pass]; a request made while a pass runs stays here
  /// for the rerun.
  final Set<String> _flushConversations = {};

  /// T164: (conversation id, network message id) of messages the next pass
  /// attempts regardless of their backoff window (negative R-ACK / timeout).
  final Set<(String, String)> _flushMessages = {};

  /// T164: immediate re-sends already granted per (conversation id, network
  /// message id) of a 1:1 message — the [maxImmediateAckRetries] budget. In
  /// memory, per process. Dropped once the message is done (`routed`,
  /// `delivered`, `failed`) or the user resets it ([retryNow]). Group
  /// messages never get an entry (see [onRoutingAck]).
  final Map<(String, String), int> _immediateAckRetries = {};
  ConnectionStatus? _lastSeenStatus;

  /// Set by the first [start]: the next pass begins with
  /// [recoverAfterRestart]. Running the recovery inside the pass (instead of
  /// next to it) serializes it with the first send attempts, so it can never
  /// flip a row back to `pending` that this process has just sent. Cleared
  /// only once the recovery succeeded; until then no pass sends anything.
  bool _started = false;
  bool _recoveryDue = false;
  bool _disposed = false;
  final _attemptController = StreamController<DeliveryAttempt>.broadcast();

  OutboxService(this._messages, this._client, this._groups);

  /// Number of messages this outbox keeps immediate-retry bookkeeping for
  /// (T164 review L2: must not grow with every message ever sent).
  @visibleForTesting
  int get trackedAckStates => _immediateAckRetries.length;

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

  /// Starts the schedule. The first call also queues [recoverAfterRestart]
  /// ahead of the first pass (TD137) — this is the process start. Not when a
  /// pass already ran: rows it sent carry live ack tags and must stay `sent`.
  /// A no-op after [dispose].
  void start() {
    if (_disposed) return;
    if (!_started) {
      _started = true;
      _recoveryDue = _passFuture == null;
    }
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

  /// Stops the schedule and releases the attempt stream. A pass still in
  /// flight ends after its current attempt and runs no rerun; the returned
  /// future waits for that, so a caller that awaits it can close the message
  /// repository and the network client afterwards. (A torn-down provider
  /// scope does not await it — the early end of the pass is what keeps it
  /// off a closed database there.)
  Future<void> dispose() async {
    _disposed = true;
    stop();
    _flushConversations.clear();
    _flushMessages.clear();
    try {
      await settled;
    } catch (e) {
      debugPrint('OutboxService: pass failed while disposing: $e');
    }
    await _attemptController.close();
  }

  /// Re-queues every message the previous process left `sent` (TD137).
  ///
  /// Ack tags live only in memory, so a message handed to the network but
  /// not R-ACKed before the last shutdown can never be confirmed or timed
  /// out — it would stay `sent` forever. The re-send reuses the stable
  /// network message id, so receivers that already got it deduplicate it.
  /// Runs once, as the first step of the first pass after [start]; returns
  /// the number of re-queued messages.
  @visibleForTesting
  Future<int> recoverAfterRestart() async {
    final count = await _messages.requeueStuckSent();
    if (count > 0) {
      debugPrint('OutboxService: re-queued $count stuck sent message(s)');
    }
    return count;
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

  /// When the backoff window for [msg] ends, i.e. the earliest time the
  /// outbox attempts it again. Null when it has no previous attempt — it is
  /// due immediately. The one place that turns a row's backoff bookkeeping
  /// into a time (TD136): the UI reads this instead of re-deriving it.
  static DateTime? nextAttemptAt(Message msg) =>
      msg.lastRetryAt?.add(backoffFor(msg.retryCount));

  /// True if the backoff window for [msg] has elapsed.
  static bool isDue(Message msg, DateTime now) {
    final next = nextAttemptAt(msg);
    return next == null || !now.isBefore(next);
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
    required String content,
  }) async {
    final rowId = await _messages.insertOutgoing(
      conversationId: conversationId,
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
  ///
  /// Returns false when the message was NOT re-queued because it moved on
  /// while the user was looking at it (an ACK confirmed it) — the caller
  /// must not claim it is sending again.
  Future<bool> retryNow(int messageRowId) async {
    final requeued = await _messages.resetForImmediateRetry(messageRowId);
    if (!requeued) return false;
    // T164 review R8: the user starts the message over — including its
    // immediate re-send budget, like its backoff.
    final row = await _messages.getMessage(messageRowId);
    if (row != null) _forget(row.conversationId, row.messageId);
    unawaited(
      runPass().catchError(
        (Object e) => debugPrint('OutboxService: manual retry failed: $e'),
      ),
    );
    return true;
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
        if (!_rerunRequested || _disposed) break;
        ignore = _rerunIgnoresBackoff;
      }
    } finally {
      _passInProgress = false;
      _rerunRequested = false;
      _rerunIgnoresBackoff = false;
    }
  }

  Future<void> _pass({required bool ignoreBackoff}) async {
    if (_recoveryDue) {
      // A failure aborts the pass BEFORE anything is sent and leaves the
      // recovery due, so the next pass retries it. Sending first and
      // recovering later would re-queue rows this process just sent.
      await recoverAfterRestart();
      _recoveryDue = false;
    }
    // TD002/T51: pull back anything stuck `sent` without an ack tag before
    // looking at the pending set, so a message this sweep just requeued is
    // picked up by the very same pass instead of waiting another tick.
    // T164: take the targeted requests BEFORE reading the pending set — the
    // re-queue that asked for them has already been written, so this pass
    // sees the row. Requests that arrive later stay for the rerun.
    // Removed from the queue only once the pending set was read: a failing
    // read must not swallow a request whose budget is already spent (T164
    // review L1).
    final flushConversations = Set.of(_flushConversations);
    final flushMessages = Set.of(_flushMessages);
    await _messages.requeueStaleSent(olderThan: staleSentThreshold);
    final pending = await _messages.getPendingMessages();
    _flushConversations.removeAll(flushConversations);
    _flushMessages.removeAll(flushMessages);
    final now = DateTime.now();

    for (final msg in pending) {
      if (_disposed) return;
      // The cap holds for every trigger, targeted or not.
      if (msg.retryCount >= maxRetries) {
        await _messages.markFailed(msg.id);
        _forget(msg.conversationId, msg.messageId);
        continue;
      }
      final forced =
          ignoreBackoff ||
          flushConversations.contains(msg.conversationId) ||
          (msg.messageId != null &&
              flushMessages.contains((msg.conversationId, msg.messageId!)));
      if (!forced && !isDue(msg, now)) continue;
      // T164 review L3: the snapshot above may be seconds old by now (an
      // earlier attempt of this pass blocked on the network) — an ACK that
      // confirmed the row meanwhile means there is nothing left to send.
      final current = await _messages.getMessage(msg.id);
      if (current == null || current.status != MessageStatus.pending) {
        continue;
      }
      await _attempt(current);
    }
  }

  /// Drops the T164 bookkeeping of a message that is done.
  void _forget(String conversationId, String? messageIdHex) {
    if (messageIdHex == null || messageIdHex.isEmpty) return;
    _immediateAckRetries.remove((conversationId, messageIdHex));
  }

  /// Kicks a pass that attempts the targeted rows regardless of their
  /// backoff (T164). Never awaited by the caller: the callers sit in
  /// `MessageSyncService`'s persistence chain, which must not block on a
  /// network send. [settled] is how a test waits for it.
  void _kickTargetedPass({String? conversationId, (String, String)? message}) {
    if (_disposed) return;
    if (conversationId != null) _flushConversations.add(conversationId);
    if (message != null) _flushMessages.add(message);
    unawaited(
      runPass().catchError(
        (Object e) => debugPrint('OutboxService: targeted pass failed: $e'),
      ),
    );
  }

  /// T164: the counterpart's mailbox set for [CounterpartOhUpdate.channelId]
  /// changed (first learned via rendezvous, or moved via in-band
  /// `oh_update`). Every pending message of that channel is attempted now
  /// instead of at the end of its backoff window — a message that failed
  /// with [UnknownCounterpartException] is deliverable the moment the
  /// network client knows where to deposit it (testnet lab run 1: mailbox
  /// known at 102 s, first send at 220 s).
  ///
  /// [maxRetries] still applies, and every failed attempt books a retry as
  /// usual. The client emits this only when the set actually changes, so it
  /// cannot drive a loop by itself.
  void onCounterpartOhUpdate(CounterpartOhUpdate update) {
    if (update.descriptors.isEmpty) return;
    _kickTargetedPass(conversationId: update.channelId);
  }

  /// Re-queues a sent message after negative routing feedback and — while
  /// its [maxImmediateAckRetries] budget lasts and [immediate] is set —
  /// attempts it right away over fresh hops (T164). Without budget the
  /// normal backoff from now applies, as before T164. 1:1 messages only.
  Future<void> _requeueAfterNegativeAck(
    RoutingAckUpdate update, {
    required bool immediate,
  }) async {
    final requeued = await _messages.requeueSentByNetworkId(
      update.channelId,
      update.messageIdHex,
    );
    if (!requeued || !immediate) return;
    final key = (update.channelId, update.messageIdHex);
    final granted = _immediateAckRetries[key] ?? 0;
    if (granted >= maxImmediateAckRetries) {
      debugPrint(
        'OutboxService: immediate re-send budget used up for '
        '${update.messageIdHex} — normal backoff',
      );
      return;
    }
    _immediateAckRetries[key] = granted + 1;
    _kickTargetedPass(message: key);
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
    } on UnknownCounterpartException catch (e) {
      // The counterpart's OH is still unknown — normal backoff; the message
      // becomes sendable once it is (see redpanda_light_client.dart sendMessage /
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
        _forget(msg.conversationId, msg.messageId);
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
  /// REJECTED, an unknown status or a timeout re-queue the message and
  /// (T164) re-send it at once over fresh hops — the node scorer already
  /// penalized the old ones on timeout — within [maxImmediateAckRetries];
  /// MAILBOX_FULL re-queues with the normal backoff. The immediate re-send
  /// applies to 1:1 messages only; group messages always take the backoff.
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
        // T164 deliberately stops at 1:1: a group fan-out gets one R-ACK per
        // member, so feedback for an earlier attempt can meet a later one,
        // and the R-ACK does not say which attempt it describes. Telling
        // them apart needs the send time from the client (review round 2);
        // until then a group message keeps the pre-T164 behaviour — re-queue
        // with the normal backoff.
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
      // T164: a timeout is treated like a negative R-ACK. 90 s of silence
      // already exceed the early backoff steps; the hops were scored down,
      // so the re-send takes a fresh route; and if only the R-ACK was lost,
      // the duplicate costs one deposit — the receiver drops it by message
      // id. On the testnet a timeout has so far always meant a lost message.
      debugPrint(
        'OutboxService: no R-ACK for ${update.messageIdHex} — '
        're-queueing for fresh hops',
      );
      await _requeueAfterNegativeAck(update, immediate: true);
      return;
    }
    switch (update.status) {
      case RoutingAck.statusStored:
        _forget(update.channelId, update.messageIdHex);
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
        await _requeueAfterNegativeAck(update, immediate: false);
        break;
      case RoutingAck.statusHandleExpired:
      case RoutingAck.statusRejected:
      default:
        debugPrint(
          'OutboxService: deposit failed for ${update.messageIdHex} '
          '(status ${update.status})',
        );
        // T164: re-send now over fresh hops (bounded by
        // maxImmediateAckRetries) instead of after the backoff window.
        await _requeueAfterNegativeAck(update, immediate: true);
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
    // T164: a delivered 1:1 message is done. (Group messages carry no
    // budget; review round 1 H1 was about resetting it on ONE member's ack.)
    _forget(update.channelId, update.messageIdHex);
    await _messages.markDeliveredByNetworkId(
      update.channelId,
      update.messageIdHex,
    );
  }
}

final outboxServiceProvider = Provider<OutboxService>((ref) {
  final outbox = OutboxService(
    ref.watch(messageRepositoryProvider),
    ref.watch(redPandaClientProvider),
    ref.watch(groupRepositoryProvider),
  );
  // The timer, the connection subscription and the attempt stream outlive
  // nothing: when the scope goes, so do they.
  ref.onDispose(() => unawaited(outbox.dispose()));
  return outbox;
});

/// Delivery attempts made by the outbox; the chat UI surfaces the ones the
/// user just triggered.
final deliveryAttemptProvider = StreamProvider<DeliveryAttempt>((ref) {
  return ref.watch(outboxServiceProvider).attempts;
});
