import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/router.dart';
import 'package:redpanda/services/field_logging.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/send_retry_queue.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // T17: restore the opt-in logcat sink before the client's first logs.
  try {
    await FieldLogging.init();
  } catch (e) {
    debugPrint('Failed to restore field logging setting: $e');
  }
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
    // Messages handed to the network but not R-ACKed before the last
    // shutdown can never be confirmed (ack tags are in-memory only) —
    // re-queue them so the retry queue delivers them again.
    unawaited(
      ref
          .read(messageRepositoryProvider)
          .requeueStuckSent()
          .then((count) {
            if (count > 0) {
              debugPrint('Re-queued $count stuck sent message(s) on startup');
            }
          })
          .catchError((Object e) {
            debugPrint('Failed to re-queue stuck messages: $e');
          }),
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
