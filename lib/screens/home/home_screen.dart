import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/services/channel_health.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda/shared/widgets/connection_status_badge.dart';
import 'package:redpanda/shared/widgets/glass_backdrop.dart';
import 'package:redpanda/shared/widgets/glass_surface.dart';

/// Traffic-light health indicator for one channel tile. Green: everything
/// runs; amber: working with limitations (queued sends, stale mailbox
/// check, missing counterpart mailbox); red: needs attention. Details on the
/// channel status page (info button in the chat).
class _ChannelHealthDot extends ConsumerWidget {
  final String channelId;

  const _ChannelHealthDot({required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(channelHealthProvider(channelId));
    final (color, label) = switch (health.level) {
      ChannelHealthLevel.healthy => (Colors.green, 'Channel healthy'),
      ChannelHealthLevel.degraded => (
        Colors.amber,
        'Channel working with limitations',
      ),
      ChannelHealthLevel.problem => (Colors.red, 'Channel needs attention'),
      ChannelHealthLevel.unknown => (Colors.grey, 'Channel status unknown'),
    };
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Floating, blurred top bar (glass chrome): the channel list scrolls
/// beneath it (`extendBodyBehindAppBar`) instead of sitting under a flat
/// opaque Material app bar.
class _GlassTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassTopBar();

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "RedPanda",
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const ConnectionStatusBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating capsule replacing the old three-FAB stack: one glass pill with
/// the same three actions (join by QR, create group, create channel).
class _GlassActionCapsule extends StatelessWidget {
  const _GlassActionCapsule();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(999),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Join channel',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => context.push('/channels/join'),
            ),
            IconButton(
              tooltip: 'Create group',
              icon: const Icon(Icons.group_add),
              onPressed: () => context.push('/groups/create'),
            ),
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Create channel',
                icon: Icon(Icons.add, color: scheme.onPrimary),
                onPressed: () => context.push('/channels/create'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// T26 (foreground-only reception UX): on iOS there is no push and no
  /// background fetch (deliberate decision, 2026-07-15) — messages arrive
  /// only while the app is open. Say so instead of letting users wonder.
  /// The resume catch-up (client.onResume) makes reopening pull mail
  /// within seconds.
  Widget _platformNotice(BuildContext context) {
    if (kIsWeb || !Platform.isIOS) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Messages are received only while the app is open.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // using channelsProvider from channel_repository.dart
    final channelsAsync = ref.watch(channelsProvider);
    final groups = ref.watch(groupsProvider).value ?? const [];
    final invites = ref.watch(groupInvitesProvider).value ?? const [];
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const _GlassTopBar(),
      body: GlassBackdrop(
        child: channelsAsync.when(
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
              padding: EdgeInsets.fromLTRB(0, topInset + 76, 0, 96),
              children: [
                _platformNotice(context),
                // MS08: pending group invites first — they need a decision.
                for (final invite in invites)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: GlassSurface(
                      borderRadius: BorderRadius.circular(18),
                      padding: EdgeInsets.zero,
                      blurSigma: 16,
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.group_add),
                        ),
                        title: Text(invite.groupName),
                        subtitle: const Text('Group invite'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
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
                    ),
                  ),
                for (final group in groups)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: GlassSurface(
                      borderRadius: BorderRadius.circular(18),
                      padding: EdgeInsets.zero,
                      blurSigma: 16,
                      child: ListTile(
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
                    ),
                  ),
                for (final channel in channels)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: GlassSurface(
                      borderRadius: BorderRadius.circular(18),
                      padding: EdgeInsets.zero,
                      blurSigma: 16,
                      child: ListTile(
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
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text("Error: $err")),
        ),
      ),
      floatingActionButton: const _GlassActionCapsule(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
