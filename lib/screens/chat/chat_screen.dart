import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/screens/chat/share_qr_dialog.dart';
import 'package:redpanda/shared/providers.dart';

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

    // Insert message locally with pending status
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            conversationId: widget.peerUuid,
            senderId: currentUser.uuid,
            content: content,
            timestamp: DateTime.now(),
            status: 0, // MessageStatus.pending
            type: 0, // MessageType.text
          ),
        );

    // Send via network
    try {
      await ref
          .read(redPandaClientProvider)
          .sendMessage(widget.peerUuid, content);
      // TODO: Update message status to sent (1) after confirmation
    } catch (e) {
      // TODO: Update message status to failed (5), show Snackbar
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch messages for this conversation
    final messagesAsync = ref.watch(messagesStreamProvider(widget.peerUuid));
    final channelAsync = ref.watch(channelProvider(widget.peerUuid));

    // Register channel encryption keys when channel data is available
    channelAsync.whenData((channel) {
      if (channel != null) {
        final client = ref.read(redPandaClientProvider);
        final encKey = HEX.decode(channel.encryptionKey);
        final peerOhId = channel.peerOhId != null
            ? HEX.decode(channel.peerOhId!)
            : null;
        client.addChannelKeys(channel.uuid, encKey, peerOhId: peerOhId);
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
                onPressed: () {
                  final map = <String, dynamic>{
                    'l': channel.label,
                    'k_enc': channel.encryptionKey,
                    'k_auth': channel.authenticationKey,
                  };

                  if (channel.peerOhEndpoint != null &&
                      channel.peerOhId != null &&
                      channel.peerOhPublicKey != null) {
                    map['oh'] = {
                      'ep': channel.peerOhEndpoint,
                      'id': channel.peerOhId,
                      'pk': channel.peerOhPublicKey,
                    };
                    map['v'] = 2;
                  } else {
                    map['v'] = 1;
                  }

                  final jsonString = jsonEncode(map);

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
                        child: Text(msg.content),
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
