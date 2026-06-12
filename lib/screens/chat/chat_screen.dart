import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/screens/chat/share_qr_dialog.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart'
    show DepositException;

class ChatScreen extends ConsumerStatefulWidget {
  final String peerUuid;

  const ChatScreen({super.key, required this.peerUuid});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();

  void _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    _messageController.clear();

    final db = ref.read(dbProvider);

    // Get current user (assumed singleton for now)
    final currentUser = await db.select(db.users).getSingleOrNull();
    if (currentUser == null) return;

    final messages = ref.read(messageRepositoryProvider);

    // Insert message locally with pending status
    final rowId = await messages.insertOutgoing(
      conversationId: widget.peerUuid,
      senderId: currentUser.uuid,
      content: content,
    );

    // Send via network. On failure the message stays pending and the
    // SendRetryQueue re-sends it with backoff, reusing the same network
    // message id so retries deduplicate at the receiver. MS02b: the node now
    // reports deposit rejections (FlaschenpostPutResponse) — surface those to
    // the user, analogous to the mailbox-overflow warning.
    try {
      final usedId = await ref
          .read(redPandaClientProvider)
          .sendMessage(widget.peerUuid, content);
      await messages.setNetworkMessageId(rowId, usedId);
      await messages.updateMessageStatus(rowId, MessageStatus.sent);
    } on DepositException catch (e) {
      if (e.isBadRequest) {
        // Over the per-item size limit — retrying can never succeed.
        await messages.updateMessageStatus(rowId, MessageStatus.failed);
      } else {
        await messages.markRetryAttempt(rowId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.isBadRequest
                  ? 'Message too large to deliver.'
                  : e.isQuotaExceeded
                  ? "Recipient's mailbox is full — will retry later."
                  : 'Message could not be delivered yet — will retry later.',
            ),
          ),
        );
      }
    } catch (_) {
      await messages.markRetryAttempt(rowId);
    }
  }

  /// Status icon for own outgoing messages (MS02: pending/sent/failed).
  Widget? _statusIcon(int status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 14, color: Colors.grey);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.grey);
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

    // Register channel encryption keys when channel data is available
    channelAsync.whenData((channel) {
      if (channel != null) {
        final client = ref.read(redPandaClientProvider);
        final encKey = HEX.decode(channel.encryptionKey);
        final peerOhId = channel.peerOhId != null
            ? HEX.decode(channel.peerOhId!)
            : null;
        client.addChannelKeys(
          channel.uuid,
          encKey,
          peerOhId: peerOhId,
          // The creator is the device holding the channel auth private key;
          // a device that joined via QR code holds only the public key.
          isChannelCreator: channel.authPrivateKey != null,
          ratchetState: channel.ratchetState,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: channelAsync.when(
          data: (channel) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(channel?.label ?? "Unknown"),
              const Text(
                "Private Channel",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
            ],
          ),
          loading: () => const Text("Loading..."),
          error: (_, _) => const Text("Chat"),
        ),
        actions: [
          channelAsync.when(
            data: (channel) {
              if (channel == null) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.qr_code),
                onPressed: () async {
                  // QR v3 (MS03): only K_enc + public material — the channel
                  // auth private key never leaves this device.
                  final map = <String, dynamic>{
                    'l': channel.label,
                    'k_enc': channel.encryptionKey,
                    'k_auth_pub': channel.authPublicKey,
                  };

                  // Embed our OWN outbound handle so the scanning peer
                  // knows where to deposit messages for us. Registers one
                  // on the fly if we don't have a valid OH yet.
                  final ownDescriptor = await ref
                      .read(outboundHandleRepositoryProvider)
                      .ensureOwnDescriptor(
                        ref.read(redPandaClientProvider),
                        channel.uuid,
                      );

                  if (ownDescriptor != null) {
                    map['oh'] = ownDescriptor.toJsonMap();
                  }
                  map['v'] = 3;

                  final jsonString = jsonEncode(map);

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
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text("Say hi!"));
                }
                return ListView.builder(
                  reverse:
                      true, // Show newest at bottom (requires list to be reversed order)
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe =
                        msg.conversationId == widget.peerUuid &&
                        msg.senderId != widget.peerUuid;
                    // Note: Logic above is a bit simplified. Usually check if senderId == myUuid.
                    // But here, if senderId != peerUuid, assume it's me.

                    final statusIcon = isMe ? _statusIcon(msg.status) : null;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(child: Text(msg.content)),
                            if (statusIcon != null) ...[
                              const SizedBox(width: 6),
                              statusIcon,
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text("Error: $e")),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
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
