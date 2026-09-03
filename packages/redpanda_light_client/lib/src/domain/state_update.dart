import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';

/// Base type of every one-way state change the network layer publishes to the
/// app layer — "this piece of state changed, persist and/or display it".
///
/// **One channel, not one per event.** All subtypes travel over the single
/// [RedPandaClient.stateUpdates] stream and cross the isolate boundary inside
/// the single `EventStateUpdate` message. Adding a new state event therefore
/// costs two touchpoints: declare the subtype (here or next to its domain
/// type) and emit it in the worker. There is no protocol class, no
/// `_handleEvent` branch, no facade stream and no isolate-client controller to
/// add — the transport is type-agnostic.
///
/// **What is NOT a state update** (deliberately kept off this channel):
/// - request/response pairs correlated by a request id (send, OH
///   registration, loopback self-test, channel doctor, group operations) —
///   they answer exactly one caller and complete a `Future`;
/// - the incoming-message stream ([RedPandaClient.incomingMessages]) — it
///   carries domain entities, not state deltas;
/// - connection/telemetry streams (status, peer count, peer stats) — they are
///   seeded "current value" streams, not a persistence feed.
///
/// Every subtype must be isolate-sendable, i.e. built from plain Dart objects
/// (no closures, ports or native resources).
abstract class StateUpdate {
  const StateUpdate();
}

/// Typed views on the single state channel.
extension StateUpdateStream on Stream<StateUpdate> {
  /// The [T]-typed projection of this channel; every other update is dropped.
  ///
  /// Replaces the former per-event streams — `client.stateUpdates.of<
  /// RatchetStateUpdate>()` is exactly what `client.ratchetStateUpdates` was,
  /// but costs nothing per new event type.
  Stream<T> of<T extends StateUpdate>() => where((u) => u is T).cast<T>();
}

/// R-ACK-based node reliability snapshot (MS06), emitted whenever a score
/// changed so the app layer can persist it into `node_scores`.
class NodeScoreUpdate extends StateUpdate {
  final List<NodeScore> scores;
  const NodeScoreUpdate(this.scores);
}

/// A channel's current own-OH SET after a change (T21 failover / T42
/// redundancy top-up), so the app layer can sync its persisted rows to
/// exactly this set.
///
/// [OHRegistration] is isolate-sendable (its keypair holds only the 32-byte
/// Ed25519 seed and verify key), so the set travels as-is.
class OwnOhSetUpdate extends StateUpdate {
  /// Channel the set belongs to; null only for handles without a channel.
  final String? channelId;

  /// The complete current own-OH set of [channelId]. Never empty: the set is
  /// a REPLACEMENT instruction, and "this channel has no mailbox any more" is
  /// not a state the app can act on today, so the producer suppresses it
  /// rather than have every consumer invent its own interpretation.
  final List<OHRegistration> handles;

  const OwnOhSetUpdate({required this.channelId, required this.handles});
}
