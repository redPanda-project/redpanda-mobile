import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/screens/channels/connection_doctor_screen.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart' hide Channel;

import '../helpers/fake_redpanda_client.dart';

void main() {
  late FakeRedPandaClient client;

  setUp(() {
    client = FakeRedPandaClient();
  });

  tearDown(() async {
    await client.disconnect();
  });

  Widget app() {
    return ProviderScope(
      overrides: [redPandaClientProvider.overrideWithValue(client)],
      child: const MaterialApp(
        home: ConnectionDoctorScreen(channelUuid: 'channel-1'),
      ),
    );
  }

  bool hasIcon(WidgetTester tester, IconData icon, Color color) {
    return tester
        .widgetList<Icon>(find.byIcon(icon))
        .any((w) => w.color == color);
  }

  testWidgets('renders each stage with its traffic-light and detail', (
    tester,
  ) async {
    client.doctorReport = const ChannelDoctorReport([
      DoctorStage(
        name: 'Host node reachable',
        status: DoctorStatus.ok,
        durationMs: 3,
        detail: 'Connected to node-a (handshake verified).',
      ),
      DoctorStage(
        name: "Recipient's mailbox known",
        status: DoctorStatus.warn,
        durationMs: 0,
        detail: "Recipient's mailbox unknown — scan the QR code.",
      ),
      DoctorStage(
        name: 'Loopback self-test',
        status: DoctorStatus.fail,
        durationMs: 1200,
        detail: 'Failed: not received within 60s',
      ),
    ]);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Stage names render.
    expect(find.text('Host node reachable'), findsOneWidget);
    expect(find.text("Recipient's mailbox known"), findsOneWidget);
    expect(find.text('Loopback self-test'), findsOneWidget);

    // Failure detail is surfaced (no silent fail).
    expect(find.text('Failed: not received within 60s'), findsOneWidget);

    // Runtime is shown per stage.
    expect(find.text('1.2 s'), findsOneWidget);
    expect(find.text('3 ms'), findsOneWidget);

    // Traffic-light colours: green ok, amber warn, red fail.
    expect(hasIcon(tester, Icons.check_circle, Colors.green), isTrue);
    expect(hasIcon(tester, Icons.warning, Colors.amber), isTrue);
    expect(hasIcon(tester, Icons.error, Colors.red), isTrue);
  });

  testWidgets('runs on open and re-runs on button tap', (tester) async {
    client.doctorReport = const ChannelDoctorReport([
      DoctorStage(
        name: 'Host node reachable',
        status: DoctorStatus.ok,
        durationMs: 1,
        detail: 'Connected.',
      ),
    ]);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(client.doctorRunCount, 1); // initial auto-run

    await tester.tap(find.text('Run again'));
    await tester.pumpAndSettle();
    expect(client.doctorRunCount, 2);
  });
}
