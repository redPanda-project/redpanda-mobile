import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/services/foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('redpanda/foreground_service');
  final calls = <String>[];
  Object? Function()? handler;

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return handler != null ? handler!() : true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('starts once, is idempotent, stops on disable', () async {
    final service = ForegroundReceptionService(isAndroid: true);

    await service.setEnabled(true);
    await service.setEnabled(true); // no second start
    expect(calls, equals(['start']));
    expect(service.running, isTrue);

    await service.setEnabled(false);
    expect(calls, equals(['start', 'stop']));
    expect(service.running, isFalse);
  });

  test('non-Android platform never touches the channel', () async {
    final service = ForegroundReceptionService(isAndroid: false);

    await service.setEnabled(true);
    await service.setEnabled(false);
    expect(calls, isEmpty);
  });

  test('platform failure is swallowed and retried on the next call', () async {
    final service = ForegroundReceptionService(isAndroid: true);
    handler = () => throw PlatformException(code: 'boom');

    await service.setEnabled(true);
    expect(service.running, isFalse); // failed start is not recorded

    handler = null;
    await service.setEnabled(true); // retry succeeds
    expect(calls, equals(['start', 'start']));
    expect(service.running, isTrue);
  });
}
