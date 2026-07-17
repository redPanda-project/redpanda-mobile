import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the Android foreground service that keeps the app process (and
/// with it the network isolate's TCP connections) alive in the background
/// (T16). No-op on every other platform.
///
/// The service runs whenever the user has at least one channel — reception
/// is the app's core promise and there is no push fallback. It stops when
/// the last channel is deleted, so a fresh install shows no notification.
class ForegroundReceptionService {
  static const MethodChannel _channel = MethodChannel(
    'redpanda/foreground_service',
  );

  final bool _isAndroid;
  bool _running = false;

  /// [isAndroid] is overridable for tests; defaults to the real platform.
  ForegroundReceptionService({bool? isAndroid})
    : _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Whether the service was requested to run (last successful call).
  @visibleForTesting
  bool get running => _running;

  /// Starts or stops the service to match [shouldRun]. Idempotent; failures
  /// are logged and swallowed — background reception is best-effort and must
  /// never break the app.
  Future<void> setEnabled(bool shouldRun) async {
    if (!_isAndroid || shouldRun == _running) return;
    try {
      await _channel.invokeMethod<bool>(shouldRun ? 'start' : 'stop');
      _running = shouldRun;
    } on PlatformException catch (e) {
      debugPrint('ForegroundReceptionService: ${e.code}: ${e.message}');
    } on MissingPluginException {
      // Platform side not available (e.g. tests without the activity).
      debugPrint('ForegroundReceptionService: platform channel unavailable');
    }
  }
}
