import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart'
    show GroupMemberInfo;

/// Member list plus admin controls (rename / remove members / leave) for
/// one group (MS08).
class GroupInfoScreen extends ConsumerWidget {
  final String groupId;

  const GroupInfoScreen({super.key, required this.groupId});

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final group = await ref.read(groupRepositoryProvider).getGroup(groupId);
    if (group == null || !context.mounted) return;
    final controller = TextEditingController(text: group.label);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == group.label) return;
    try {
      await ref.read(groupServiceProvider).renameGroup(groupId, newName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
    }
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    String memberId,
    String displayName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $displayName?'),
        content: const Text(
          'The group key is rotated — the removed member cannot read new '
          'messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(groupServiceProvider).removeMember(groupId, memberId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text(
          'The group and its messages are removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(groupServiceProvider).leaveGroup(groupId);
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final groupsAsync = ref.watch(groupsProvider);
    final group = groupsAsync.value
        ?.where((g) => g.groupId == groupId)
        .firstOrNull;
    final isAdmin = group?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.label ?? 'Group'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _rename(context, ref),
            ),
        ],
      ),
      body: membersAsync.when(
        data: (members) => ListView(
          children: [
            if (group != null)
              ListTile(
                leading: const Icon(Icons.key),
                title: Text('Key epoch ${group.keyEpoch}'),
                subtitle: Text(
                  group.keyEpoch == 0
                      ? 'Waiting for the group key…'
                      : '${members.length} member(s)',
                ),
              ),
            const Divider(),
            for (final member in members)
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    member.displayName.isNotEmpty
                        ? member.displayName[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(
                  member.memberId == group?.myMemberId
                      ? '${member.displayName} (you)'
                      : member.displayName,
                ),
                subtitle: Text(
                  member.role == GroupMemberInfo.roleAdmin ? 'Admin' : 'Member',
                ),
                trailing:
                    isAdmin &&
                        member.memberId != group?.myMemberId &&
                        member.role != GroupMemberInfo.roleAdmin
                    ? IconButton(
                        icon: const Icon(Icons.person_remove),
                        onPressed: () => _removeMember(
                          context,
                          ref,
                          member.memberId,
                          member.displayName,
                        ),
                      )
                    : null,
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Leave group',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => _leave(context, ref),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
