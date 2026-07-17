import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/oh_fetch_status.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/loopback_result.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
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
  ///
  /// [messageId] is the stable 16-byte network message id as a hex string. It
  /// is carried inside the encrypted payload (ChannelMessage.message_id) and is
  /// what the receiver deduplicates on. Callers MUST pass the same [messageId]
  /// on every retry of the same logical message so re-sends are deduplicated.
  /// If omitted, a fresh random id is generated.
  ///
  /// Returns the message id (hex) that was actually used.
  Future<String> sendMessage(
    String channelId,
    String content, {
    String? messageId,
  });

  /// Adds a peer address (host:port) to the connection pool.
  Future<void> addPeer(String address);

  /// Runs a loopback self-test for [channelId] (T20): deposits a test
  /// message into the channel's OWN mailbox over the regular send path
  /// (garlic-routed when hops are available, direct deposit otherwise) and
  /// waits until the regular fetch pipeline receives and decrypts it. The
  /// test message never surfaces as a chat message.
  ///
  /// Never throws — failures (no own mailbox, not connected, timeout) are
  /// reported in [LoopbackResult.error].
  Future<LoopbackResult> runLoopbackTest(String channelId);

  /// Stream of periodic peer stats snapshots from the network layer.
  Stream<PeerStatsSnapshot> get peerStatsStream;

  /// Registers an Outbound Handle on a connected Full Node.
  /// Returns an [OHRegistration] on success.
  Future<OHRegistration> registerOutboundHandle({String? channelId});

  /// Fetches messages from the given OH mailbox.
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh);

  /// Re-activates a previously registered (persisted) Outbound Handle so it
  /// is polled again and auto-renewed. Does not contact the network.
  Future<void> restoreOutboundHandle(OHRegistration registration);

  /// Stream of incoming messages from background polling.
  Stream<DecryptedMessage> get incomingMessages;

  /// Stream of OH state changes (fetch cursor advanced, registration
  /// renewed, mailbox overflow detected). The app layer should persist
  /// [OhMailboxUpdate.lastCursor] and [OhMailboxUpdate.expiresAtMs].
  Stream<OhMailboxUpdate> get ohMailboxUpdates;

  /// Outcome of every mailbox fetch attempt (success and failure, including
  /// empty polls). Purely informational — the app layer uses it to display
  /// per-channel health ("mailbox last checked …"); nothing is persisted.
  Stream<OhFetchStatus> get ohFetchStatus;

  /// Registers channel encryption keys so [sendMessage] can encrypt outgoing
  /// messages for [channelId]. Optionally associates a peer OH ID for routing.
  ///
  /// [peerOhEndpoint] is the host:port of the node hosting the peer's OH
  /// (from the OHDescriptor). MS04 uses it to keep the destination node out
  /// of the garlic hop path.
  ///
  /// MS03b: the channel ratchet is initialized from these keys.
  /// [isChannelCreator] must reflect the true role — `true` only on the
  /// device that generated the channel (it holds the channel auth private
  /// key), `false` on a device that joined via QR code; with mismatched
  /// roles the two ratchets cannot line up. [ratchetState] restores a
  /// previously persisted ratchet (see [ratchetStateUpdates]); it is ignored
  /// when the client already holds a live session for [channelId], because
  /// the in-memory state is always the most advanced.
  ///
  /// MS05: [sessionTags] (tag hex → createdAtMs) and [pendingRgbHex] restore
  /// the persisted reverse-garlic session state (see [garlicSessionUpdates]);
  /// like [ratchetState], they are applied only on the first registration of
  /// [channelId] — live state always wins.
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? peerOhId,
    String? peerOhEndpoint,
    required bool isChannelCreator,
    String? ratchetState,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
  });

  /// Ratchet state changes (MS03b). Emitted after every encrypt/decrypt that
  /// advanced a channel ratchet; the app layer must persist
  /// [RatchetStateUpdate.stateJson] on-device (and only on-device — ratchet
  /// state never travels in the QR code or any off-device backup) and feed
  /// it back via [addChannelKeys] after a restart.
  Stream<RatchetStateUpdate> get ratchetStateUpdates;

  /// Reverse-garlic session state changes (MS05): outstanding session tags
  /// and the pending RGB per channel. The app layer must persist these
  /// on-device and feed them back via [addChannelKeys] after a restart — a
  /// lost session tag silently discards the matching reply (single-use).
  Stream<GarlicSessionUpdate> get garlicSessionUpdates;

  /// Routing-layer delivery feedback (MS06): an R-ACK arrived for an
  /// outgoing message (update its status to `routed`, or `failed` on
  /// HANDLE_EXPIRED), or none arrived within the ack timeout ([timedOut] —
  /// re-send over fresh hops).
  Stream<RoutingAckUpdate> get routingAckUpdates;

  /// Application-layer delivery confirmations (MS06): the channel partner
  /// received and decrypted an outgoing message (status `delivered`).
  Stream<ChannelAckUpdate> get channelAckUpdates;

  /// Node score snapshots (MS06). The app layer persists them into the
  /// `node_scores` table and feeds them back via [restoreNodeScores] after
  /// a restart.
  Stream<List<NodeScore>> get nodeScoreUpdates;

  /// Restores persisted node scores on startup. Live in-memory scores win.
  void restoreNodeScores(List<NodeScore> scores);

  // -----------------------------------------------------------------------
  // Groups (Frontend MS08)
  // -----------------------------------------------------------------------

  /// Registers a group (the group counterpart of [addChannelKeys]) so
  /// [sendGroupMessage] can encrypt for it and fetched items from the group
  /// OH (registered under `channelId = groupId`) can be decrypted.
  /// Persisted state travels in [GroupRegistration.cryptoStateJson],
  /// `pendingItems` and `pendingRotations`; like the channel state it is
  /// applied only on the first registration — live state wins.
  void registerGroup(GroupRegistration registration);

  /// Encrypts [content] once with the own sender chain (envelope v5) and
  /// fans it out to every other member's group OH (master spec MS08,
  /// Decisions 1/5/7). Pass the same [messageId] on retries — members that
  /// were already reached deduplicate on it.
  ///
  /// Throws [GroupSendException] when one or more members could not be
  /// reached. A retry re-encrypts with the next chain key; members that
  /// already received the message drop the duplicate by message id.
  Future<String> sendGroupMessage(
    String groupId,
    String content, {
    String? messageId,
  });

  /// Admin only (Decision 9): installs a new key epoch for [members] (the
  /// full replacement list), seals one rotation box per other member and
  /// delivers them (Decisions 3/6/12). Boxes that could not be delivered
  /// stay pending (see [GroupStateUpdate.pendingRotations]) and are retried
  /// via [retryPendingRotations].
  Future<void> rotateGroupKey(
    String groupId, {
    required List<GroupMemberInfo> members,
    String? label,
  });

  /// Re-sends sealed rotation boxes that could not be delivered yet.
  Future<void> retryPendingRotations(String groupId);

  /// Sends a group handshake (invite proposal / join accept, Decision 8)
  /// over the existing 1:1 channel [channelId], ratchet-encrypted like any
  /// other 1:1 message. [handshake] is a serialized `GroupHandshake`.
  Future<void> sendGroupHandshake(String channelId, List<int> handshake);

  /// Admin only: broadcasts a rename to the group (GroupControl over v5).
  Future<void> sendGroupInfoUpdate(String groupId, String label);

  /// Group state snapshots (crypto chains, epoch, member list, buffered
  /// items, pending rotation boxes). The app layer persists them and feeds
  /// them back via [registerGroup] after a restart.
  Stream<GroupStateUpdate> get groupStateUpdates;

  /// Group handshakes received over 1:1 channels (Decision 8).
  Stream<GroupHandshakeEvent> get groupHandshakeEvents;
}
