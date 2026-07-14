import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/services/field_logging.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> printed;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    printed = [];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
  });

  tearDown(() async {
    debugPrint = originalDebugPrint;
    await FieldLogging.setEnabled(false);
  });

  test('disabled by default: info lines do not reach the device log', () {
    RpLog.info('should stay invisible');
    expect(printed, isEmpty);
    expect(FieldLogging.enabled, isFalse);
  });

  test(
    'enabled: info lines reach the device log, debug stays suppressed',
    () async {
      await FieldLogging.setEnabled(true);
      printed.clear();

      RpLog.info('operational line');
      RpLog.debug('sensitive: oh-id 0xdead');

      expect(printed, equals(['[redpanda] operational line']));
    },
  );

  test('debug lines are filtered even if the threshold is lowered', () async {
    await FieldLogging.setEnabled(true);
    RpLog.minLevel = LogLevel.debug;
    printed.clear();

    RpLog.debug('sensitive: peer address');

    expect(printed, isEmpty);
    RpLog.minLevel = LogLevel.info;
  });

  test('setEnabled persists the choice and init restores it', () async {
    await FieldLogging.setEnabled(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FieldLogging.prefsKey), isTrue);

    await FieldLogging.setEnabled(false);
    printed.clear();
    RpLog.info('gone again');
    expect(printed, isEmpty);

    await prefs.setBool(FieldLogging.prefsKey, true);
    await FieldLogging.init();
    printed.clear();
    RpLog.info('back after restart');
    expect(printed, equals(['[redpanda] back after restart']));
  });
}
