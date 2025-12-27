import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:redpanda/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('tap on the floating action button, verify counter', (
      tester,
    ) async {
      app.main();
      await tester.pumpAndSettle();

      // Example test: Waiting for the app to launch and verifying Onboarding or Home screen.
      // Adjust this based on your actual initial screen logic.

      // For now, we just wait to ensure it launches without crashing.
      await Future.delayed(const Duration(seconds: 2));

      // Check if we are on the Onboarding screen
      // expect(find.text('Willkommen bei RedPanda'), findsOneWidget); // Example
    });
  });
}
