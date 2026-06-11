import 'package:test/test.dart';

import 'package:redpanda_light_client/src/logging/logger.dart';

void main() {
  group('RpLog', () {
    late List<(String, LogLevel)> captured;
    late LogLevel savedLevel;
    late void Function(String, LogLevel) savedSink;

    setUp(() {
      captured = [];
      savedLevel = RpLog.minLevel;
      savedSink = RpLog.sink;
      RpLog.sink = (msg, level) => captured.add((msg, level));
    });

    tearDown(() {
      RpLog.sink = savedSink;
      RpLog.minLevel = savedLevel;
    });

    test('at default level (info), debug messages are suppressed', () {
      RpLog.minLevel = LogLevel.info;

      RpLog.info('operational');
      RpLog.debug('oh_id=deadbeef payload=2048 bytes');

      expect(captured, hasLength(1));
      expect(captured.single.$1, equals('operational'));
      expect(captured.single.$2, equals(LogLevel.info));
    });

    test('lowering minLevel to debug emits both', () {
      RpLog.minLevel = LogLevel.debug;

      RpLog.info('a');
      RpLog.debug('b');

      expect(captured.map((c) => c.$1), equals(['a', 'b']));
    });

    test('sensitive details only ever go through debug', () {
      RpLog.minLevel = LogLevel.info;
      RpLog.debug('peer 1.2.3.4:5 oh_id=ff serialized 99 bytes');
      expect(captured, isEmpty);
    });
  });
}
