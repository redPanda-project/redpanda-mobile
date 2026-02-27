class PeerStats {
  final String address;
  String? nodeId;
  int averageLatencyMs;
  int successCount;
  int failureCount;
  DateTime? lastSeen;

  PeerStats({
    required this.address,
    this.nodeId,
    this.averageLatencyMs = 9999,
    this.successCount = 0,
    this.failureCount = 0,
    this.lastSeen,
  });

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'nodeId': nodeId,
      'averageLatencyMs': averageLatencyMs,
      'successCount': successCount,
      'failureCount': failureCount,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }

  factory PeerStats.fromJson(Map<String, dynamic> json) {
    return PeerStats(
      address: json['address'] as String,
      nodeId: json['nodeId'] as String?,
      averageLatencyMs: json['averageLatencyMs'] as int? ?? 9999,
      successCount: json['successCount'] as int? ?? 0,
      failureCount: json['failureCount'] as int? ?? 0,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
    );
  }

  /// Calculates a score for the peer. Higher is better.
  ///
  /// Score factors:
  /// - Latency: Lower is better.
  /// - Reliability: successCount vs failureCount.
  /// - Recency: Peers not seen for a long time decay in score.
  double get score {
    // Latency Factor: Inverse of latency.
    // Add 1 to avoid division by zero. Cap at reasonable min latency
    double latencyFactor =
        1.0 / ((averageLatencyMs < 1 ? 1 : averageLatencyMs) + 1);

    // Reliability Factor: Successes count more than failures (optimistic).
    // But consecutive failures hurt.
    // If we have 0 successes, it's a new or bad peer.
    double reliabilityFactor = (successCount + 1) / ((failureCount + 1) * 0.5);

    // Decay Factor:
    // If lastSeen is null or very old, score drops.
    double decayFactor = 1.0;
    if (lastSeen != null) {
      final hoursSinceSeen = DateTime.now().difference(lastSeen!).inHours;
      if (hoursSinceSeen > 24) {
        decayFactor = 0.5; // Halve score if not seen in a day
      } else if (hoursSinceSeen > 168) {
        // 1 week
        decayFactor = 0.1;
      }
    }

    return latencyFactor * reliabilityFactor * decayFactor * 10000;
    // Multiplied by 10000 to make it human readable (e.g. 50, 100 instead of 0.005)
  }
}
