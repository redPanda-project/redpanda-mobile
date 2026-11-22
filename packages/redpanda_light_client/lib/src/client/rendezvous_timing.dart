import 'dart:math';

/// T160 timing of the rendezvous read-before-write and of the joiner's
/// pairing lookups. Production values are the defaults; tests pass short
/// durations (and a seeded [Random]) so they need no multi-second waits.
class RendezvousTiming {
  /// The longest a publish is held while the lookup that must precede it is
  /// in flight. A found record answers in ~0.1 s on the testnet and ~2–3 s
  /// on the local 5-node lab (2026-11-22); "no record" only after the node's
  /// DHT search times out (5–7 s). Past this, the side publishes anyway
  /// (counterpart offline, its store lost) — a late answer that teaches an
  /// entry the write lacked triggers a republish (read-repair, case B).
  final Duration prePublishHoldMax;

  /// Base delays between the joiner's pairing lookups after the first one
  /// (sent with its held first publish): +2.5, +1.5, +2, +4, +10, +20, +40,
  /// +80 s — nine lookups in all, dense in the first ten seconds where the
  /// pairing budget lives, then thinning out.
  final List<Duration> pairingLookupDelays;

  /// Relative jitter on every pairing delay (±[jitter], uniform). A fixed
  /// schedule would let the nodes near the channel key read off the join
  /// time, that the joiner does not know the creator yet, and — from where
  /// the sequence stops — when the pairing succeeded (review P6).
  final double jitter;

  /// Floor of the FIRST delay after jitter. The answer to a lookup reaches
  /// the joiner's mailbox through a relay that must resolve the mailbox host
  /// in the OH-DHT, and a node announces a new registration only a random
  /// 0–2 s after it (`OhAnnounceJob.NEW_REGISTRATION_STAGGER_MS`); the
  /// joiner's mailbox is brand new at the join, so the lookup at 0 s often
  /// loses its answer. The second one must come after the stagger.
  final Duration firstRetryFloor;

  /// Range of the offset between today's and yesterday's lookup of the same
  /// round: the two keys travel on separate routes at separate times, so the
  /// executing node of one cannot link both UTC-day keys of the channel.
  final Duration yesterdayOffsetMin;
  final Duration yesterdayOffsetMax;

  final Random _random;

  RendezvousTiming({
    this.prePublishHoldMax = const Duration(seconds: 5),
    this.pairingLookupDelays = defaultPairingLookupDelays,
    this.jitter = 0.4,
    this.firstRetryFloor = const Duration(milliseconds: 2200),
    this.yesterdayOffsetMin = const Duration(milliseconds: 300),
    this.yesterdayOffsetMax = const Duration(milliseconds: 1500),
    Random? random,
  }) : _random = random ?? Random.secure();

  static const List<Duration> defaultPairingLookupDelays = [
    Duration(milliseconds: 2500),
    Duration(milliseconds: 1500),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 80),
  ];

  /// The jittered delay before pairing lookup number [attempt] + 1
  /// (attempt 0 = the step after the first lookup), uniform in
  /// `[max(floor, base·(1−jitter)), base·(1+jitter)]`.
  Duration pairingDelay(int attempt) {
    final baseUs = pairingLookupDelays[attempt].inMicroseconds;
    var lowUs = (baseUs * (1 - jitter)).round();
    final highUs = (baseUs * (1 + jitter)).round();
    if (attempt == 0 && lowUs < firstRetryFloor.inMicroseconds) {
      lowUs = firstRetryFloor.inMicroseconds;
    }
    if (highUs <= lowUs) return Duration(microseconds: lowUs);
    return Duration(
      microseconds: lowUs + (_random.nextDouble() * (highUs - lowUs)).round(),
    );
  }

  /// Upper bound of [pairingDelay] for [attempt] (tests, budget checks).
  Duration maxPairingDelay(int attempt) {
    final baseUs = pairingLookupDelays[attempt].inMicroseconds;
    final highUs = (baseUs * (1 + jitter)).round();
    final floorUs = attempt == 0 ? firstRetryFloor.inMicroseconds : 0;
    return Duration(microseconds: max(highUs, floorUs));
  }

  /// The offset of yesterday's lookup behind today's.
  Duration yesterdayOffset() {
    final lowUs = yesterdayOffsetMin.inMicroseconds;
    final highUs = yesterdayOffsetMax.inMicroseconds;
    if (highUs <= lowUs) return yesterdayOffsetMin;
    return Duration(
      microseconds: lowUs + (_random.nextDouble() * (highUs - lowUs)).round(),
    );
  }
}
