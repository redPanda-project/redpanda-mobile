import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda/shared/widgets/connection_status_badge.dart';
import 'package:uuid/uuid.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(channelsStreamProvider);

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
                  child: Text(channel.username[0].toUpperCase()),
                ),
                title: Text(channel.username),
                subtitle: Text(
                  channel.isOnline == true ? 'Online' : 'Last seen recently',
                ),
                onTap: () {
                  context.push('/chat/${channel.uuid}');
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Error: $err")),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addMockChannel(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addMockChannel(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final mockNames = ["Alice", "Bob", "Charlie", "David", "Eve"];
    final name = mockNames[DateTime.now().second % mockNames.length];

    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            uuid: const Uuid().v4(),
            username: "$name ${DateTime.now().minute}",
            privateKey: const Value("MOCK-PRIVATE-KEY-12345"), // Mock data
            lastSeen: Value(DateTime.now()),
            isOnline: const Value(true),
          ),
        );
  }
}

// Simple stream provider for channels
final channelsStreamProvider = StreamProvider<List<Channel>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.channels).watch();
});
