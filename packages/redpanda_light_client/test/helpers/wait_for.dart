import 'package:test/test.dart';

/// Polls [predicate] until it holds, or fails the test after [timeout].
///
/// Use this instead of a fixed `Future.delayed(...)` whenever a test waits for
/// an asynchronous side effect before a *positive* assertion. A fixed sleep
/// encodes a guess about host speed: under load (a second `flutter test`, a CI
/// poller) the awaited work is not done yet and the test goes red although
/// nothing is broken (TD052). Polling turns that guess into a bounded wait —
/// fast when the host is idle, patient when it is not.
///
/// A fixed delay stays the right tool for the opposite case: asserting that
/// *nothing* happens within a window. There a too-short wait only weakens the
/// check, it cannot make it red.
Future<void> waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  // Stopwatch, not DateTime.now(): a wall-clock jump (NTP step, VM
  // suspend/resume) must not shorten or stretch the budget.
  final elapsed = Stopwatch()..start();
  while (!predicate()) {
    if (elapsed.elapsed > timeout) {
      fail('$description not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}
