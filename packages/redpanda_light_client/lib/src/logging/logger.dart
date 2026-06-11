import 'dart:developer' as developer;

/// Minimal severity levels for [RpLog].
enum LogLevel {
  /// Verbose diagnostics that may include privacy-sensitive details such as
  /// OH ids, peer addresses and payload sizes. Suppressed at the default
  /// threshold so these never reach production logs.
  debug,

  /// Normal operational messages, safe to keep at the default threshold.
  info,
}

/// A minimal, injectable logging sink for the light client.
///
/// The default implementation forwards to `dart:developer.log` (a no-op in
/// release AOT unless a debugger/observer is attached, and never written to
/// stdout). Tests and the app can inject their own sink.
///
/// Privacy: [LogLevel.debug] messages are dropped unless [minLevel] is lowered
/// to [LogLevel.debug]. Because the default [minLevel] is [LogLevel.info],
/// OH ids / payload sizes / peer addresses logged via [debug] do **not** appear
/// at the default level — important for a metadata-protection product.
class RpLog {
  RpLog._();

  /// The lowest level that is emitted. Defaults to [LogLevel.info] so
  /// privacy-sensitive [LogLevel.debug] lines are suppressed by default.
  static LogLevel minLevel = LogLevel.info;

  /// The sink that receives formatted lines. Replace in tests or to route to a
  /// custom logger. Defaults to `dart:developer.log` under the 'redpanda' name.
  static void Function(String message, LogLevel level) sink = _developerSink;

  static void _developerSink(String message, LogLevel level) {
    developer.log(
      message,
      name: 'redpanda',
      level: level == LogLevel.debug
          ? 500 // FINE
          : 800 /* INFO */,
    );
  }

  /// Logs an operational message (safe for default level).
  static void info(String message) => _emit(message, LogLevel.info);

  /// Logs a verbose/diagnostic message that may include sensitive details
  /// (OH ids, payload sizes, peer addresses). Suppressed at default level.
  static void debug(String message) => _emit(message, LogLevel.debug);

  static void _emit(String message, LogLevel level) {
    if (level.index < minLevel.index) return;
    sink(message, level);
  }
}
