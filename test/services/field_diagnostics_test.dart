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

  FieldDiagnosticsService newService({bool releaseMode = true}) {
    final s = FieldDiagnosticsService(
      directory: () async => dir,
      uploader: uploader,
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
      final service = newService();
      SharedPreferences.setMockInitialValues({
        FieldDiagnosticsService.enabledPrefsKey: true,
      });
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
