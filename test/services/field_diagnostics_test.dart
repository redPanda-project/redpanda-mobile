import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/screens/field_diagnostics_section.dart';
import 'package:redpanda/services/field_diagnostics.dart';
import 'package:redpanda/shared/widgets/field_diagnostics_indicator.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:sentry/sentry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeUploader implements DiagUploader {
  bool reachable = true;
  bool throwOnSend = false;
  bool? logsEnabled;
  final sent = <(String, Map<String, SentryAttribute>)>[];

  @override
  bool get ready => true;

  @override
  Future<bool> probe() async => reachable;

  @override
  void send(String body, Map<String, SentryAttribute> attributes) {
    if (throwOnSend) throw StateError('sdk broken');
    sent.add((body, attributes));
  }

  @override
  void setLogsEnabled(bool enabled) => logsEnabled = enabled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late FakeUploader uploader;
  final services = <FieldDiagnosticsService>[];

  FieldDiagnosticsService newService({
    bool releaseMode = true,
    int capacity = DiagRingBuffer.defaultCapacityBytes,
  }) {
    final s = FieldDiagnosticsService(
      directory: () async => dir,
      uploader: uploader,
      capacityBytes: capacity,
      uploadInterval: const Duration(hours: 1), // uploads driven by the test
      flushDelay: const Duration(milliseconds: 1),
      releaseMode: releaseMode,
    );
    services.add(s);
    return s;
  }

  /// The start-up `net.ifaces` snapshot is recorded asynchronously; wait
  /// for it so a test's buffer count is stable.
  Future<void> settled(FieldDiagnosticsService s) async {
    final sw = Stopwatch()..start();
    while (!s.buffer!.peek(10000).any((l) => l.contains('"net.ifaces"'))) {
      if (sw.elapsed > const Duration(seconds: 10)) {
        fail('no net.ifaces snapshot recorded');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    RpDiag.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('t180_diag');
    uploader = FakeUploader();
  });

  tearDown(() async {
    for (final s in services) {
      await s.setEnabled(false);
      await s.dispose();
    }
    services.clear();
    RpDiag.resetForTesting();
    dir.deleteSync(recursive: true);
  });

  group('network gate', () {
    setUp(() => RpDiag.networkId = 'mainnet');

    test(
      'another network: switching on is ignored, nothing recorded',
      () async {
        final service = newService();
        await service.setEnabled(true);
        RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
        expect(service.available, isFalse);
        expect(service.enabled, isFalse);
        expect(RpDiag.enabled, isFalse);
        expect(service.buffered, 0);
        expect(uploader.logsEnabled, isNull);
        expect(dir.listSync(), isEmpty, reason: 'no buffer file is created');
      },
    );

    test(
      'another network: a buffer left by a testnet build is deleted',
      () async {
        final names = [
          FieldDiagnosticsService.bufferFileName,
          'field_diagnostics-debug.jsonl',
          'field_diagnostics.jsonl${DiagRingBuffer.asideMarker}1',
        ];
        for (final n in names) {
          File('${dir.path}/$n').writeAsStringSync('{"e":"conn.up"}\n');
        }
        File('${dir.path}/unrelated.txt').writeAsStringSync('keep');
        await newService().init();
        for (final n in names) {
          expect(File('${dir.path}/$n').existsSync(), isFalse, reason: n);
        }
        expect(File('${dir.path}/unrelated.txt').existsSync(), isTrue);
      },
    );

    test('another network: a persisted "on" is not restored', () async {
      SharedPreferences.setMockInitialValues({
        FieldDiagnosticsService.enabledPrefsKey: true,
      });
      final service = newService();
      await service.init();
      expect(service.enabled, isFalse);
      expect(RpDiag.enabled, isFalse);
    });

    testWidgets('another network: neither the switch nor the indicator is '
        'shown', (tester) async {
      // Not registered for the shared tearDown: nothing ever starts here,
      // and the tearDown's async work cannot complete inside this widget
      // test's fake-async zone.
      final service = FieldDiagnosticsService(
        directory: () async => dir,
        uploader: uploader,
      );
      await tester.runAsync(() => service.setEnabled(true)); // refused
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fieldDiagnosticsServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  FieldDiagnosticsSection(),
                  FieldDiagnosticsIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('field-diagnostics-switch')), findsNothing);
      expect(find.text('Diagnostics to Sentry'), findsNothing);
      expect(
        find.byKey(const Key('field-diagnostics-indicator')),
        findsNothing,
      );
    });
  });

  group('UI on the testnet', () {
    testWidgets('switch off by default, indicator appears once it is on', (
      tester,
    ) async {
      final service = newService();
      await tester.runAsync(service.init);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fieldDiagnosticsServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  FieldDiagnosticsSection(),
                  FieldDiagnosticsIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('field-diagnostics-switch')),
      );
      expect(tile.value, isFalse);
      expect(
        find.byKey(const Key('field-diagnostics-indicator')),
        findsNothing,
      );
      expect(find.textContaining('mailbox ids, message ids'), findsOneWidget);

      await tester.runAsync(() => service.setEnabled(true));
      await tester.pump();
      expect(
        find.byKey(const Key('field-diagnostics-indicator')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('field-diagnostics-switch')),
            )
            .value,
        isTrue,
      );
    });
  });

  group('DiagRingBuffer', () {
    String line(int i) => jsonEncode({'i': i, 'pad': 'x' * 80});

    test('keeps order, drops the oldest beyond the cap', () async {
      final buffer = DiagRingBuffer(
        File('${dir.path}/b.jsonl'),
        capacityBytes: 2000,
      );
      await buffer.load();
      for (var i = 0; i < 100; i++) {
        buffer.add(line(i));
      }
      expect(buffer.bytes, lessThanOrEqualTo(2000));
      expect(buffer.dropped, greaterThan(0));
      final kept = buffer
          .peek(1000)
          .map((l) => (jsonDecode(l) as Map)['i'] as int)
          .toList();
      expect(kept.last, 99, reason: 'the newest survive');
      expect(kept, List.generate(kept.length, (k) => 100 - kept.length + k));
    });

    test('survives a restart; removal after upload reaches the disk', () async {
      final file = File('${dir.path}/b.jsonl');
      final first = DiagRingBuffer(file);
      await first.load();
      for (var i = 0; i < 5; i++) {
        first.add(line(i));
      }
      await first.flush();

      final second = DiagRingBuffer(file);
      await second.load();
      expect(second.length, 5);
      second.removeFirst(2);
      await second.flush();

      final third = DiagRingBuffer(file);
      await third.load();
      expect(third.peek(10).map((l) => (jsonDecode(l) as Map)['i']), [2, 3, 4]);
    });

    test('a torn last line (crash mid-write) is skipped on load', () async {
      final file = File('${dir.path}/b.jsonl')
        ..writeAsStringSync('${line(0)}\n${line(1)}\n{"i": 2, "pa');
      final buffer = DiagRingBuffer(file);
      await buffer.load();
      expect(buffer.length, 2);
    });

    test('a torn multi-byte character costs only its line', () async {
      final file = File('${dir.path}/b.jsonl')
        ..writeAsBytesSync([
          ...utf8.encode('${line(0)}\n${line(1)}\n'),
          ...utf8.encode('{"d": "Mi 10 '),
          0xc3, // first byte of "ä", the second one never made it
        ]);
      final buffer = DiagRingBuffer(file);
      await buffer.load();
      expect(buffer.length, 2);
      expect(
        dir.listSync().where(
          (f) => f.path.contains(DiagRingBuffer.asideMarker),
        ),
        isEmpty,
      );
    });

    test(
      'a file that cannot be read is moved aside, never overwritten',
      () async {
        final file = File('${dir.path}/b.jsonl')
          ..writeAsBytesSync([0xff, 0xfe, 0x00, 0x80, 0x0a]);
        final buffer = DiagRingBuffer(
          file,
          readBytes: (_) async => throw const FileSystemException('EIO'),
        );
        await buffer.load();
        expect(buffer.length, 0);
        buffer.add(line(1));
        buffer.removeFirst(1); // would rewrite the file
        buffer.add(line(2));
        await buffer.flush();
        final aside = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains(DiagRingBuffer.asideMarker))
            .toList();
        expect(aside, hasLength(1));
        expect(aside.single.readAsBytesSync(), [0xff, 0xfe, 0x00, 0x80, 0x0a]);
        await buffer.deleteAsideFiles();
        expect(aside.single.existsSync(), isFalse);
      },
    );

    DiagRingBuffer appendOnlyBuffer(File file, {int capacity = 100000}) =>
        DiagRingBuffer(
          file,
          capacityBytes: capacity,
          readBytes: (_) async => throw const FileSystemException('EIO'),
          renameFile: (_, _) async => throw const FileSystemException('EPERM'),
        );

    test(
      'append-only (unreadable, not movable): clear deletes the file',
      () async {
        final file = File('${dir.path}/b.jsonl')..writeAsStringSync('secret\n');
        final buffer = appendOnlyBuffer(file);
        await buffer.load();
        expect(buffer.appendOnly, isTrue);
        buffer.add(line(1));
        buffer.removeFirst(1);
        buffer.add(line(2));
        await buffer.flush();
        expect(
          file.readAsStringSync(),
          startsWith('secret\n'),
          reason: 'never rewritten',
        );
        buffer.add(line(3)); // pending, must not be appended after clear
        await buffer.clear();
        await buffer.flush();
        expect(file.existsSync(), isFalse);
      },
    );

    test('append-only: the cap still holds (delete and recreate)', () async {
      final file = File('${dir.path}/b.jsonl')
        ..writeAsStringSync('${'Z' * 1500}\n');
      final buffer = appendOnlyBuffer(file, capacity: 2000);
      await buffer.load();
      for (var i = 0; i < 10; i++) {
        buffer.add(line(i));
        await buffer.flush();
      }
      expect(file.lengthSync(), lessThanOrEqualTo(2000));
      expect(file.readAsStringSync(), isNot(contains('ZZZZ')));
      expect(buffer.appendOnly, isFalse);
    });

    test('an oversized file is trimmed on load', () async {
      final file = File('${dir.path}/b.jsonl')
        ..writeAsStringSync('${List.generate(100, line).join('\n')}\n');
      final buffer = DiagRingBuffer(file, capacityBytes: 2000);
      await buffer.load();
      expect(buffer.bytes, lessThanOrEqualTo(2000));
      expect((jsonDecode(buffer.peek(1000).last) as Map)['i'], 99);
    });
  });

  group('service', () {
    test(
      'records with the envelope and uploads with the original time',
      () async {
        final service = newService();
        await service.setDeviceName('  Mi 10  ');
        await service.setEnabled(true);
        await settled(service);
        expect(uploader.logsEnabled, isTrue);
        RpDiag.emit(DiagEvt.connDown, {
          DiagKey.addr: '5.75.137.166:59558',
          DiagKey.reason: 'closed',
          DiagKey.wasUp: true,
          DiagKey.ageMs: 1234,
        });
        final recordedAt = DateTime.now().millisecondsSinceEpoch;
        // diag.state + net.ifaces + conn.down
        expect(service.buffered, 3);
        final ifaces =
            jsonDecode(
                  service.buffer!
                      .peek(10)
                      .firstWhere((l) => l.contains('net.ifaces')),
                )
                as Map;
        expect((ifaces['a'] as Map)['trigger'], 'start');

        await service.uploadNow();
        expect(service.buffered, 0);
        final down = uploader.sent.singleWhere((s) => s.$1 == DiagEvt.connDown);
        final a = down.$2;
        expect(a['rp.evt']!.value, DiagEvt.connDown);
        expect(a['rp.role']!.value, 'app');
        expect(a['rp.device']!.value, 'Mi 10');
        expect(a['rp.net']!.value, RpNetwork.id);
        expect(a['rp.build']!.value, FieldDiagnosticsService.build);
        expect(a['rp.boot']!.value, service.boot);
        expect(a['rp.t_ms']!.value as int, closeTo(recordedAt, 5000));
        expect(a['rp.seq']!.value, isA<int>());
        expect(a['rp.addr']!.value, '5.75.137.166:59558');
        expect(a['rp.was_up']!.value, isA<bool>());
        expect(a['rp.age_ms']!.value, 1234);
        final seqs = uploader.sent.map((s) => s.$2['rp.seq']!.value as int);
        expect(seqs, orderedEquals(List.of(seqs)..sort()));
      },
    );

    test('unreachable Sentry: nothing leaves the buffer', () async {
      final service = newService();
      await service.setEnabled(true);
      await settled(service);
      RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
      final before = service.buffered;
      uploader.reachable = false;
      await service.uploadNow();
      expect(uploader.sent, isEmpty);
      expect(service.buffered, before);
      expect(service.probeFailures, 1);

      uploader.reachable = true;
      await service.uploadNow();
      expect(service.buffered, 0);
      expect(uploader.sent, hasLength(before));
    });

    test('a throwing SDK is swallowed and counted', () async {
      final service = newService();
      await service.setEnabled(true);
      RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
      uploader.throwOnSend = true;
      await expectLater(service.uploadNow(), completes);
      expect(service.uploadFailures, greaterThan(0));
    });

    test(
      'non-release builds record but never upload, into their own file',
      () async {
        final service = newService(releaseMode: false);
        await service.setEnabled(true);
        RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
        await service.uploadNow();
        expect(uploader.sent, isEmpty);
        expect(service.uploadsActive, isFalse);
        expect(service.buffered, greaterThan(0));
        await service.onPause();
        expect(
          File(
            '${dir.path}/${FieldDiagnosticsService.bufferFileName.replaceFirst('.jsonl', '-debug.jsonl')}',
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            '${dir.path}/${FieldDiagnosticsService.bufferFileName}',
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('the switch and the buffer survive an app restart', () async {
      final first = newService();
      await first.setEnabled(true);
      RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
      final recorded = first.buffered;
      await first.onPause(); // flush
      // Simulate the process ending: the next process starts clean.
      RpDiag.resetForTesting();

      final second = newService();
      await second.init();
      expect(second.enabled, isTrue);
      expect(RpDiag.enabled, isTrue);
      // The old events plus the new process' diag.state.
      expect(second.buffered, greaterThan(recorded));
      expect(second.boot, isNot(first.boot));
    });

    test(
      'switching off stops recording and deletes what was not sent',
      () async {
        final service = newService();
        await service.setEnabled(true);
        RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
        await service.setEnabled(false);
        expect(RpDiag.enabled, isFalse);
        expect(uploader.logsEnabled, isFalse);
        RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:2'});
        expect(service.buffered, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(FieldDiagnosticsService.enabledPrefsKey), isFalse);
      },
    );

    test('on→off while the start is still loading ends OFF', () async {
      final gate = Completer<Directory>();
      final service = FieldDiagnosticsService(
        directory: () => gate.future,
        uploader: uploader,
        uploadInterval: const Duration(hours: 1),
        releaseMode: true,
      );
      services.add(service);
      final on = service.setEnabled(true);
      final off = service.setEnabled(false);
      gate.complete(dir);
      await on;
      await off;
      expect(service.enabled, isFalse);
      expect(RpDiag.enabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(FieldDiagnosticsService.enabledPrefsKey), isFalse);
      RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
      expect(service.buffered, 0);
    });

    test('switching off deletes the buffer file', () async {
      final service = newService();
      await service.setEnabled(true);
      RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
      await service.onPause();
      final file = File(
        '${dir.path}/${FieldDiagnosticsService.bufferFileName}',
      );
      expect(file.existsSync(), isTrue);
      await service.setEnabled(false);
      expect(file.existsSync(), isFalse);
    });

    test('off→on→off→on: the last request wins, one buffer', () async {
      final service = newService();
      final calls = [
        service.setEnabled(true),
        service.setEnabled(false),
        service.setEnabled(true),
      ];
      await Future.wait(calls);
      expect(service.enabled, isTrue);
      expect(RpDiag.enabled, isTrue);
      final buffer = service.buffer;
      await service.setEnabled(false);
      await service.setEnabled(true);
      expect(identical(service.buffer, buffer), isTrue);
    });

    test('boot counter: +1 per process that starts diagnostics, (boot, seq) '
        'on every event', () async {
      final idle = newService();
      await idle.init(); // diagnostics off: no prefs write at all
      expect(idle.boot, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(FieldDiagnosticsService.bootCounterPrefsKey), isNull);

      final first = newService();
      await first.setEnabled(true);
      await first.setEnabled(false);
      await first.setEnabled(true); // same process: no second bump
      final second = newService();
      await second.setEnabled(true);
      expect(first.boot, 1);
      expect(second.boot, 2);
      RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:1'});
      await second.uploadNow();
      final up = uploader.sent.firstWhere((s) => s.$1 == DiagEvt.connUp).$2;
      expect(up['rp.boot']!.value, 2);
      expect(up['rp.boot_id']!.value, second.bootId);
    });

    test('drops are reported as diag.state', () async {
      // The trim leaves 10 % headroom, so the report itself fits.
      final service = newService(capacity: 4000);
      await service.setEnabled(true);
      for (var i = 0; i < 60; i++) {
        RpDiag.emit(DiagEvt.connUp, {DiagKey.addr: 'a:$i'});
      }
      expect(service.droppedByCapacity, greaterThan(0));
      service.reportDropsForTesting();
      final state =
          jsonDecode(
                service.buffer!
                    .peek(1000)
                    .lastWhere((l) => l.contains('diag.state')),
              )
              as Map;
      expect((state['a'] as Map)['ring_dropped'], greaterThan(0));
      // Reported once, not again.
      final count = service.buffer!
          .peek(1000)
          .where((l) => l.contains('diag.state'))
          .length;
      service.reportDropsForTesting();
      expect(
        service.buffer!
            .peek(1000)
            .where((l) => l.contains('diag.state'))
            .length,
        count,
      );
    });

    test('the envelope cannot be overwritten by an event field', () {
      final attrs = FieldDiagnosticsService.toSentryAttributes({
        'e': 'conn.up',
        't': 5,
        's': 1,
        'b': 'beef',
        'd': '',
        'a': {'evt': 'forged', 'role': 'node', 'addr': 'a:1'},
      }, build: 'abc123');
      expect(attrs['rp.evt']!.value, 'conn.up');
      expect(attrs['rp.role']!.value, 'app');
      expect(attrs['rp.device']!.value, 'unnamed');
      expect(attrs['rp.build']!.value, 'abc123');
    });
  });

  group('beforeSendLog', () {
    SentryLog log() => SentryLog(
      timestamp: DateTime.now(),
      level: SentryLogLevel.info,
      body: 'conn.up',
      attributes: {
        'rp.t_ms': SentryAttribute.int(1700000000123),
        'rp.evt': SentryAttribute.string('conn.up'),
      },
    );

    test('moves the log back to the recorded device time', () {
      RpDiag.setEnabled(true);
      final out = FieldDiagnosticsService.beforeSendLog(log());
      expect(
        out!.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1700000000123, isUtc: true),
      );
    });

    test('drops every log while diagnostics are off', () {
      expect(FieldDiagnosticsService.beforeSendLog(log()), isNull);
    });
  });
}
