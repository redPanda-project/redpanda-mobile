import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in field-test logging (T17): routes [RpLog] info lines to the device
/// log (logcat) so release builds can be diagnosed via `adb logcat`.
///
/// Privacy boundary: only [LogLevel.info] is ever printed. [LogLevel.debug]
/// lines (OH ids, peer addresses, payload sizes) are suppressed by RpLog's
/// default threshold and additionally filtered here — enabling field logging
/// never exposes them. The worker isolate forwards only info lines too (see
/// `_isolateEntryPoint` in the light client).
///
/// The default sink (`dart:developer.log`) is a no-op in release AOT, which
/// left field tests diagnostically blind. The toggle persists across app
/// restarts so a field test does not have to re-enable it after every
/// launch — the exact scenario under investigation.
class FieldLogging {
  FieldLogging._();

  static const String prefsKey = 'field_logging_enabled';

  static void Function(String message, LogLevel level)? _defaultSink;

  static bool _enabled = false;

  /// Whether the logcat sink is currently installed.
  static bool get enabled => _enabled;

  /// Restores the persisted toggle. Call once at startup, before the
  /// network client emits its first logs.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefsKey) ?? false) {
      _install();
    }
  }

  /// Enables or disables the logcat sink and persists the choice.
  static Future<void> setEnabled(bool value) async {
    if (value) {
      _install();
    } else {
      _uninstall();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, value);
  }

  static void _install() {
    if (_enabled) return;
    _defaultSink = RpLog.sink;
    RpLog.sink = (message, level) {
      // debugPrint reaches logcat in release builds (unlike
      // dart:developer.log) and throttles to avoid dropped lines.
      if (level == LogLevel.info) {
        debugPrint('[redpanda] $message');
      }
    };
    _enabled = true;
    RpLog.info('Field logging enabled');
  }

  static void _uninstall() {
    if (!_enabled) return;
    RpLog.info('Field logging disabled');
    RpLog.sink = _defaultSink!;
    _defaultSink = null;
    _enabled = false;
  }
}

/// UI state for the field-logging toggle.
class FieldLoggingNotifier extends Notifier<bool> {
  @override
  bool build() => FieldLogging.enabled;

  Future<void> setEnabled(bool value) async {
    await FieldLogging.setEnabled(value);
    state = FieldLogging.enabled;
  }
}

final fieldLoggingProvider = NotifierProvider<FieldLoggingNotifier, bool>(
  FieldLoggingNotifier.new,
);
