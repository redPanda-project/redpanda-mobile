import 'dart:io';

import 'package:test/test.dart';

/// Guard-rail for TD033. The e2e suites only stay honest as long as every one
/// of them opts into two conventions, and both have already drifted once:
///
/// * `@Tags(['e2e'])` — decides which CI step runs the suite. Three suites had
///   silently lost it and were running inside the fast parallel unit step
///   (spawning JVM nodes there) while the serial e2e step never saw them.
/// * `e2eJarAvailable()` — the fail-closed backend-JAR check. A suite that
///   goes back to a plain existence check skips silently in CI again, which is
///   how a green run with zero e2e coverage happened on 2026-08-09.
///
/// This test is deliberately NOT tagged `e2e`: it needs no node and no JAR, so
/// it runs in the fast unit step and catches the drift on the very first PR.
void main() {
  test('every e2e suite carries the e2e tag and the fail-closed JAR guard', () {
    final dir = Directory('test/e2e');
    expect(
      dir.existsSync(),
      isTrue,
      reason:
          'expected to run with the package root as cwd, but ${dir.absolute.path} does not exist',
    );

    final suites =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('_test.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    expect(suites, isNotEmpty, reason: 'no e2e suites found in test/e2e');

    // Both patterns are deliberately lenient about spelling that Dart treats
    // as equivalent (`const` list, either quote style, whitespace before the
    // argument list): the guard-rail is here to catch a suite that forgot the
    // convention, not to police formatting.
    final tagPattern = RegExp(
      '''@Tags\\(\\s*(?:const\\s*)?\\[[^\\]]*['"]e2e['"]''',
    );
    final guardPattern = RegExp(r'\be2eJarAvailable\s*\(');

    for (final suite in suites) {
      final name = suite.uri.pathSegments.last;
      final source = suite.readAsStringSync();

      expect(
        tagPattern.hasMatch(source),
        isTrue,
        reason:
            "$name is missing @Tags(['e2e']) — without it the suite runs in "
            'the unit step instead of the serial e2e step',
      );
      expect(
        guardPattern.hasMatch(source),
        isTrue,
        reason:
            '$name does not use e2eJarAvailable() — a suite that checks for '
            'the backend JAR any other way skips silently in CI (TD033)',
      );
    }
  });
}
