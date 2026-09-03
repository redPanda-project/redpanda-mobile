import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/screens/chat/share_qr_dialog.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda/shared/widgets/glass_backdrop.dart';
import 'package:redpanda/shared/widgets/glass_surface.dart';

/// Floating, blurred top bar (glass chrome): the message list scrolls
/// beneath it (`extendBodyBehindAppBar`) instead of sitting under a flat
/// opaque Material app bar.
class _GlassChatTopBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget> actions;

  const _GlassChatTopBar({required this.title, required this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(child: title),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating glass capsule replacing the flat, bordered compose bar.
class _GlassComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _GlassComposer({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(999),
        padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: "Type a message...",
                  filled: false,
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.send, color: scheme.onPrimary),
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  final String peerUuid;

  const ChatScreen({super.key, required this.peerUuid});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  /// T112: the composer ENQUEUES, it does not send. Handing the message to
  /// the network — with the retry cap, the backoff and one policy per
  /// failure — is the outbox's job; this method used to be the second,
  /// slightly different implementation of it (no retry cap, no
  /// QUOTA_EXCEEDED penalty, its own exception handling).
  void _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    _messageController.clear();

    final db = ref.read(dbProvider);

    // Get current user (assumed singleton for now)
    final currentUser = await db.select(db.users).getSingleOrNull();
    if (currentUser == null) return;

    await ref
        .read(outboxServiceProvider)
        .enqueue(
          conversationId: widget.peerUuid,
          senderId: currentUser.uuid,
          content: content,
        );
  }

  /// Snackbar text for a failed FIRST attempt, i.e. the send the user just
  /// triggered from this screen (later retries are silent, as before).
  /// Null means "say nothing" — a transport failure is what the pending
  /// clock icon and the retry queue are for.
  static String? _failureMessage(DeliveryAttempt attempt) {
    switch (attempt.failure) {
      case DeliveryFailure.groupPartial:
        return '${attempt.unreachedMembers} member(s) not reached yet — '
            'will retry.';
      case DeliveryFailure.tooLarge:
        return 'Message too large to deliver.';
      case DeliveryFailure.mailboxFull:
        return "Recipient's mailbox is full — will retry later.";
      case DeliveryFailure.depositRejected:
        return 'Message could not be delivered yet — will retry later.';
      case DeliveryFailure.unknownCounterpart:
        return 'Recipient not reachable yet — will retry automatically.';
      case DeliveryFailure.transport:
      case null:
        return null;
    }
  }

  /// Human-readable delivery state for the details sheet.
  static String _statusLabel(int status) {
    switch (status) {
      case MessageStatus.pending:
        return 'Waiting to send — retries automatically';
      case MessageStatus.sent:
        return 'Handed to the network, waiting for routing confirmation';
      case MessageStatus.routed:
        return "Stored in the recipient's mailbox";
      case MessageStatus.delivered:
        return "Delivered to the recipient's device";
      case MessageStatus.failed:
        return 'Delivery failed after several attempts';
      default:
        return 'Unknown';
    }
  }

  /// Bottom sheet with the delivery state of an own outgoing message:
  /// status, attempt count, next automatic retry, and a manual "send again"
  /// action for messages the queue has not confirmed yet.
  void _showDeliveryDetails(Message msg) {
    final canRetry =
        msg.status == MessageStatus.pending ||
        msg.status == MessageStatus.failed;
    final nextAttempt =
        msg.status == MessageStatus.pending && msg.lastRetryAt != null
        ? msg.lastRetryAt!.add(OutboxService.backoffFor(msg.retryCount))
        : null;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statusIcon(msg.status) ?? const SizedBox.shrink(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusLabel(msg.status),
                      style: Theme.of(sheetContext).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Sent: ${msg.timestamp}'),
              if (msg.retryCount > 0) Text('Attempts: ${msg.retryCount + 1}'),
              if (msg.lastRetryAt != null)
                Text('Last attempt: ${msg.lastRetryAt}'),
              if (nextAttempt != null)
                Text(
                  'Next automatic attempt: '
                  '${nextAttempt.isBefore(DateTime.now()) ? 'due now' : nextAttempt}',
                ),
              if (canRetry) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Send again now'),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _retryNow(msg.id);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retryNow(int messageRowId) async {
    // The details sheet decides whether to offer "send again" from a
    // SNAPSHOT of the row; an ACK can land between rendering that button and
    // the tap, in which case the outbox refuses to re-queue a message the
    // recipient already has. Say so instead of claiming a send.
    final requeued = await ref
        .read(outboxServiceProvider)
        .retryNow(messageRowId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requeued
                ? 'Sending again…'
                : 'Already confirmed — nothing to send again.',
          ),
        ),
      );
    }
  }

  /// Shared bubble body for both the solid (own) and glass (incoming)
  /// message containers, so the two decorations wrap identical content.
  Widget _bubbleContent(
    BuildContext context,
    String? senderName,
    Message msg,
    Widget? statusIcon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (senderName != null)
          Text(
            senderName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(child: Text(msg.content)),
            if (statusIcon != null) ...[const SizedBox(width: 6), statusIcon],
          ],
        ),
      ],
    );
  }

  /// Status icon for own outgoing messages (MS06 lifecycle: pending → sent
  /// → routed (R-ACK) → delivered (Channel-ACK), or failed).
  Widget? _statusIcon(int status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 14, color: Colors.grey);
      case MessageStatus.sent:
        return const Icon(Icons.arrow_upward, size: 14, color: Colors.grey);
      case MessageStatus.routed:
        return const Icon(Icons.check, size: 14, color: Colors.grey);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      case MessageStatus.failed:
        return const Icon(Icons.close, size: 14, color: Colors.red);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch messages for this conversation
    final messagesAsync = ref.watch(messagesStreamProvider(widget.peerUuid));
    final channelAsync = ref.watch(channelProvider(widget.peerUuid));

    // MS08: this conversation may be a group instead of a 1:1 channel.
    final group = ref
        .watch(groupsProvider)
        .value
        ?.where((g) => g.groupId == widget.peerUuid)
        .firstOrNull;
    final groupMembers = group != null
        ? ref.watch(groupMembersProvider(widget.peerUuid)).value ?? const []
        : const <GroupMemberRow>[];
    final memberNames = {
      for (final member in groupMembers) member.memberId: member.displayName,
    };

    // Warn when the Full Node evicted messages from our mailbox.
    ref.listen(mailboxOverflowProvider, (_, next) {
      final update = next.value;
      if (update == null) return;
      if (update.channelId != null && update.channelId != widget.peerUuid) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some older messages may have been lost (mailbox full).',
          ),
        ),
      );
    });

    // T112: the outbox reports what became of the message the user just
    // sent. Only the FIRST attempt of a message of THIS conversation is
    // surfaced — that is exactly the attempt the composer used to make
    // inline and report on; the queue's later retries stay silent.
    ref.listen(deliveryAttemptProvider, (_, next) {
      final attempt = next.value;
      if (attempt == null) return;
      if (attempt.conversationId != widget.peerUuid) return;
      if (attempt.attempt != 1 || attempt.succeeded) return;
      final message = _failureMessage(attempt);
      if (message == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });

    // T111: no network orchestration here. `build()` used to re-register the
    // channel's keys on every rebuild — with a SUBSET of the arguments (no
    // session tags, no pending RGB, no display name), which the worker-respawn
    // projection then cached as the channel's whole state — and to trigger the
    // T42 mailbox top-up. Channel state now has exactly one restore entry
    // point (`MessageSyncService.registerChannel`, called on startup and when
    // a channel is created/joined), and the worker owns its own mailbox
    // redundancy in its poll cycle.

    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _GlassChatTopBar(
        title: group != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(group.label),
                  Text(
                    group.keyEpoch == 0
                        ? 'Waiting for the group key…'
                        : '${groupMembers.length} members',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              )
            : channelAsync.when(
                data: (channel) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(channel?.label ?? "Unknown"),
                    const Text(
                      "Private Channel",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                loading: () => const Text("Loading..."),
                error: (_, _) => const Text("Chat"),
              ),
        actions: [
          if (group != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => context.push('/groups/${widget.peerUuid}/info'),
            )
          else
            IconButton(
              icon: const Icon(Icons.monitor_heart_outlined),
              tooltip: 'Channel status',
              onPressed: () =>
                  context.push('/channels/${widget.peerUuid}/status'),
            ),
          channelAsync.when(
            data: (channel) {
              if (channel == null) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.qr_code),
                onPressed: () {
                  // QR v4 (T44): the code carries only the 32-byte channel
                  // secret; the counterpart derives k_enc, the identity and the
                  // rendezvous keys from it, and discovers our OH via the
                  // rendezvous DHT record (no OH is embedded in the QR).
                  final jsonString = jsonEncode(<String, dynamic>{
                    'v': 4,
                    'l': channel.label,
                    'sk': channel.channelSecret,
                  });

                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    builder: (context) => ShareChannelDialog(
                      channelName: channel.label,
                      qrData: jsonString,
                    ),
                  );
                },
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: GlassBackdrop(
        child: Stack(
          children: [
            messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text("Say hi!"));
                }
                return ListView.builder(
                  reverse:
                      true, // Show newest at bottom (requires list to be reversed order)
                  padding: EdgeInsets.fromLTRB(0, topInset + 76, 0, 88),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    // MS08: in groups the sender is a member id, so "mine"
                    // is decided by the status (incoming rows are always
                    // `received`); 1:1 keeps the legacy heuristic.
                    final isMe = group != null
                        ? msg.status != MessageStatus.received
                        : msg.conversationId == widget.peerUuid &&
                              msg.senderId != widget.peerUuid;

                    final statusIcon = isMe ? _statusIcon(msg.status) : null;
                    // MS08: authenticated sender name for group messages.
                    final senderName = !isMe && msg.senderMemberId != null
                        ? memberNames[msg.senderMemberId] ?? 'Unknown member'
                        : null;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: isMe ? () => _showDeliveryDetails(msg) : null,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: isMe
                              ? BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(16),
                                )
                              : null,
                          padding: isMe
                              ? const EdgeInsets.all(12)
                              : EdgeInsets.zero,
                          child: isMe
                              ? _bubbleContent(
                                  context,
                                  senderName,
                                  msg,
                                  statusIcon,
                                )
                              : GlassSurface(
                                  borderRadius: BorderRadius.circular(16),
                                  padding: const EdgeInsets.all(12),
                                  blurSigma: 16,
                                  tint: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  child: _bubbleContent(
                                    context,
                                    senderName,
                                    msg,
                                    statusIcon,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text("Error: $e")),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: _GlassComposer(
                controller: _messageController,
                onSend: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final messagesStreamProvider = StreamProvider.family<List<Message>, String>((
  ref,
  conversationId,
) {
  final db = ref.watch(dbProvider);
  return (db.select(db.messages)
        ..where((t) => t.conversationId.equals(conversationId))
        ..orderBy([
          (t) => drift.OrderingTerm(
            expression: t.timestamp,
            mode: drift.OrderingMode.desc,
          ),
        ]))
      .watch();
});

final channelProvider = FutureProvider.family<Channel?, String>((
  ref,
  uuid,
) async {
  final db = ref.watch(dbProvider);
  return (db.select(
    db.channels,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
});
