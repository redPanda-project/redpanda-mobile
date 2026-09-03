import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/services/channel_health.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart' hide Channel;

/// Per-channel transparency page: shows when the important background jobs
/// for this channel last ran (mailbox checks, own-mailbox renewal, send
/// retries) and what the send/receive state is.
class ChannelStatusScreen extends ConsumerWidget {
  final String channelUuid;

  const ChannelStatusScreen({super.key, required this.channelUuid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Periodic rebuild so relative times and countdowns stay current.
    ref.watch(healthTickProvider);

    final now = DateTime.now();
    final channel = ref.watch(channelRowProvider(channelUuid)).value;
    final connection = ref.watch(connectionStatusProvider).value;
    final peerCount = ref.watch(peerCountProvider).value ?? 0;
    final fetchInfo = ref.watch(channelFetchInfoProvider)[channelUuid];
    final ownHandle = ref.watch(ownHandleProvider(channelUuid)).value;
    final stats = ref.watch(conversationStatsProvider(channelUuid)).value;
    final health = ref.watch(channelHealthProvider(channelUuid));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(channel?.label ?? 'Channel'),
            const Text(
              'Channel status',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          _HealthBanner(health: health),
          const _SectionHeader('Network'),
          ListTile(
            leading: Icon(
              connection == ConnectionStatus.connected
                  ? Icons.cloud_done
                  : Icons.cloud_off,
            ),
            title: Text(_connectionLabel(connection)),
            subtitle: Text('$peerCount peer(s) connected'),
          ),
          const _SectionHeader('Receiving (own mailbox)'),
          if (ownHandle == null)
            const ListTile(
              leading: Icon(Icons.markunread_mailbox_outlined),
              title: Text('No own mailbox yet'),
              subtitle: Text(
                'It is registered when you share this channel as a QR code.',
              ),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.markunread_mailbox),
              title: Text('Mailbox on ${ownHandle.serverEndpoint}'),
              subtitle: Text(
                ownHandle.expiresAt.isBefore(now)
                    ? 'Registration EXPIRED ${_relative(ownHandle.expiresAt, now)}'
                    : 'Registration valid for '
                          '${_duration(ownHandle.expiresAt.difference(now))} '
                          '(auto-renewed)',
              ),
            ),
            if (ownHandle.failedOverAt != null)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Mailbox moved (automatic failover)'),
                subtitle: Text(
                  'The previous host node was unreachable — a new mailbox '
                  'was registered ${_relative(ownHandle.failedOverAt!, now)} '
                  'and announced to your contact.',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(
                fetchInfo?.lastOkAt != null
                    ? 'Last checked ${_relative(fetchInfo!.lastOkAt!, now)}'
                    : 'Not checked since app start',
              ),
              subtitle: Text(
                fetchInfo?.lastError != null
                    ? 'Last attempt failed: ${fetchInfo!.lastError}'
                    : 'Checked automatically every 30 seconds',
              ),
            ),
          ],
          const _SectionHeader('Sending (to the recipient)'),
          ListTile(
            leading: Icon(
              channel?.counterpartOhId != null
                  ? Icons.send
                  : Icons.help_outline,
            ),
            title: Text(
              channel?.counterpartOhId != null
                  ? "Recipient's mailbox known"
                  : "Recipient's mailbox unknown",
            ),
            subtitle: Text(
              channel?.counterpartOhId != null
                  ? 'On ${channel!.counterpartOhEndpoint ?? 'unknown node'}'
                  : "Scan the recipient's QR code to enable sending.",
            ),
          ),
          if (stats != null) ...[
            ListTile(
              leading: const Icon(Icons.outbox),
              title: Text(_outboxLabel(stats)),
              subtitle: Text(_outboxDetail(stats, now)),
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: Text(
                stats.lastConfirmedAt != null
                    ? 'Last confirmed delivery '
                          '${_relative(stats.lastConfirmedAt!, now)}'
                    : 'No confirmed delivery yet',
              ),
            ),
            const _SectionHeader('Receiving (messages)'),
            ListTile(
              leading: const Icon(Icons.move_to_inbox),
              title: Text(
                stats.lastReceivedAt != null
                    ? 'Last message received '
                          '${_relative(stats.lastReceivedAt!, now)}'
                    : 'No message received yet',
              ),
            ),
          ],
          const _SectionHeader('Self-test'),
          _LoopbackTile(
            channelUuid: channelUuid,
            hasOwnMailbox: ownHandle != null,
          ),
          ListTile(
            leading: const Icon(Icons.health_and_safety),
            title: const Text('Connection doctor'),
            subtitle: const Text(
              'Run step-by-step checks and see where a problem is.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/channels/$channelUuid/doctor'),
          ),
        ],
      ),
    );
  }

  static String _connectionLabel(ConnectionStatus? status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting…';
      case ConnectionStatus.offline:
        return 'Offline';
      case ConnectionStatus.disconnected:
      case null:
        return 'Disconnected';
    }
  }

  static String _outboxLabel(ConversationStats stats) {
    if (stats.failedCount > 0) {
      return '${stats.failedCount} message(s) failed';
    }
    if (stats.pendingCount > 0) {
      return '${stats.pendingCount} message(s) waiting to be sent';
    }
    if (stats.sentCount > 0) {
      return '${stats.sentCount} message(s) awaiting confirmation';
    }
    return 'Outbox empty';
  }

  static String _outboxDetail(ConversationStats stats, DateTime now) {
    if (stats.failedCount > 0) {
      return 'Open the message in the chat to send it again.';
    }
    final nextRetryAt = stats.nextRetryAt;
    if (stats.pendingCount > 0 && nextRetryAt != null) {
      return nextRetryAt.isBefore(now)
          ? 'Next attempt: any moment'
          : 'Next attempt in ${_duration(nextRetryAt.difference(now))}';
    }
    return 'Everything handed to the network.';
  }

  /// "12 s ago" / "3 min ago" / "2 h ago" / "5 d ago".
  static String _relative(DateTime time, DateTime now) {
    final diff = now.difference(time);
    if (diff.isNegative) return _duration(-diff);
    return '${_duration(diff)} ago';
  }

  static String _duration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 48) return '${d.inHours} h';
    return '${d.inDays} d';
  }
}

/// One-shot loopback self-test (T20): deposits a test message into the
/// channel's OWN mailbox over the full network path (garlic routing included)
/// and reports whether — and how fast — it came back through the regular
/// fetch pipeline. Runs only on demand; there is no periodic self-ping.
class _LoopbackTile extends ConsumerStatefulWidget {
  final String channelUuid;
  final bool hasOwnMailbox;

  const _LoopbackTile({required this.channelUuid, required this.hasOwnMailbox});

  @override
  ConsumerState<_LoopbackTile> createState() => _LoopbackTileState();
}

class _LoopbackTileState extends ConsumerState<_LoopbackTile> {
  bool _running = false;
  LoopbackResult? _result;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
    });
    final client = ref.read(redPandaClientProvider);
    final result = await client.runLoopbackTest(widget.channelUuid);
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasOwnMailbox) {
      return const ListTile(
        leading: Icon(Icons.network_ping),
        title: Text('Loopback test unavailable'),
        subtitle: Text('It needs an own mailbox (see above).'),
      );
    }
    final result = _result;
    final (icon, title, subtitle) = _running
        ? (
            const Icon(Icons.network_ping),
            'Loopback test running…',
            'Sending a test message to this channel\'s own mailbox '
                '(up to 60 s).',
          )
        : result == null
        ? (
            const Icon(Icons.network_ping),
            'Loopback test',
            'Sends a test message to this channel\'s own mailbox over the '
                'network and waits for it to come back.',
          )
        : result.success
        ? (
            const Icon(Icons.check_circle, color: Colors.green),
            'Loopback OK in ${_seconds(result.roundtripMs!)} s',
            'Deposited via ${result.hopCount} relay hop(s), received back '
                'through the regular mailbox check.',
          )
        : (
            const Icon(Icons.error, color: Colors.red),
            'Loopback test failed',
            result.error ?? 'unknown error',
          );
    return ListTile(
      leading: _running
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : icon,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: FilledButton.tonal(
        onPressed: _running ? null : _run,
        child: Text(result == null && !_running ? 'Run' : 'Run again'),
      ),
    );
  }

  static String _seconds(int ms) => (ms / 1000).toStringAsFixed(1);
}

class _HealthBanner extends StatelessWidget {
  final ChannelHealth health;

  const _HealthBanner({required this.health});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (health.level) {
      ChannelHealthLevel.healthy => (
        Colors.green,
        Icons.check_circle,
        'Everything is working',
      ),
      ChannelHealthLevel.degraded => (
        Colors.amber,
        Icons.info,
        'Working with limitations',
      ),
      ChannelHealthLevel.problem => (
        Colors.red,
        Icons.error,
        'Attention needed',
      ),
      ChannelHealthLevel.unknown => (Colors.grey, Icons.help, 'Status unknown'),
    };
    return Container(
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          for (final reason in health.reasons)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Text('• $reason'),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
