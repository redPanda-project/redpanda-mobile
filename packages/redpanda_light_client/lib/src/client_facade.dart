import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/peer_stats_snapshot.dart';

/// The primary interface for the App to interact with the RedPanda Network.
abstract class RedPandaClient {
  /// Stream of connection status updates.
  Stream<ConnectionStatus> get connectionStatus;

  /// Stream of connected peer count.
  Stream<int> get peerCountStream;

  /// Connects to the network (starts background services).
  Future<void> connect();

  /// Disconnects from the network.
  Future<void> disconnect();

  /// Sends a message to a channel identified by [channelId].
  /// The content is encrypted with the channel's encryption key.
  /// Returns a message ID.
  Future<String> sendMessage(String channelId, String content);

  /// Adds a peer address (host:port) to the connection pool.
  Future<void> addPeer(String address);

  /// Stream of periodic peer stats snapshots from the network layer.
  Stream<PeerStatsSnapshot> get peerStatsStream;

  /// Registers an Outbound Handle on a connected Full Node.
  /// Returns an [OHRegistration] on success.
  Future<OHRegistration> registerOutboundHandle();

  /// Fetches messages from the given OH mailbox.
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh);

  /// Stream of incoming messages from background polling.
  Stream<DecryptedMessage> get incomingMessages;

  /// Registers channel encryption keys so [sendMessage] can encrypt outgoing
  /// messages for [channelId]. Optionally associates a peer OH ID for routing.
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? peerOhId,
  });
}
