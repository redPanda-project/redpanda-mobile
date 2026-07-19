import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/router.dart';
import 'package:redpanda/services/field_logging.dart';
import 'package:redpanda/services/foreground_service.dart';
import 'package:redpanda/services/group_service.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/send_retry_queue.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:sentry/sentry.dart';

/// Public client key for the redpanda-mobile Sentry project (crash reporting
/// only — no tracing, no PII). Pure Dart `sentry` package on purpose: the
/// `sentry_flutter` native plugin (JNI interop since 9.x) destabilized the
/// light client's worker-isolate networking in the emulator E2E gate.
const _sentryDsn =
    'https://193dc757933e3ea94c9b1c7ca51aba5d@o235168.ingest.us.sentry.io/4511756564496384';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // T17: restore the opt-in logcat sink before the client's first logs.
  try {
    await FieldLogging.init();
  } catch (e) {
    debugPrint('Failed to restore field logging setting: $e');
  }
  if (!kReleaseMode) {
    // Debug and profile runs (dev, E2E gate) report crashes locally;
    // keep Sentry to field release builds.
    runApp(const ProviderScope(child: MyApp()));
    return;
  }
  await Sentry.init((options) {
    options.dsn = _sentryDsn;
    options.tracesSampleRate = 0;
    options.sendDefaultPii = false;
  });
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      Sentry.captureException(details.exception, stackTrace: details.stack),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(Sentry.captureException(error, stackTrace: stack));
    return true;
  };
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

    // T16: keep the process (and with it the network isolate) alive in the
    // background on Android once there is at least one channel to receive
    // for; stop when the last channel is gone.
    _channelsSubscription = ref.listenManual(
      channelsProvider,
      fireImmediately: true,
      (_, next) {
        final channels = next.value;
        if (channels == null) return;
        unawaited(_foregroundService.setEnabled(channels.isNotEmpty));
      },
    );

    // Lifecycle listener
    _lifecycleListener = AppLifecycleListener(onStateChange: _onStateChanged);
  }

  final _foregroundService = ForegroundReceptionService();
  ProviderSubscription<AsyncValue<List<Channel>>>? _channelsSubscription;

  late final AppLifecycleListener _lifecycleListener;

  void _onStateChanged(AppLifecycleState state) {
    // T26: onPause/onResume are part of the RedPandaClient facade — the old
    // `is RedPandaLightClient` type check never matched the production
    // isolate client, so lifecycle signals silently never reached the
    // network worker (iOS resume waited for the next poll tick).
    final client = ref.read(redPandaClientProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      client.onPause();
    } else if (state == AppLifecycleState.resumed) {
      client.onResume();
    }
  }

  @override
  void dispose() {
    _channelsSubscription?.close();
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
