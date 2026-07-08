import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Creates a new group (MS08): pick a name plus initial members from the
/// existing 1:1 channels — invites travel over those channels
/// (Decision 8: no QR group invites in v1).
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedChannelIds = {};
  bool _creating = false;

  Future<void> _createGroup(List<Channel> channels) async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedChannelIds.isEmpty || _creating) return;

    setState(() => _creating = true);
    try {
      final selected = [
        for (final channel in channels)
          if (_selectedChannelIds.contains(channel.id)) channel,
      ];
      final groupId = await ref
          .read(groupServiceProvider)
          .createGroup(name, selected);
      if (!mounted) return;
      context.pushReplacement('/chat/$groupId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create group: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(channelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New Group')),
      body: channelsAsync.when(
        data: (channels) {
          // Invites need a peer mailbox to be deposited into.
          final invitable = [
            for (final channel in channels)
              if (channel.peerOhDescriptor != null) channel,
          ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Members (from your channels, max. ${maxGroupMembers - 1})',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              Expanded(
                child: invitable.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No channels with a known mailbox yet — group '
                            'invites travel over existing 1:1 channels.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: invitable.length,
                        itemBuilder: (context, index) {
                          final channel = invitable[index];
                          final selected = _selectedChannelIds.contains(
                            channel.id,
                          );
                          return CheckboxListTile(
                            value: selected,
                            title: Text(channel.label),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  if (_selectedChannelIds.length + 1 <
                                      maxGroupMembers) {
                                    _selectedChannelIds.add(channel.id);
                                  }
                                } else {
                                  _selectedChannelIds.remove(channel.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _creating ? null : () => _createGroup(channels),
                    child: _creating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create group'),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
