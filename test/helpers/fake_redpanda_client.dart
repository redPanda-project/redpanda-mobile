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
  final ratchetStateController =
      StreamController<RatchetStateUpdate>.broadcast();

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
    required bool isChannelCreator,
    String? ratchetState,
  }) {
    channelKeys[channelId] = encryptionKey;
    channelCreatorRoles[channelId] = isChannelCreator;
    if (ratchetState != null) {
      restoredRatchetStates[channelId] = ratchetState;
    }
  }

  @override
  Stream<RatchetStateUpdate> get ratchetStateUpdates =>
      ratchetStateController.stream;

  @override
  Stream<DecryptedMessage> get incomingMessages => incomingController.stream;

  @override
  Stream<OhMailboxUpdate> get ohMailboxUpdates => updateController.stream;

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
    await ratchetStateController.close();
  }

  @override
  Future<void> addPeer(String address) async {}

  @override
  Future<OHRegistration> registerOutboundHandle({String? channelId}) {
    throw UnimplementedError('not needed in these tests');
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async => [];
}
