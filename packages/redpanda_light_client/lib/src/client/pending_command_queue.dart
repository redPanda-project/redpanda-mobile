import 'package:redpanda_light_client/src/client/isolate_protocol.dart';

/// Buffers the commands nothing else re-sends while no worker isolate is
/// attached — the startup window and the gap between a worker's death and its
/// respawn (TD115).
///
/// Only [CommandRecovery.queuedUntilWorkerReady] commands belong here; the
/// re-established ones are covered by `WorkerReplayState` and the client's
/// connect/lifecycle flags, and buffering a second copy of those would send
/// stale state after the newest state was already replayed.
class PendingCommandQueue {
  /// Upper bound on buffered commands. A worker that never comes back must not
  /// grow this without bound (every queued command pins its arguments —
  /// message contents, group member lists). The bound is deliberately far
  /// above any real burst: the respawn backoff starts at 500 ms, and the
  /// request/response commands carry their own 15–90 s timeouts, so a queue
  /// this long already means the worker is gone for good.
  static const int capacity = 64;

  final List<IsolateCommand> _commands = [];

  /// Buffers [cmd] and returns the command that had to be evicted to make
  /// room, or null when nothing was dropped.
  ///
  /// Overflow drops the OLDEST command: the newest intent is the one a caller
  /// is most likely still waiting for, and the oldest is the one whose own
  /// timeout has most likely already fired. An eviction is never silent — the
  /// caller logs it.
  IsolateCommand? add(IsolateCommand cmd) {
    assert(
      cmd.recovery == CommandRecovery.queuedUntilWorkerReady,
      'only queuedUntilWorkerReady commands may be buffered, got '
      '${cmd.runtimeType} (${cmd.recovery})',
    );
    IsolateCommand? evicted;
    if (_commands.length >= capacity) {
      evicted = _commands.removeAt(0);
    }
    _commands.add(cmd);
    return evicted;
  }

  /// Removes and returns everything buffered, in the order it was added.
  List<IsolateCommand> drain() {
    final drained = List<IsolateCommand>.of(_commands);
    _commands.clear();
    return drained;
  }

  /// Drops a specific buffered command (identity), used when its caller gave
  /// up: a request whose future already completed with a timeout must not be
  /// executed by a later flush — on a first send attempt the network message
  /// id is generated worker-side, so a late execution would deliver a SECOND
  /// message the retry cannot deduplicate.
  bool remove(IsolateCommand cmd) => _commands.remove(cmd);

  /// Applies the worker-death policy and returns the commands it discarded:
  /// every request-bound command goes (its caller was just failed by
  /// `_failPendingRequests`, so executing it after the respawn would run a
  /// request nobody awaits any more — for a first send attempt that means a
  /// second, undedupable message), while fire-and-forget commands stay
  /// buffered for the next worker — dropping those would be exactly the
  /// silent loss TD115 removes, one respawn later.
  List<IsolateCommand> discardRequestBound() {
    final discarded = _commands.where((c) => c.requestId != null).toList();
    _commands.removeWhere((c) => c.requestId != null);
    return discarded;
  }

  /// Discards everything buffered (dispose only — after that nothing will
  /// ever flush the queue again).
  void clear() => _commands.clear();

  int get length => _commands.length;

  bool get isEmpty => _commands.isEmpty;
}
