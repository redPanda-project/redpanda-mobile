import 'dart:math';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/rendezvous_timing.dart';

/// T160/P6: the production pairing schedule is jittered, keeps the second
/// lookup past the node's mailbox-announce stagger, and still leaves room
/// for several lookups inside the 10 s pairing budget.
void main() {
  final timing = RendezvousTiming(random: Random(42));

  test('every delay stays inside base ± 40 %', () {
    for (var attempt = 0; attempt < 8; attempt++) {
      final base = RendezvousTiming.defaultPairingLookupDelays[attempt];
      for (var i = 0; i < 200; i++) {
        final d = timing.pairingDelay(attempt);
        expect(d, lessThanOrEqualTo(timing.maxPairingDelay(attempt)));
        expect(
          d.inMicroseconds,
          greaterThanOrEqualTo((base.inMicroseconds * 0.6).round()),
        );
      }
    }
  });

  test('the step after the first lookup never comes before 2.2 s', () {
    for (var i = 0; i < 500; i++) {
      expect(
        timing.pairingDelay(0),
        greaterThanOrEqualTo(const Duration(milliseconds: 2200)),
      );
    }
  });

  test('the schedule is not fixed: two joins draw different delays', () {
    final seen = {for (var i = 0; i < 50; i++) timing.pairingDelay(1)};
    expect(seen.length, greaterThan(40));
  });

  test(
    'worst case: three lookups after the first within 8.5 s of the join',
    () {
      var worst = Duration.zero;
      for (var attempt = 0; attempt < 3; attempt++) {
        worst += timing.maxPairingDelay(attempt);
      }
      // 3.5 + 2.1 + 2.8 = 8.4 s — the third retry still has ~1.5 s to answer
      // inside the 10 s budget even when the first three lookups are lost.
      expect(worst, lessThanOrEqualTo(const Duration(milliseconds: 8500)));
    },
  );

  test('yesterday\'s lookup follows today\'s by 0.3–1.5 s', () {
    for (var i = 0; i < 200; i++) {
      final d = timing.yesterdayOffset();
      expect(d, greaterThanOrEqualTo(const Duration(milliseconds: 300)));
      expect(d, lessThanOrEqualTo(const Duration(milliseconds: 1500)));
    }
  });
}
