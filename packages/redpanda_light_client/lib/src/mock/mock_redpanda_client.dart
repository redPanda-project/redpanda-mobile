import 'dart:async';
import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/channel_doctor_report.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/loopback_result.dart';
import 'package:redpanda_light_client/src/domain/oh_fetch_status.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/peer_stats_snapshot.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';

/// A mock implementation of [RedPandaClient] for testing and UI development.
class MockRedPandaClient implements RedPandaClient {
  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _incomingMessageController =
      StreamController<DecryptedMessage>.broadcast();

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  Stream<int> get peerCountStream => Stream.value(1); // Mock 1 peer

  @override
  Future<void> connect() async {
    _connectionStatusController.add(ConnectionStatus.connecting);
    await Future.delayed(const Duration(seconds: 3)); // Simulate network delay
    _connectionStatusController.add(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }

  @override
  Future<String> sendMessage(
    String channelId,
    String content, {
    String? messageId,
  }) async {
    // Simulate sending
    await Future.delayed(Duration(milliseconds: 500));
    return messageId ??
        "mock-message-id-${DateTime.now().millisecondsSinceEpoch}";
  }

  @override
  Future<void> addPeer(String address) async {
    // Mock implementation - do nothing or log
    RpLog.debug('MockRedPandaClient: Added peer $address');
  }

  @override
  Future<LoopbackResult> runLoopbackTest(String channelId) async {
    await Future.delayed(const Duration(seconds: 1));
    return const LoopbackResult.ok(roundtripMs: 1000, hopCount: 2);
  }

  @override
  Future<ChannelDoctorReport> runChannelDoctor(String channelId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return const ChannelDoctorReport([
      DoctorStage(
        name: 'Host node reachable',
        status: DoctorStatus.ok,
        durationMs: 1,
        detail: 'Connected to mock-node (handshake verified).',
      ),
      DoctorStage(
        name: 'Own mailbox announced',
        status: DoctorStatus.ok,
        durationMs: 0,
        detail: 'Announced on mock-node, valid for 6 d.',
      ),
      DoctorStage(
        name: 'Peer mailbox known',
        status: DoctorStatus.ok,
        durationMs: 0,
        detail: 'Peer mailbox on mock-node.',
      ),
      DoctorStage(
        name: 'Last fetch success',
        status: DoctorStatus.ok,
        durationMs: 0,
        detail: 'Last successful mailbox check 3 s ago.',
      ),
      DoctorStage(
        name: 'Loopback self-test',
        status: DoctorStatus.ok,
        durationMs: 1000,
        detail: 'Round trip in 1.0 s via 2 relay hop(s).',
      ),
    ]);
  }

  @override
  Stream<PeerStatsSnapshot> get peerStatsStream => Stream.value(
    PeerStatsSnapshot(
      allPeers: [],
      activePeerAddresses: {},
      connectingPeerAddresses: {},
    ),
  );

  @override
  Future<OHRegistration> registerOutboundHandle({String? channelId}) async {
    throw UnimplementedError('Mock OH registration not available');
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async {
    return [];
  }

  @override
  Future<void> restoreOutboundHandle(OHRegistration registration) async {
    // Mock: no-op
  }

  @override
  Stream<DecryptedMessage> get incomingMessages =>
      _incomingMessageController.stream;

  @override
  Stream<OhMailboxUpdate> get ohMailboxUpdates => const Stream.empty();

  @override
  Stream<OhFetchStatus> get ohFetchStatus => const Stream.empty();

  @override
  Stream<OHRegistration> get ohRegistrationUpdates => const Stream.empty();

  @override
  Stream<PeerOhUpdate> get peerOhUpdates => const Stream.empty();

  @override
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? peerOhId,
    String? peerOhEndpoint,
    required bool isChannelCreator,
    String? ratchetState,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
  }) {
    // Mock: no-op
  }

  @override
  Stream<RatchetStateUpdate> get ratchetStateUpdates => const Stream.empty();

  @override
  Stream<GarlicSessionUpdate> get garlicSessionUpdates => const Stream.empty();

  @override
  Stream<RoutingAckUpdate> get routingAckUpdates => const Stream.empty();

  @override
  Stream<ChannelAckUpdate> get channelAckUpdates => const Stream.empty();

  @override
  Stream<List<NodeScore>> get nodeScoreUpdates => const Stream.empty();

  @override
  void restoreNodeScores(List<NodeScore> scores) {
    // Mock: no-op
  }

  @override
  void registerGroup(GroupRegistration registration) {
    // Mock: no-op
  }

  @override
  Future<String> sendGroupMessage(
    String groupId,
    String content, {
    String? messageId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return messageId ??
        'mock-group-message-id-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> rotateGroupKey(
    String groupId, {
    required List<GroupMemberInfo> members,
    String? label,
  }) async {
    // Mock: no-op
  }

  @override
  Future<void> retryPendingRotations(String groupId) async {
    // Mock: no-op
  }

  @override
  Future<void> sendGroupHandshake(String channelId, List<int> handshake) async {
    // Mock: no-op
  }

  @override
  Future<void> sendGroupInfoUpdate(String groupId, String label) async {
    // Mock: no-op
  }

  @override
  Stream<GroupStateUpdate> get groupStateUpdates => const Stream.empty();

  @override
  Stream<GroupHandshakeEvent> get groupHandshakeEvents => const Stream.empty();
}
