import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/router.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/send_retry_queue.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Synchronous connection trigger (KeyPair gen is now fast)
    ref.read(redPandaClientProvider).connect();

    // MS02: persist incoming messages/cursors, restore OHs, retry sends
    final syncService = ref.read(messageSyncServiceProvider);
    syncService.start();
    unawaited(
      syncService.restorePersistedState().catchError(
        (Object e) => debugPrint('Failed to restore persisted OH state: $e'),
      ),
    );

    // MS08: handshake handling + restore persisted groups into the client
    final groupService = ref.read(groupServiceProvider);
    groupService.start();
    unawaited(
      groupService.restorePersistedGroups().catchError(
        (Object e) => debugPrint('Failed to restore persisted groups: $e'),
      ),
    );
    ref.read(sendRetryQueueProvider).start();

    // Lifecycle listener
    _lifecycleListener = AppLifecycleListener(onStateChange: _onStateChanged);
  }

  late final AppLifecycleListener _lifecycleListener;

  void _onStateChanged(AppLifecycleState state) {
    // Only works if client is actually RedPandaLightClient
    final client = ref.read(redPandaClientProvider);
    if (client is RedPandaLightClient) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        client.onPause();
      } else if (state == AppLifecycleState.resumed) {
        client.onResume();
      }
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'RedPanda Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
