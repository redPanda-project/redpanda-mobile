import 'dart:async';

import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Test double for [RedPandaClient] with scriptable send behaviour and
/// manually controllable incoming/update streams.
class FakeRedPandaClient implements RedPandaClient {
  final incomingController = StreamController<DecryptedMessage>.broadcast();
  final updateController = StreamController<OhMailboxUpdate>.broadcast();

  /// When set, [sendMessage] throws this error instead of succeeding.
  Object? sendError;

  final List<({String channelId, String content, String? messageId})>
  sentMessages = [];
  final List<OHRegistration> restoredHandles = [];
  final Map<String, List<int>> channelKeys = {};
  final Map<String, bool> channelCreatorRoles = {};
  final Map<String, String> restoredRatchetStates = {};
  final Map<String, Map<String, int>> restoredSessionTags = {};
  final Map<String, String> restoredPendingRgbs = {};
  final ratchetStateController =
      StreamController<RatchetStateUpdate>.broadcast();
  final garlicSessionController =
      StreamController<GarlicSessionUpdate>.broadcast();
  final routingAckController = StreamController<RoutingAckUpdate>.broadcast();
  final channelAckController = StreamController<ChannelAckUpdate>.broadcast();
  final nodeScoreController = StreamController<List<NodeScore>>.broadcast();
  final List<NodeScore> restoredNodeScores = [];

  @override
  Future<LoopbackResult> runLoopbackTest(String channelId) async {
    return const LoopbackResult.ok(roundtripMs: 42, hopCount: 0);
  }

  /// Report returned by [runChannelDoctor]; overridable per test.
  ChannelDoctorReport doctorReport = const ChannelDoctorReport([
    DoctorStage(
      name: 'Host node reachable',
      status: DoctorStatus.ok,
      durationMs: 1,
      detail: 'Connected to fake-node (handshake verified).',
    ),
    DoctorStage(
      name: 'Loopback self-test',
      status: DoctorStatus.ok,
      durationMs: 42,
      detail: 'Round trip in 0.0 s via 0 relay hop(s).',
    ),
  ]);

  /// Number of times [runChannelDoctor] was invoked.
  int doctorRunCount = 0;

  @override
  Future<ChannelDoctorReport> runChannelDoctor(String channelId) async {
    doctorRunCount++;
    return doctorReport;
  }

  @override
  Future<String> sendMessage(
    String channelId,
    String content, {
    String? messageId,
  }) async {
    final error = sendError;
    if (error != null) throw error;
    sentMessages.add((
      channelId: channelId,
      content: content,
      messageId: messageId,
    ));
    // Echo a caller-supplied id (retry path); otherwise mint a fresh one.
    return messageId ?? 'fake-${sentMessages.length}';
  }

  @override
  Future<void> restoreOutboundHandle(OHRegistration registration) async {
    restoredHandles.add(registration);
  }

  @override
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? peerOhId,
    String? peerOhEndpoint,
    List<OHDescriptor>? peerOhSet,
    required bool isChannelCreator,
    String? ratchetState,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
  }) {
    channelKeys[channelId] = encryptionKey;
    channelCreatorRoles[channelId] = isChannelCreator;
    if (ratchetState != null) {
      restoredRatchetStates[channelId] = ratchetState;
    }
    if (sessionTags != null) {
      restoredSessionTags[channelId] = sessionTags;
    }
    if (pendingRgbHex != null) {
      restoredPendingRgbs[channelId] = pendingRgbHex;
    }
  }

  @override
  Stream<RatchetStateUpdate> get ratchetStateUpdates =>
      ratchetStateController.stream;

  @override
  Stream<GarlicSessionUpdate> get garlicSessionUpdates =>
      garlicSessionController.stream;

  @override
  Stream<RoutingAckUpdate> get routingAckUpdates => routingAckController.stream;

  @override
  Stream<ChannelAckUpdate> get channelAckUpdates => channelAckController.stream;

  @override
  Stream<List<NodeScore>> get nodeScoreUpdates => nodeScoreController.stream;

  @override
  void restoreNodeScores(List<NodeScore> scores) {
    restoredNodeScores.addAll(scores);
  }

  @override
  Stream<DecryptedMessage> get incomingMessages => incomingController.stream;

  @override
  Stream<OhMailboxUpdate> get ohMailboxUpdates => updateController.stream;

  final fetchStatusController = StreamController<OhFetchStatus>.broadcast();

  @override
  Stream<OhFetchStatus> get ohFetchStatus => fetchStatusController.stream;

  final ohRegistrationController =
      StreamController<List<OHRegistration>>.broadcast();

  @override
  Stream<List<OHRegistration>> get ohRegistrationUpdates =>
      ohRegistrationController.stream;

  @override
  Future<void> ensureOhRedundancy(String channelId) async {}

  final peerOhUpdateController = StreamController<PeerOhUpdate>.broadcast();

  @override
  Stream<PeerOhUpdate> get peerOhUpdates => peerOhUpdateController.stream;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      Stream.value(ConnectionStatus.connected);

  @override
  Stream<int> get peerCountStream => Stream.value(1);

  @override
  Stream<PeerStatsSnapshot> get peerStatsStream => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {
    await incomingController.close();
    await updateController.close();
    await fetchStatusController.close();
    await ratchetStateController.close();
    await garlicSessionController.close();
    await routingAckController.close();
    await channelAckController.close();
    await nodeScoreController.close();
    await ohRegistrationController.close();
    await peerOhUpdateController.close();
  }

  @override
  Future<void> addPeer(String address) async {}

  /// Lifecycle signal counters (T26).
  int pauseCount = 0;
  int resumeCount = 0;

  @override
  void onPause() {
    pauseCount++;
  }

  @override
  void onResume() {
    resumeCount++;
  }

  /// When set, [registerOutboundHandle] returns a registration built by
  /// this factory (MS08 group tests); otherwise it throws.
  Future<OHRegistration> Function(String? channelId)? ohRegistrationFactory;

  @override
  Future<OHRegistration> registerOutboundHandle({String? channelId}) {
    final factory = ohRegistrationFactory;
    if (factory != null) return factory(channelId);
    throw UnimplementedError('not needed in these tests');
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async => [];

  // --- Groups (MS08) ---

  final groupStateController = StreamController<GroupStateUpdate>.broadcast();
  final groupHandshakeController =
      StreamController<GroupHandshakeEvent>.broadcast();
  final List<GroupRegistration> registeredGroups = [];
  final List<({String groupId, String content, String? messageId})>
  sentGroupMessages = [];
  final List<({String groupId, List<GroupMemberInfo> members, String? label})>
  rotations = [];
  final List<({String channelId, List<int> handshake})> sentHandshakes = [];
  final List<({String groupId, String label})> sentInfoUpdates = [];
  final List<String> retriedRotations = [];

  /// When set, [sendGroupMessage] throws this error instead of succeeding.
  Object? groupSendError;

  @override
  void registerGroup(GroupRegistration registration) {
    registeredGroups.add(registration);
  }

  @override
  Future<String> sendGroupMessage(
    String groupId,
    String content, {
    String? messageId,
  }) async {
    final error = groupSendError;
    if (error != null) throw error;
    sentGroupMessages.add((
      groupId: groupId,
      content: content,
      messageId: messageId,
    ));
    return messageId ?? 'fake-group-${sentGroupMessages.length}';
  }

  @override
  Future<void> rotateGroupKey(
    String groupId, {
    required List<GroupMemberInfo> members,
    String? label,
  }) async {
    rotations.add((groupId: groupId, members: members, label: label));
  }

  @override
  Future<void> retryPendingRotations(String groupId) async {
    retriedRotations.add(groupId);
  }

  @override
  Future<void> sendGroupHandshake(String channelId, List<int> handshake) async {
    sentHandshakes.add((channelId: channelId, handshake: handshake));
  }

  @override
  Future<void> sendGroupInfoUpdate(String groupId, String label) async {
    sentInfoUpdates.add((groupId: groupId, label: label));
  }

  @override
  Stream<GroupStateUpdate> get groupStateUpdates => groupStateController.stream;

  @override
  Stream<GroupHandshakeEvent> get groupHandshakeEvents =>
      groupHandshakeController.stream;
}
