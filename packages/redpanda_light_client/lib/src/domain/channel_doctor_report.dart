/// Traffic-light outcome of a single Verbindungs-Doctor stage (T25).
enum DoctorStatus { ok, warn, fail }

/// One diagnostic stage of the channel connection doctor (T25). Carries only
/// isolate-sendable primitives so the whole report can cross the worker
/// boundary unchanged.
class DoctorStage {
  /// Short, stable stage name (e.g. "Host node reachable").
  final String name;

  /// Traffic-light result for this stage.
  final DoctorStatus status;

  /// How long evaluating this stage took, in milliseconds. For the loopback
  /// stage this is the measured round-trip time.
  final int durationMs;

  /// Human-readable detail or error — never a silent fail: every stage,
  /// including the green ones, explains its result.
  final String detail;

  const DoctorStage({
    required this.name,
    required this.status,
    required this.durationMs,
    required this.detail,
  });
}

/// Aggregate outcome of [RedPandaClient.runChannelDoctor] (T25): one entry
/// per diagnostic stage, in execution order. The UI only renders it.
class ChannelDoctorReport {
  final List<DoctorStage> stages;

  const ChannelDoctorReport(this.stages);
}
