import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/screens/channels/join_channel_screen.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

/// T140: the injected-payload hook the emulator duo E2E uses must drive the
/// SAME join handler as a camera scan — persist the channel, hand it to the
/// worker, return home — without ever starting the camera scanner.
void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;
  late GoRouter router;

  setUp(() {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/channels/join',
          builder: (_, state) =>
              JoinChannelScreen(injectedCode: state.extra as String?),
        ),
      ],
    );
  });

  tearDown(() async {
    await client.disconnect();
    await db.close();
  });

  Widget app() => ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(db),
      redPandaClientProvider.overrideWithValue(client),
    ],
    child: MaterialApp.router(routerConfig: router),
  );

  /// Lets real async work (crypto, drift) run while pumping frames.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('an injected QR payload joins through the production handler', (
    tester,
  ) async {
    final channel = (await tester.runAsync(
      () => Channel.generate('Joined Channel'),
    ))!;

    await tester.pumpWidget(app());
    router.push('/channels/join', extra: channel.toJson());
    await tester.pump();
    expect(find.byType(MobileScanner), findsNothing);

    await pumpUntil(tester, () => find.text('home').evaluate().isNotEmpty);

    expect(find.text('home'), findsOneWidget);
    final rows = (await tester.runAsync(() => db.select(db.channels).get()))!;
    expect(rows.map((r) => r.conversationId), [channel.id]);
    expect(rows.single.label, 'Joined Channel');
    expect(
      client.channelRegistrations.map((r) => r.channelId),
      contains(channel.id),
    );

    await unmount(tester);
  });

  testWidgets('an invalid injected payload is rejected and persists nothing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    router.push('/channels/join', extra: 'not a channel');
    await tester.pump();

    await pumpUntil(
      tester,
      () => find.textContaining('Invalid Channel Code').evaluate().isNotEmpty,
    );

    expect(find.textContaining('Invalid Channel Code'), findsOneWidget);
    expect(find.text('home'), findsNothing);
    final rows = (await tester.runAsync(() => db.select(db.channels).get()))!;
    expect(rows, isEmpty);

    await unmount(tester);
  });
}
