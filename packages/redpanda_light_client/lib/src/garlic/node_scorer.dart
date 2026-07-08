/// Per-node reliability scoring from R-ACK feedback (Frontend MS06).
///
/// Lives in the network isolate next to the [HopSelector] that consumes it.
/// The app layer persists [snapshot] emissions into the Drift `node_scores`
/// table and feeds them back through [restore] after a restart (the same
/// pattern as the ratchet and garlic-session state — the isolate has no
/// database handle, see the C4 note in the frontend status overview).
class NodeScorer {
  final Map<String, NodeScore> _scores = {};

  /// Nodes below this delivery rate are avoided as hops when enough other
  /// candidates exist (master spec MS06, section 4).
  static const double avoidThreshold = 0.3;

  /// Neutral score for unknown nodes.
  static const double neutralScore = 0.5;

  /// Records a successful R-ACK round trip over [hopNodeIdsHex].
  void recordSuccess(List<String> hopNodeIdsHex, int latencyMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final nodeId in hopNodeIdsHex) {
      final score = _scores[nodeId] ?? NodeScore.empty(nodeId);
      _scores[nodeId] = score.withSuccess(latencyMs, now);
    }
  }

  /// Records a missing R-ACK (timeout) for every hop involved. The blame is
  /// collective — an R-ACK is a hint, not proof of which hop failed.
  void recordFailure(List<String> hopNodeIdsHex) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final nodeId in hopNodeIdsHex) {
      final score = _scores[nodeId] ?? NodeScore.empty(nodeId);
      _scores[nodeId] = score.withFailure(now);
    }
  }

  /// Delivery rate of [nodeIdHex] in [0, 1]; [neutralScore] when unknown.
  double score(String nodeIdHex) {
    final score = _scores[nodeIdHex];
    if (score == null) return neutralScore;
    final total = score.successCount + score.failureCount;
    if (total == 0) return neutralScore;
    return score.successCount / total;
  }

  /// True when [nodeIdHex] has enough data and falls below [avoidThreshold].
  bool shouldAvoid(String nodeIdHex) {
    final score = _scores[nodeIdHex];
    if (score == null) return false;
    // A single missing R-ACK must not blacklist a node — require a minimum
    // of observations before avoiding it.
    if (score.successCount + score.failureCount < 3) return false;
    return this.score(nodeIdHex) < avoidThreshold;
  }

  /// All scores for persistence.
  List<NodeScore> snapshot() => List.unmodifiable(_scores.values);

  /// Restores persisted scores (startup). Live entries win — restore is
  /// applied only for nodes without in-memory state.
  void restore(Iterable<NodeScore> scores) {
    for (final score in scores) {
      _scores.putIfAbsent(score.nodeIdHex, () => score);
    }
  }
}

/// Reliability statistics of one node. Immutable and isolate-sendable
/// (plain primitives only).
class NodeScore {
  /// KademliaId of the node, lowercase hex.
  final String nodeIdHex;

  /// R-ACK round trips this node was part of.
  final int successCount;

  /// Ack timeouts this node was part of.
  final int failureCount;

  /// Average send-to-R-ACK latency over the successful round trips
  /// (local clock, includes the mailbox polling delay).
  final int avgLatencyMs;

  final int lastUpdatedMs;

  const NodeScore({
    required this.nodeIdHex,
    required this.successCount,
    required this.failureCount,
    required this.avgLatencyMs,
    required this.lastUpdatedMs,
  });

  factory NodeScore.empty(String nodeIdHex) => NodeScore(
    nodeIdHex: nodeIdHex,
    successCount: 0,
    failureCount: 0,
    avgLatencyMs: 0,
    lastUpdatedMs: 0,
  );

  NodeScore withSuccess(int latencyMs, int nowMs) => NodeScore(
    nodeIdHex: nodeIdHex,
    successCount: successCount + 1,
    failureCount: failureCount,
    // Running average without storing the series.
    avgLatencyMs:
        ((avgLatencyMs * successCount) + latencyMs) ~/ (successCount + 1),
    lastUpdatedMs: nowMs,
  );

  NodeScore withFailure(int nowMs) => NodeScore(
    nodeIdHex: nodeIdHex,
    successCount: successCount,
    failureCount: failureCount + 1,
    avgLatencyMs: avgLatencyMs,
    lastUpdatedMs: nowMs,
  );
}
