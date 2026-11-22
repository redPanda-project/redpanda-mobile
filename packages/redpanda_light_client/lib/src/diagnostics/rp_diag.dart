import 'package:crypto/crypto.dart' show sha256;
import 'package:meta/meta.dart';
import 'package:redpanda_light_client/src/diagnostics/rp_network.dart';

/// One field-diagnostics event (T180): a catalogue name, the device time it
/// happened at and its attributes. Plain data — crosses isolate boundaries
/// unchanged (attribute values are only String / int / double / bool).
class DiagEvent {
  /// One of `DiagEvt`.
  final String name;

  /// Device time, ms since epoch, taken when the event was emitted (in the
  /// isolate that emitted it).
  final int tMs;

  /// Attribute key (without the `rp.` prefix) → value.
  final Map<String, Object> attrs;

  const DiagEvent(this.name, this.tMs, this.attrs);

  @override
  String toString() => 'DiagEvent($name, $tMs, $attrs)';
}

/// The field-diagnostics event channel (T180).
///
/// Deliberately separate from `RpLog`: RpLog's privacy statement (info lines
/// never carry identifiers) stays true, while this channel carries full
/// identifiers — and therefore exists only behind two locks:
///
/// 1. the network gate: [setEnabled] refuses to switch on unless
///    [RpNetwork.allowsDiagnostics] holds for [networkId] (testnet only);
/// 2. the opt-in switch: off by default, switched on by the app.
///
/// [emit] is synchronous, never awaits, never throws into the caller and is a
/// single bool check while disabled — call sites that would build expensive
/// attributes check [enabled] first. Nothing is buffered here: an event goes
/// straight to [sink] (in the network worker that is the isolate port to the
/// main isolate, in the main isolate the app's ring buffer).
///
/// State is per isolate. The main isolate's switch is propagated to the
/// worker by `RedPandaIsolateClient` (command `CmdSetDiagnostics`, re-sent to
/// a respawned worker).
class RpDiag {
  RpDiag._();

  /// The network the gate checks. [RpNetwork.id] in every real build; tests
  /// override it to prove the feature is inert elsewhere.
  @visibleForTesting
  static String networkId = RpNetwork.id;

  /// Whether diagnostics may be switched on at all in this build.
  static bool get available => RpNetwork.allowsDiagnostics(networkId);

  static bool _enabled = false;

  /// Whether events are currently emitted.
  static bool get enabled => _enabled;

  /// Receives every emitted event while [enabled]. Must not throw (a throw
  /// is swallowed and counted in [sinkErrors]).
  static void Function(DiagEvent event)? sink;

  static final List<void Function(bool enabled)> _listeners = [];

  /// Rate limit: at most [maxEventsPerWindow] events per [rateWindow]; the
  /// rest is dropped and counted in [dropped]. Bounds what one isolate can
  /// push into the event port when something loops.
  static const int maxEventsPerWindow = 300;
  static const Duration rateWindow = Duration(seconds: 10);
  static int _windowStartMs = 0;
  static int _windowCount = 0;

  /// Events dropped by the rate limit (since the last [takeDropped]).
  static int dropped = 0;

  /// Exceptions swallowed while building or sinking an event.
  static int sinkErrors = 0;

  /// Switches emission on or off. Switching on is refused (stays off) when
  /// the network gate is closed. Listeners are told about every change.
  static void setEnabled(bool value) {
    final next = value && available;
    if (next == _enabled) return;
    _enabled = next;
    for (final listener in List.of(_listeners)) {
      try {
        listener(next);
      } catch (_) {
        sinkErrors++;
      }
    }
  }

  static void addListener(void Function(bool enabled) listener) =>
      _listeners.add(listener);

  static void removeListener(void Function(bool enabled) listener) =>
      _listeners.remove(listener);

  /// Emits [name] with [attrs] (null values are left out, lists are joined
  /// with commas, anything else that is not a String / num / bool becomes its
  /// `toString()`). A no-op while disabled.
  static void emit(String name, [Map<String, Object?> attrs = const {}]) {
    if (!_enabled) return;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _windowStartMs >= rateWindow.inMilliseconds ||
          nowMs < _windowStartMs) {
        _windowStartMs = nowMs;
        _windowCount = 0;
      }
      if (_windowCount >= maxEventsPerWindow) {
        dropped++;
        return;
      }
      _windowCount++;
      final target = sink;
      if (target == null) return;
      target(DiagEvent(name, nowMs, _clean(attrs)));
    } catch (_) {
      sinkErrors++;
    }
  }

  /// Hands an event that was emitted in another isolate to [sink] — used by
  /// the main isolate for events from the network worker. Dropped while this
  /// isolate's switch is off (the worker may still send a few in flight).
  static void deliver(DiagEvent event) {
    if (!_enabled) return;
    try {
      sink?.call(event);
    } catch (_) {
      sinkErrors++;
    }
  }

  /// Returns [dropped] and resets it.
  static int takeDropped() {
    final value = dropped;
    dropped = 0;
    return value;
  }

  /// Resets all state (tests only).
  @visibleForTesting
  static void resetForTesting() {
    _enabled = false;
    sink = null;
    _listeners.clear();
    _windowStartMs = 0;
    _windowCount = 0;
    dropped = 0;
    sinkErrors = 0;
    networkId = RpNetwork.id;
  }

  /// First 16 hex characters of SHA-256 over [bytes] — the catalogue's hash
  /// format (`pkt_hash`, `item_hash`), computable by a node from the same
  /// bytes.
  static String hash16(List<int> bytes) =>
      sha256.convert(bytes).toString().substring(0, 16);

  static const int _maxStringLength = 1024;

  static Map<String, Object> _clean(Map<String, Object?> attrs) {
    final out = <String, Object>{};
    attrs.forEach((key, value) {
      if (value == null) return;
      final Object v;
      if (value is String || value is int || value is double || value is bool) {
        v = value;
      } else if (value is Iterable) {
        v = value.join(',');
      } else {
        v = value.toString();
      }
      out[key] = v is String && v.length > _maxStringLength
          ? v.substring(0, _maxStringLength)
          : v;
    });
    return out;
  }
}
