import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/services/channel_health.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda/shared/widgets/connection_status_badge.dart';

/// Traffic-light health indicator for one channel tile. Green: everything
/// runs; amber: working with limitations (queued sends, stale mailbox
/// check, missing peer mailbox); red: needs attention. Details on the
/// channel status page (info button in the chat).
class _ChannelHealthDot extends ConsumerWidget {
  final String channelId;

  const _ChannelHealthDot({required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(channelHealthProvider(channelId));
    final color = switch (health.level) {
      ChannelHealthLevel.healthy => Colors.green,
      ChannelHealthLevel.degraded => Colors.amber,
      ChannelHealthLevel.problem => Colors.red,
      ChannelHealthLevel.unknown => Colors.grey,
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // using channelsProvider from channel_repository.dart
    final channelsAsync = ref.watch(channelsProvider);
    final groups = ref.watch(groupsProvider).value ?? const [];
    final invites = ref.watch(groupInvitesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text("RedPanda"),
        actions: [
          const ConnectionStatusBadge(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Settings
            },
          ),
        ],
      ),
      body: channelsAsync.when(
        data: (channels) {
          if (channels.isEmpty && groups.isEmpty && invites.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.perm_contact_calendar_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No channels yet",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          return ListView(
            children: [
              // MS08: pending group invites first — they need a decision.
              for (final invite in invites)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.group_add)),
                  title: Text(invite.groupName),
                  subtitle: const Text('Group invite'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(groupServiceProvider)
                                .acceptInvite(invite.groupId);
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Could not join group: $e'),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => ref
                            .read(groupServiceProvider)
                            .dismissInvite(invite.groupId),
                      ),
                    ],
                  ),
                ),
              for (final group in groups)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    child: const Icon(Icons.group),
                  ),
                  title: Text(group.label),
                  subtitle: Text(
                    group.keyEpoch == 0
                        ? 'Waiting for the group key…'
                        : 'Group',
                  ),
                  onTap: () {
                    context.push('/chat/${group.groupId}');
                  },
                ),
              for (final channel in channels)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Text(channel.label[0].toUpperCase()),
                  ),
                  title: Text(channel.label),
                  subtitle: const Text('Private Channel'),
                  trailing: _ChannelHealthDot(channelId: channel.id),
                  onTap: () {
                    context.push('/chat/${channel.id}');
                  },
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Error: $err")),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: "join_channel",
            onPressed: () => context.push('/channels/join'),
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.small(
            heroTag: "create_group",
            onPressed: () => context.push('/groups/create'),
            child: const Icon(Icons.group_add),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "create_channel",
            onPressed: () => context.push('/channels/create'),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
