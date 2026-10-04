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
///
/// [interval] is the pause between polls. [onPoll] runs once per failed poll,
/// right before the pause — for pollers that must nudge the system (e.g.
/// `requestPeerLists()`) instead of only watching it. [message], if given,
/// builds the failure text lazily at timeout, so it can report the state at
/// that moment (e.g. how many of N items were found); it replaces the
/// `[description] not met` default.
Future<void> waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
  Duration interval = const Duration(milliseconds: 10),
  void Function()? onPoll,
  String Function()? message,
}) async {
  // Stopwatch, not DateTime.now(): a wall-clock jump (NTP step, VM
  // suspend/resume) must not shorten or stretch the budget.
  final elapsed = Stopwatch()..start();
  while (!predicate()) {
    if (elapsed.elapsed > timeout) {
      fail(message?.call() ?? '$description not met within $timeout');
    }
    onPoll?.call();
    await Future.delayed(interval);
  }
}
