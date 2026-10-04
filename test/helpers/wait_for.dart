import 'package:flutter_test/flutter_test.dart';

/// Polls [predicate] until it holds, or fails the test after [timeout].
///
/// App-side twin of the light client's `test/helpers/wait_for.dart` (T105):
/// the app tests cannot import that one (it lives in another package's test
/// tree and uses `package:test`, which the app does not depend on). Keep both
/// in step.
///
/// Use it instead of a fixed `Future.delayed(...)` whenever a test waits for
/// an asynchronous side effect before a *positive* assertion: a fixed sleep is
/// a guess about host speed that goes red under load (TD052, TD121). A fixed
/// delay stays right for the opposite case — asserting that *nothing* happens
/// within a window.
Future<void> waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  // Stopwatch, not DateTime.now(): a wall-clock jump must not shorten or
  // stretch the budget.
  final elapsed = Stopwatch()..start();
  while (!predicate()) {
    if (elapsed.elapsed > timeout) {
      fail('$description not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
