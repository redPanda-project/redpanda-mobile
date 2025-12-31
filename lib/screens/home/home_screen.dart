import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/shared/widgets/connection_status_badge.dart';
// import 'package:redpanda/database/database.dart'; // Temporarily unused

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // using channelsProvider from channel_repository.dart
    final channelsAsync = ref.watch(channelsProvider);

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
          if (channels.isEmpty) {
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
          return ListView.builder(
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(channel.label[0].toUpperCase()),
                ),
                title: Text(channel.label),
                subtitle: const Text(
                  'Private Channel', // TODO: Add status
                ),
                onTap: () {
                  context.push('/chat/${channel.id}');
                },
              );
            },
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
