import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:sentry/sentry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Field diagnostics (T180, `plans/PLAN-field-diagnostics.md`): while the
/// switch is on, every [RpDiag] event of this process — from the network
/// worker and from the app — is appended to an on-disk ring buffer and
/// uploaded in batches as Sentry structured logs under its ORIGINAL device
/// time.
///
/// What leaves the device: mailbox ids, message ids, session/ack tags, node
/// ids and peer addresses in clear text, plus the user-chosen device name.
/// That is acceptable for the testnet only, so the feature is inert unless
/// [RpDiag.available] (network gate, `RpNetwork`): nothing is recorded,
/// nothing is uploaded and the switch is not shown.
///
/// Build modes: diagnostics work in release builds — the point of the
/// feature. Debug and profile builds (dev runs, the emulator E2E gate) do not
/// initialize Sentry (`main.dart`), so there they record into a SEPARATE
/// buffer file ([bufferFileName] with a `-debug` suffix) and never upload; a
/// later release build on the same device therefore never ships events a
/// debug run recorded.
///
/// Upload: every [uploadInterval] and on resume, after a reachability probe
/// of the Sentry ingest host. Events leave the buffer only after they were
/// handed to Sentry. The pure-Dart Sentry SDK keeps handed-over logs in
/// memory for up to 5 s before its HTTP request and does not report the
/// outcome, so a network loss inside that window loses those events; the
/// probe keeps the window small. Failures are swallowed and counted.
class FieldDiagnosticsService {
  FieldDiagnosticsService({
    Future<Directory> Function()? directory,
    DiagUploader? uploader,
    this.uploadInterval = const Duration(seconds: 10),
    this.flushDelay = const Duration(seconds: 2),
    this.batchSize = 100,
    this.capacityBytes = DiagRingBuffer.defaultCapacityBytes,
    bool? releaseMode,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _uploader = uploader ?? SentryDiagUploader(),
       _releaseMode = releaseMode ?? kReleaseMode;

  /// The process-wide service (set up by `main.dart`; an inert default for
  /// tests that never call [init]).
  static FieldDiagnosticsService instance = FieldDiagnosticsService();

  static const String enabledPrefsKey = 'field_diagnostics_enabled';
  static const String deviceNamePrefsKey = 'field_diagnostics_device_name';
  static const String bootCounterPrefsKey = 'field_diagnostics_boot';
  static const String bufferFileName = 'field_diagnostics.jsonl';
  static const int maxDeviceNameLength = 40;

  /// Build identifier for `rp.build`: pass
  /// `--dart-define=RP_BUILD=$(git rev-parse --short HEAD)` when building.
  static const String build = String.fromEnvironment(
    'RP_BUILD',
    defaultValue: 'unknown',
  );

  final Future<Directory> Function() _directory;
  final DiagUploader _uploader;
  final bool _releaseMode;
  final Duration uploadInterval;
  final Duration flushDelay;
  final int batchSize;
  final int capacityBytes;

  DiagRingBuffer? _buffer;
  bool _enabled = false;
  String _deviceName = '';
  Timer? _uploadTimer;
  Timer? _flushTimer;
  bool _uploading = false;
  Timer? _notifyTimer;
  StreamSubscription<ConnectionStatus>? _statusSub;
  bool? _lastConnected;

  /// Serializes [setEnabled] (and the restore in [init]): each queued step
  /// applies the value requested LAST, so an on→off pair can never end on.
  Future<void> _toggleTail = Future.value();
  bool? _wanted;

  /// Process counter, persisted and incremented once per process when
  /// diagnostics actually start (0 before, or when the prefs write failed). `rp.t_ms` is the primary order key of the events;
  /// (`rp.boot`, `rp.seq`) identifies an event uniquely, so a batch that is
  /// uploaded again after the process was killed mid-upload can be
  /// de-duplicated.
  int boot = 0;

  /// Random id of this process (`rp.boot_id`); tells two installs apart
  /// whose [boot] counters restarted from 0.
  final String bootId = _randomHex(4);
  int _seq = 0;

  /// Ring-buffer drops already reported in a `diag.state`.
  int _reportedRingDrops = 0;

  int uploaded = 0;
  int uploadFailures = 0;
  int probeFailures = 0;

  final _changes = StreamController<void>.broadcast();

  /// Fires after every change the UI shows (switch, name, upload counts).
  Stream<void> get changes => _changes.stream;

  bool get available => RpDiag.available;
  bool get enabled => _enabled;
  String get deviceName => _deviceName;
  int get buffered => _buffer?.length ?? 0;
  int get droppedByCapacity => _buffer?.dropped ?? 0;

  /// Whether this build uploads at all (release build with Sentry running).
  bool get uploadsActive => _releaseMode && _uploader.ready;

  /// The buffer, once loaded (tests).
  @visibleForTesting
  DiagRingBuffer? get buffer => _buffer;

  /// Restores the persisted switch and device name. Call once at startup,
  /// before the network client is created, so its first events are kept.
  ///
  /// With the network gate closed nothing starts, and any buffer a build for
  /// the testnet left behind is deleted: it holds identifiers in clear text
  /// and this build offers no switch to clear it.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceName = prefs.getString(deviceNamePrefsKey) ?? '';
    if (!available) {
      await _deleteBufferFiles();
      return;
    }
    if (prefs.getBool(enabledPrefsKey) ?? false) {
      await _enqueue(true, persist: false);
    }
  }

  /// Switches diagnostics on or off and persists the choice. Switching on is
  /// ignored when the network gate is closed. Switching off stops recording
  /// and uploading and deletes the events not uploaded yet. Calls are
  /// serialized; the last requested value wins.
  Future<void> setEnabled(bool value) {
    if (value && !available) return Future.value();
    return _enqueue(value, persist: true);
  }

  Future<void> _enqueue(bool value, {required bool persist}) {
    _wanted = value;
    final next = _toggleTail
        .then((_) => _apply(persist: persist))
        .catchError((Object _) {});
    _toggleTail = next;
    return next;
  }

  Future<void> _apply({required bool persist}) async {
    final want = _wanted;
    if (want == null) return;
    try {
      if (want) {
        if (persist) await _persistEnabled(true);
        await _start();
      } else {
        // Stop first: a failing prefs write must not leave it running.
        await _stop();
        if (persist) await _persistEnabled(false);
      }
    } finally {
      _notify();
    }
  }

  Future<void> _persistEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPrefsKey, value);
  }

  /// Bumps the persisted [boot] counter once per process, when diagnostics
  /// actually start. A failing prefs write is not fatal: [boot] then stays
  /// 0 and [bootId] still tells the process apart.
  Future<void> _bumpBoot() async {
    if (boot != 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = (prefs.getInt(bootCounterPrefsKey) ?? 0) + 1;
      await prefs.setInt(bootCounterPrefsKey, next);
      boot = next;
    } catch (_) {}
  }

  /// Deletes every buffer file of both build modes, including files moved
  /// aside after a read error.
  Future<void> _deleteBufferFiles() async {
    try {
      final dir = await _directory();
      if (!await dir.exists()) return;
      final stem = bufferFileName.replaceFirst('.jsonl', '');
      await for (final entity in dir.list()) {
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (entity is File && name.startsWith(stem)) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  Future<void> setDeviceName(String name) async {
    var trimmed = name.trim();
    if (trimmed.length > maxDeviceNameLength) {
      trimmed = trimmed.substring(0, maxDeviceNameLength);
    }
    _deviceName = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(deviceNamePrefsKey, trimmed);
    _notify();
  }

  /// Watches the client's aggregate status: every change between connected
  /// and not connected records a `net.ifaces` snapshot (T179: what did the
  /// device's network look like when the connections dropped).
  void attachConnectionStatus(Stream<ConnectionStatus> status) {
    _statusSub?.cancel();
    _statusSub = status.listen((s) {
      final connected = s == ConnectionStatus.connected;
      final previous = _lastConnected;
      _lastConnected = connected;
      if (previous == null || previous == connected) return;
      unawaited(snapshotInterfaces(connected ? 'connected' : 'disconnected'));
    });
  }

  /// App came to the foreground: snapshot the interfaces and upload.
  Future<void> onResume() async {
    if (!_enabled) return;
    unawaited(snapshotInterfaces('resume'));
    await uploadNow();
  }

  /// App goes to the background: get what is buffered onto the disk.
  Future<void> onPause() async {
    if (!_enabled) return;
    await _buffer?.flush();
  }

  /// Records a `net.ifaces` event with every interface name and address
  /// (`NetworkInterface.list`, no plugin).
  Future<void> snapshotInterfaces(String trigger) async {
    if (!RpDiag.enabled) return;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );
      RpDiag.emit(DiagEvt.netIfaces, {
        DiagKey.trigger: trigger,
        DiagKey.count: interfaces.length,
        DiagKey.ifaces: [
          for (final i in interfaces)
            '${i.name}=${i.addresses.map((a) => a.address).join('|')}',
        ].join(';'),
      });
    } catch (e) {
      RpDiag.emit(DiagEvt.netIfaces, {
        DiagKey.trigger: trigger,
        DiagKey.error: '$e',
      });
    }
  }

  String get _modeFileName => _releaseMode
      ? bufferFileName
      : bufferFileName.replaceFirst('.jsonl', '-debug.jsonl');

  Future<void> _start() async {
    if (_enabled) return;
    final dir = await _directory();
    final buffer = _buffer ??= DiagRingBuffer(
      File('${dir.path}/$_modeFileName'),
      capacityBytes: capacityBytes,
    );
    await buffer.load();
    // A later request (off) is queued behind this one and undoes it; no
    // need to start in between.
    if (_wanted == false) return;
    await _bumpBoot();
    if (_wanted == false) return;
    _enabled = true;
    RpDiag.sink = _record;
    RpDiag.setEnabled(true);
    _uploader.setLogsEnabled(true);
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(uploadInterval, (_) {
      _reportDrops();
      unawaited(uploadNow());
    });
    RpDiag.emit(DiagEvt.diagState, {
      DiagKey.enabled: true,
      DiagKey.buffered: buffer.length,
    });
    unawaited(snapshotInterfaces('start'));
  }

  Future<void> _stop() async {
    if (!_enabled) return;
    _enabled = false;
    RpDiag.setEnabled(false);
    RpDiag.sink = null;
    _uploader.setLogsEnabled(false);
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    await _buffer?.clear();
    // Files a read error moved aside hold unsent events as well.
    await _buffer?.deleteAsideFiles();
  }

  /// Reports, as a `diag.state`, events that never reached the buffer
  /// (main-isolate rate limit) or were evicted from it (capacity) since the
  /// last report — so a gap in the timeline is explained in Sentry.
  void _reportDrops() {
    final buffer = _buffer;
    if (!_enabled || buffer == null) return;
    final ringDrops = buffer.dropped - _reportedRingDrops;
    final rateDrops = RpDiag.dropped;
    if (ringDrops <= 0 && rateDrops <= 0) return;
    _reportedRingDrops = buffer.dropped;
    RpDiag.emit(DiagEvt.diagState, {
      DiagKey.enabled: true,
      DiagKey.buffered: buffer.length,
      DiagKey.diagDropped: RpDiag.takeDropped(),
      DiagKey.ringDropped: ringDrops,
    });
  }

  /// Runs the drop report of the upload tick (tests).
  @visibleForTesting
  void reportDropsForTesting() => _reportDrops();

  /// [RpDiag.sink]: stamps the envelope and appends to the buffer.
  /// Synchronous; the disk write follows within [flushDelay].
  void _record(DiagEvent event) {
    final buffer = _buffer;
    if (!_enabled || buffer == null) return;
    final line = jsonEncode({
      'e': event.name,
      't': event.tMs,
      's': _seq++,
      'b': boot,
      'i': bootId,
      'd': _deviceName,
      'a': event.attrs,
    });
    buffer.add(line);
    _flushTimer ??= Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(buffer.flush());
    });
    // The "N waiting" count on screen, at most once a second.
    _notifyTimer ??= Timer(const Duration(seconds: 1), () {
      _notifyTimer = null;
      _notify();
    });
  }

  /// Uploads up to [batchSize] buffered events (none while disabled, in
  /// non-release builds or while the Sentry host is unreachable).
  Future<void> uploadNow() async {
    final buffer = _buffer;
    if (!_enabled || buffer == null || buffer.length == 0) return;
    if (!uploadsActive || _uploading) return;
    _uploading = true;
    try {
      if (!await _uploader.probe()) {
        probeFailures++;
        return;
      }
      if (!_enabled) return;
      final batch = buffer.peek(batchSize);
      for (final line in batch) {
        try {
          final record = jsonDecode(line) as Map<String, dynamic>;
          _uploader.send(
            record['e'] as String,
            toSentryAttributes(record, build: build),
          );
          uploaded++;
        } catch (_) {
          uploadFailures++;
        }
      }
      // Handed over (or unreadable): either way they leave the buffer.
      buffer.removeFirst(batch.length);
      await buffer.flush();
    } catch (_) {
      uploadFailures++;
    } finally {
      _uploading = false;
      _notify();
    }
  }

  /// The Sentry attributes of one buffered record: the `rp.*` envelope plus
  /// the event's own fields under `rp.*`.
  static Map<String, SentryAttribute> toSentryAttributes(
    Map<String, dynamic> record, {
    required String build,
  }) {
    SentryAttribute? attr(Object? v) => switch (v) {
      final String s => SentryAttribute.string(s),
      final bool b => SentryAttribute.bool(b),
      final int i => SentryAttribute.int(i),
      final double d => SentryAttribute.double(d),
      null => null,
      _ => SentryAttribute.string('$v'),
    };
    final out = <String, SentryAttribute>{};
    final attrs = record['a'];
    if (attrs is Map) {
      attrs.forEach((key, value) {
        final a = attr(value);
        if (a != null) out['${DiagKey.prefix}$key'] = a;
      });
    }
    // The envelope last: an event field can never overwrite it.
    final device = record['d'] as String? ?? '';
    out[_k(DiagKey.evt)] = SentryAttribute.string(record['e'] as String);
    out[_k(DiagKey.role)] = SentryAttribute.string('app');
    out[_k(DiagKey.device)] = SentryAttribute.string(
      device.isEmpty ? 'unnamed' : device,
    );
    out[_k(DiagKey.net)] = SentryAttribute.string(RpNetwork.id);
    out[_k(DiagKey.build)] = SentryAttribute.string(build);
    out[_k(DiagKey.tMs)] = SentryAttribute.int(record['t'] as int);
    out[_k(DiagKey.seq)] = SentryAttribute.int(record['s'] as int);
    final boot = record['b'];
    if (boot is int) out[_k(DiagKey.boot)] = SentryAttribute.int(boot);
    final bootId = record['i'];
    if (bootId is String) {
      out[_k(DiagKey.bootId)] = SentryAttribute.string(bootId);
    }
    return out;
  }

  static String _k(String key) => '${DiagKey.prefix}$key';

  /// `SentryOptions.beforeSendLog`: drops every log while diagnostics are off
  /// (the app sends no other logs), and moves a diagnostics log back to the
  /// device time it was recorded at (`rp.t_ms`) — E0 verified that Sentry
  /// keeps such a timestamp for at least 26 h.
  static SentryLog? beforeSendLog(SentryLog log) {
    if (!RpDiag.enabled) return null;
    final tMs = log.attributes[_k(DiagKey.tMs)]?.value;
    if (tMs is int) {
      log.timestamp = DateTime.fromMillisecondsSinceEpoch(tMs, isUtc: true);
    }
    return log;
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Stops timers and listeners (tests).
  @visibleForTesting
  Future<void> dispose() async {
    _uploadTimer?.cancel();
    _flushTimer?.cancel();
    _notifyTimer?.cancel();
    await _statusSub?.cancel();
    await _buffer?.flush();
    await _changes.close();
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return [
      for (var i = 0; i < bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// Where buffered events go. [SentryDiagUploader] in the app; tests fake it.
abstract class DiagUploader {
  /// Whether an upload can happen at all (Sentry initialized).
  bool get ready;

  /// Whether the upload target is reachable right now. Must not throw.
  Future<bool> probe();

  /// Hands one event to the upload target. May throw (counted).
  void send(String body, Map<String, SentryAttribute> attributes);

  /// Mirrors the diagnostics switch into the SDK (`enableLogs`).
  void setLogsEnabled(bool enabled);
}

/// Uploads through the Sentry SDK's structured logs.
class SentryDiagUploader implements DiagUploader {
  /// The options of the running SDK, captured by `main.dart` in
  /// `Sentry.init`, so `enableLogs` follows the diagnostics switch.
  static SentryOptions? options;

  /// Ingest host of the DSN, probed before each batch.
  static String? probeHost;
  static const int probePort = 443;
  static const Duration probeTimeout = Duration(seconds: 3);

  @override
  bool get ready => Sentry.isEnabled;

  @override
  Future<bool> probe() async {
    final host = probeHost;
    if (host == null) return false;
    try {
      final socket = await Socket.connect(
        host,
        probePort,
        timeout: probeTimeout,
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void send(String body, Map<String, SentryAttribute> attributes) {
    unawaited(
      Future.sync(
        () => Sentry.logger.info(body, attributes: attributes),
      ).catchError((Object _) {}),
    );
  }

  @override
  void setLogsEnabled(bool enabled) {
    options?.enableLogs = enabled;
  }
}

/// Bounded on-disk buffer of JSON lines (T180): oldest lines are dropped
/// beyond [capacityBytes]; the content survives app restarts.
///
/// The in-memory queue is authoritative; [flush] brings the file in line —
/// appending new lines, or rewriting the file (via a temp file and rename)
/// after lines were removed. Disk writes are serialized.
class DiagRingBuffer {
  DiagRingBuffer(
    this.file, {
    this.capacityBytes = defaultCapacityBytes,
    @visibleForTesting Future<List<int>> Function(File file)? readBytes,
    @visibleForTesting
    Future<void> Function(File file, String newPath)? renameFile,
  }) : _readBytes = readBytes ?? ((f) => f.readAsBytes()),
       _renameFile = renameFile ?? ((f, path) => f.rename(path));

  final Future<List<int>> Function(File file) _readBytes;
  final Future<void> Function(File file, String newPath) _renameFile;

  static const int defaultCapacityBytes = 2 * 1024 * 1024;

  final File file;
  final int capacityBytes;

  final ListQueue<String> _lines = ListQueue();
  final List<String> _pendingAppend = [];
  int _bytes = 0;
  bool _rewrite = false;
  bool _loaded = false;
  Future<void> _ioTail = Future.value();

  /// Lines dropped because the buffer was full.
  int dropped = 0;

  int get length => _lines.length;
  int get bytes => _bytes;

  static int _size(String line) => utf8.encode(line).length + 1;

  /// Reads the file once. Decoding is lenient — a kill mid-append can tear a
  /// multi-byte character — and lines that are not valid JSON (the torn
  /// last line) are skipped, so one bad byte never costs the buffer.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!await file.exists()) return;
      final content = utf8
          .decode(await _readBytes(file), allowMalformed: true)
          .split('\n');
      var skipped = false;
      for (final line in content) {
        if (line.isEmpty) continue;
        try {
          jsonDecode(line);
        } catch (_) {
          skipped = true;
          continue;
        }
        _lines.add(line);
        _bytes += _size(line);
      }
      if (_trim() || skipped) _rewrite = true;
    } catch (_) {
      // An I/O error: never let the next flush overwrite the file with the
      // empty in-memory state. Move it aside and start a fresh file; the
      // aside file is deleted with the buffer.
      _lines.clear();
      _bytes = 0;
      _rewrite = false;
      try {
        await _renameFile(
          file,
          '${file.path}$asideMarker${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (_) {
        // Could not move it: keep appending to it and never rewrite it in
        // this process; only [clear] or the capacity (see [_persist])
        // delete it.
        _appendOnly = true;
      }
    }
  }

  /// Infix of a file moved aside after a read error.
  static const String asideMarker = '.unreadable-';

  /// Set when an unreadable file could not be moved aside: removals then
  /// stay in memory and the file is only ever appended to — until it
  /// outgrows [capacityBytes] or the buffer is cleared, which delete it.
  bool _appendOnly = false;

  /// Whether the buffer is in that append-only state (tests).
  @visibleForTesting
  bool get appendOnly => _appendOnly;

  /// Deletes files [load] moved aside.
  Future<void> deleteAsideFiles() async {
    try {
      final name = file.uri.pathSegments.last;
      await for (final entity in file.parent.list()) {
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith('$name$asideMarker')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  void add(String line) {
    _lines.add(line);
    _bytes += _size(line);
    final trimmed = _trim();
    if (trimmed) _rewrite = true;
    // Append-only never rewrites, so every line must be appended.
    if (!trimmed || _appendOnly) _pendingAppend.add(line);
  }

  /// Drops the oldest lines down to 90 % of the capacity once it is
  /// exceeded (the margin keeps the full-file rewrite rare).
  bool _trim() {
    if (_bytes <= capacityBytes) return false;
    final target = capacityBytes * 9 ~/ 10;
    while (_bytes > target && _lines.isNotEmpty) {
      _bytes -= _size(_lines.removeFirst());
      dropped++;
    }
    return true;
  }

  List<String> peek(int count) => _lines.take(count).toList();

  void removeFirst(int count) {
    for (var i = 0; i < count && _lines.isNotEmpty; i++) {
      _bytes -= _size(_lines.removeFirst());
    }
    if (count > 0) _rewrite = true;
  }

  /// Empties the buffer and deletes its file — unconditionally, also in
  /// append-only mode.
  Future<void> clear() {
    _lines.clear();
    _bytes = 0;
    _pendingAppend.clear();
    _rewrite = false;
    final next = _ioTail
        .then((_) async {
          if (await file.exists()) await file.delete();
          _appendOnly = false;
        })
        .catchError((Object _) {});
    _ioTail = next;
    return next;
  }

  Future<void> flush() {
    final next = _ioTail.then((_) => _persist()).catchError((Object _) {});
    _ioTail = next;
    return next;
  }

  Future<void> _persist() async {
    if (_appendOnly) {
      if (_pendingAppend.isNotEmpty) {
        final chunk = '${_pendingAppend.join('\n')}\n';
        _pendingAppend.clear();
        await file.writeAsString(chunk, mode: FileMode.append, flush: true);
      }
      _rewrite = false;
      // The cap still holds: an oversized unreadable file is deleted and
      // recreated from the in-memory lines.
      if (await file.length() <= capacityBytes) return;
      await file.delete();
      _appendOnly = false;
      _rewrite = true;
    }
    if (_rewrite) {
      _rewrite = false;
      _pendingAppend.clear();
      final tmp = File('${file.path}.tmp');
      await file.parent.create(recursive: true);
      await tmp.writeAsString(
        _lines.isEmpty ? '' : '${_lines.join('\n')}\n',
        flush: true,
      );
      await tmp.rename(file.path);
      return;
    }
    if (_pendingAppend.isEmpty) return;
    final chunk = '${_pendingAppend.join('\n')}\n';
    _pendingAppend.clear();
    await file.parent.create(recursive: true);
    await file.writeAsString(chunk, mode: FileMode.append, flush: true);
  }
}

/// UI state of the diagnostics switch.
@immutable
class FieldDiagnosticsState {
  final bool available;
  final bool enabled;
  final String deviceName;
  final int buffered;
  final int uploaded;
  final int uploadFailures;
  final bool uploadsActive;

  const FieldDiagnosticsState({
    required this.available,
    required this.enabled,
    required this.deviceName,
    required this.buffered,
    required this.uploaded,
    required this.uploadFailures,
    required this.uploadsActive,
  });

  factory FieldDiagnosticsState.of(FieldDiagnosticsService s) =>
      FieldDiagnosticsState(
        available: s.available,
        enabled: s.enabled,
        deviceName: s.deviceName,
        buffered: s.buffered,
        uploaded: s.uploaded,
        uploadFailures: s.uploadFailures + s.probeFailures,
        uploadsActive: s.uploadsActive,
      );
}

final fieldDiagnosticsServiceProvider = Provider<FieldDiagnosticsService>(
  (ref) => FieldDiagnosticsService.instance,
);

class FieldDiagnosticsNotifier extends Notifier<FieldDiagnosticsState> {
  @override
  FieldDiagnosticsState build() {
    final service = ref.watch(fieldDiagnosticsServiceProvider);
    final sub = service.changes.listen(
      (_) => state = FieldDiagnosticsState.of(service),
    );
    ref.onDispose(sub.cancel);
    return FieldDiagnosticsState.of(service);
  }

  Future<void> setEnabled(bool value) =>
      ref.read(fieldDiagnosticsServiceProvider).setEnabled(value);

  Future<void> setDeviceName(String name) =>
      ref.read(fieldDiagnosticsServiceProvider).setDeviceName(name);
}

final fieldDiagnosticsProvider =
    NotifierProvider<FieldDiagnosticsNotifier, FieldDiagnosticsState>(
      FieldDiagnosticsNotifier.new,
    );
