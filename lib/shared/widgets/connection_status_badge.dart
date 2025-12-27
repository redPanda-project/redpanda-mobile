import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

class ConnectionStatusBadge extends ConsumerWidget {
  const ConnectionStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider);
    final countAsync = ref.watch(peerCountProvider);

    final count = countAsync.value ?? 0;

    return statusAsync.when(
      data: (status) {
        Color color;
        IconData icon;
        String tooltip;

        switch (status) {
          case ConnectionStatus.connected:
            color = Colors.greenAccent;
            icon = Icons.cloud_done;
            tooltip = "Connected to RedPanda Network ($count peers)";
            break;
          case ConnectionStatus.connecting:
            color = Colors.orangeAccent;
            icon = Icons.cloud_sync;
            tooltip = "Connecting...";
            break;
          case ConnectionStatus.offline:
          case ConnectionStatus.disconnected:
            color = Colors.grey;
            icon = Icons.cloud_off;
            tooltip = "Offline";
            break;
        }

        return Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(
              icon: Icon(icon, color: color),
              tooltip: tooltip,
              onPressed: () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(tooltip)));
              },
            ),
            if (status == ConnectionStatus.connected && count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 14,
                    minHeight: 14,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const Icon(Icons.error, color: Colors.red),
    );
  }
}
