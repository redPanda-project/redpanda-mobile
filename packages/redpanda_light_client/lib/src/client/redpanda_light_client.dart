import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/rendezvous_manager.dart';
import 'package:redpanda_light_client/src/client/rendezvous_timing.dart';
import 'package:redpanda_light_client/src/crypto/group_control.dart';
import 'package:redpanda_light_client/src/crypto/group_crypto.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v3.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/diagnostics/diag_catalogue.dart';
import 'package:redpanda_light_client/src/diagnostics/rp_diag.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/domain/channel_doctor_report.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/loopback_result.dart';
import 'package:redpanda_light_client/src/domain/oh_fetch_status.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/rendezvous_state_update.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/counterpart_oh_update.dart';
import 'package:redpanda_light_client/src/domain/reverse_garlic_block.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/ack_tag_store.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/hop_selector.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:redpanda_light_client/src/garlic/return_path.dart';
import 'package:redpanda_light_client/src/garlic/rgb_builder.dart';
import 'package:redpanda_light_client/src/streams/seeded_stream.dart';
import 'package:redpanda_light_client/src/garlic/session_tag_store.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart'
    hide RoutingAck;
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

import 'package:redpanda_light_client/src/peer_repository.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';
import 'package:redpanda_light_client/src/models/peer_stats_snapshot.dart';

import 'package:redpanda_light_client/src/network/active_peer.dart';

/// The implementation of the RedPanda Light Client.
/// Manages network connections, encryption, and routing.
class RedPandaLightClient implements RedPandaClient {
  // Wire command bytes this class sends or matches responses by. Mirrors of
  // redpandaj `im.redpanda.core.Command`; checked against the wire registry by
  // test/unit/command_bytes_test.dart (TD091).
  static const int _cmdFlaschenpostPut = 141;
  static const int _cmdFlaschenpostV2 = 142;
  static const int _cmdOutboundRegisterOhReq = 150;
  static const int _cmdOutboundRegisterOhRes = 151;
  static const int _cmdOutboundFetchReq = 152;
  static const int _cmdOutboundFetchRes = 153;
  static const int _cmdOutboundAckFetchReq = 156;
  static const int _cmdOutboundAckFetchRes = 157;
  static const int _cmdFlaschenpostPutRes = 158;
  static const int _cmdOutboundSubscribeReq = 159;
  static const int _cmdOutboundSubscribeRes = 160;
  static const int _cmdOutboundNotify = 161;

  final NodeId selfNodeId;
  final KeyPair selfKeys;

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  /// Bootstrap nodes of the v23 test network. Tests and local setups inject
  /// their own list via the `seeds` parameter.
  ///
  /// Fixed IP literals (T158), so that finding the network never depends on
  /// a DNS record. Host names remain valid in an injected `seeds` list: an
  /// unresolvable name only costs that one dial (it lands in backoff), and
  /// the alias dedup in [_runConnectionCheck] keeps a name and its own IP
  /// from being dialled as two connections to the same node.
  static const List<String> defaultSeeds = [
    '5.75.137.166:59558',
    '46.224.156.238:59558',
  ];

  /// Upper bound for one alias-dedup DNS lookup. A resolver that hangs (no
  /// network, captive portal) must not hold up the dials of the candidates
  /// after it in the same connection check, e.g. an IP seed.
  static const Duration lookupTimeout = Duration(seconds: 2);

  /// DNS resolution used by the alias dedup; injectable for tests.
  final Future<List<InternetAddress>> Function(String host) _lookup;

  final SocketFactory _socketFactory;
  // final Set<String> _knownAddresses = {}; // Replaced by PeerRepository
  final PeerRepository _peerRepository;
  final Map<String, ActivePeer> _peers = {};

  /// Addresses picked for a dial by a [_runConnectionCheck] that has not put
  /// its [ActivePeer] into [_peers] yet.
  ///
  /// [_runConnectionCheck] awaits a DNS lookup (`_resolveEndpoint`) between
  /// choosing a candidate and registering the
  /// peer, and it runs from three places at once: the constructor's
  /// `load().then(...)`, [connect], and the 3 s timer. Without this set a
  /// second check re-picks an address whose dial is still inside that await
  /// window — `_peers.containsKey` is still false — and the client opens two
  /// parallel connections with the same node identity. The node then hits its
  /// TD020 branch (redpandaj#276, `ConnectionHandler.setupConnection`),
  /// disconnects the duplicate, and `_peers[address]` may be left holding
  /// exactly the ActivePeer that was dropped: `isEncryptionActive` was true a
  /// moment earlier, yet `sendMessage` throws "no active peer available"
  /// (T78 — reproduced by pinning the e2e suite to two cores).
  final Set<String> _dialsInFlight = {};

  /// The `ip:port` endpoints each address resolved to the last time the dial
  /// loop looked at it (dialled or skipped as alias) — T154.
  ///
  /// For an address in [_peers] the entry is written in the same synchronous
  /// step that inserts the peer, so two overlapping checks cannot both miss
  /// each other: whichever finishes its lookup second sees the first one's
  /// endpoints. Resolving at dial time instead of on every check also keeps
  /// a connected hostname peer from costing a DNS query per 3 s tick.
  /// [_livePeerFor] uses the entries to find the connection that serves an
  /// endpoint under its other name (an OH host known by IP, reached under a
  /// host name). Bounded by the peer repository's address set.
  final Map<String, Set<String>> _resolvedEndpoints = {};

  /// Retry delay for an address skipped as alias of a live connection: short
  /// and fixed (no exponential growth), so the alias is dialled soon after
  /// the connection it aliases is lost.
  static const Duration aliasRetryDelay = Duration(seconds: 10);

  Timer? _connectionTimer;
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  /// Set once [disconnect] has run its terminal shutdown. A
  /// [RedPandaLightClient] is single-use: guards against reusing a
  /// disconnected instance (see [connect]/[disconnect] for the contract).
  bool _disconnected = false;

  // Configuration
  static const int maxConnections = 5;
  static const int coreSlots = 3;
  static const int roamingSlots = 2;
  static const Duration backoffDuration = Duration(seconds: 10);

  /// TCP dial timeout for the default socket factory (see constructor).
  static const Duration connectTimeout = Duration(seconds: 10);

  // State for mobile Optimization
  // bool _isBackgrounded = false; // To be set by flutter lifecycle

  /// Clock behind the retry-backoff and not-connected-log decisions —
  /// exactly [_waitInBackoff], [_handleBackoff] and [_logNotConnected], and
  /// nothing else.
  ///
  /// Injectable (constructor parameter `now`, default [DateTime.now]) because
  /// the retry backoff is otherwise only testable by wall-clock waiting: the
  /// dial loop awaits real DNS lookups, so `fake_async` cannot drive it
  /// either (TD079). Tests hand in a variable they advance by hand and get
  /// backoff expiry in microseconds instead of seconds.
  ///
  /// NOT the clock of the whole connection routine: the roaming-rotation age
  /// check in [_runConnectionCheck] still reads [DateTime.now] directly, as do
  /// the polling loop and every duration measured across an await inside one
  /// operation (latency, timeouts). Do not assume a test that pins this clock
  /// has frozen rotation as well.
  final DateTime Function() _now;

  // Backoff state
  final Map<String, DateTime> _nextRetryTime = {};
  final Map<String, int> _retryCounts = {}; // Restored
  final Set<String> _intentionalDisconnects = {};
  // static const Duration _initialBackoff = Duration(seconds: 2);
  // static const Duration _maxBackoff = Duration(minutes: 5);

  bool get isEncryptionActive => _peers.values.any((p) => p.isEncryptionActive);
  bool get isPongSent => _peers.values.any((p) => p.isPongSent);

  /// How long sendMessage waits for the deposit response (command 158)
  /// before falling back to fire-and-forget semantics. Overridable for tests.
  final Duration depositResponseTimeout;

  /// How long fetchMessages waits for the fetch response (command 153).
  /// Overridable for tests.
  final Duration fetchResponseTimeout;

  /// T160: timing of the rendezvous read-before-write and pairing lookups.
  final RendezvousTiming _rendezvousTiming;

  /// After this many consecutive fetch timeouts on the SAME connection the
  /// connection is torn down and redialed immediately (T33): fetches that
  /// time out repeatedly while the socket looks connected are the signature
  /// of a half-open TCP connection (seen after emulator kill/restart —
  /// the node never sees the requests), and every further request into the
  /// dead socket costs a full timeout instead of a reconnect.
  static const int forceReconnectFetchTimeoutThreshold = 2;

  /// Number of garlic relay hops sendMessage aims for (MS04).
  static const int defaultHopCount = 3;

  /// Selects garlic relay hops from the peer repository (MS04).
  late final HopSelector _hopSelector;

  /// Builds Reverse Garlic Blocks for outgoing messages (MS05).
  late final RgbBuilder _rgbBuilder;

  /// Outstanding session tags issued with our RGBs (MS05): single-use
  /// correlation of tagged replies fetched from our OH mailboxes.
  final SessionTagStore _sessionTagStore = SessionTagStore();

  /// Latest unused RGB received from the channel partner, per channel id
  /// (MS05). Replaced by every newer one — each message carries a fresh RGB
  /// (OQ 2: one per message), so only the newest is worth keeping.
  final Map<String, ReverseGarlicBlock> _pendingRgbs = {};

  /// Channel ids this worker already holds live state for (T111).
  ///
  /// The worker is the SINGLE owner of channel/crypto state: the first
  /// [addChannelKeys] for a channel adopts the persisted snapshot the app
  /// layer hands over, every later call is a re-registration that may only
  /// fill gaps — it can never move the ratchet, the garlic session, the
  /// rendezvous name or the partner's mailbox set backwards. Enforced in
  /// [addChannelKeys] rather than promised in a doc comment.
  ///
  /// Cleared by [disconnect] together with the state it guards.
  final Set<String> _restoredChannels = {};

  /// Whether this worker already holds live state for [channelId] (T111) —
  /// i.e. whether a further [addChannelKeys] would be a re-registration.
  bool knowsChannel(String channelId) => _restoredChannels.contains(channelId);

  /// Hop count of the most recent sendMessage (0 = direct MS02b deposit).
  /// Diagnostic only — used by tests to assert the garlic path was taken.
  int lastSendHopCount = 0;

  /// True when the most recent sendMessage traveled a reverse-garlic reply
  /// path (CMD_DELIVER_TAGGED over the partner's RGB hops). Diagnostic only.
  bool lastSendViaRgb = false;

  /// Shape of the reply path (RGB) the most recent sendMessage embedded:
  /// closed by our mailbox host, the pre-T162 shape ending at the last relay
  /// (no host identity from a handshake, or the payload too large for the
  /// host-closed one), or none. Diagnostic only (T162 review F5).
  OwnReplyPathShape lastOwnRgbShape = OwnReplyPathShape.none;

  /// True when the most recent sendMessage requested an R-ACK
  /// (CMD_DELIVER_ACKED with return path, MS06). Diagnostic only.
  bool lastSendAckRequested = false;

  /// Outstanding R-ACK expectations: ack tag → message + hops (MS06).
  final AckTagStore _ackTagStore = AckTagStore();

  /// T44: channel-rendezvous state (publish/refresh + recovery merge logic).
  final RendezvousManager _rendezvous = RendezvousManager();

  /// T44: outstanding `record_lookup` answers, ack session-tag hex → the
  /// channel that issued the lookup. The reverse-garlic answer arrives as a
  /// tagged mail item in our own OH mailbox and is correlated here, ahead of
  /// the R-ACK / channel-reply tag checks.
  final Map<String, String> _recordLookupTags = {};

  /// T44: how long a record-lookup ack tag stays outstanding before it is
  /// evicted (an answer is always sent, so this only bounds a lost packet).
  static const Duration _recordLookupTtl = Duration(minutes: 5);
  final Map<String, DateTime> _recordLookupTagCreatedAt = {};

  /// R-ACK-based node reliability (MS06); feeds the hop selector.
  final NodeScorer _nodeScorer = NodeScorer();

  /// No R-ACK within this window counts as a routing failure (MS06). Three
  /// polling cycles: the R-ACK has to travel its return path and wait for
  /// our next mailbox fetch, so the spec's 60 s would misfire routinely.
  static const Duration ackTimeout = Duration(seconds: 90);

  /// Registered groups by group id (MS08).
  final Map<String, _GroupState> _groups = {};

  /// Cap on buffered unknown-epoch items per group (Decision 10) — a
  /// malicious or broken peer must not grow the buffer unboundedly.
  static const int maxPendingGroupItems = 256;

  RedPandaLightClient({
    required this.selfNodeId,
    required this.selfKeys,
    List<String> seeds = defaultSeeds,
    SocketFactory? socketFactory,
    // Injectable repository for testing? For now we create it.
    PeerRepository? peerRepository,
    this.depositResponseTimeout = const Duration(seconds: 10),
    this.fetchResponseTimeout = const Duration(seconds: 10),
    // T160: hold/pairing-lookup timing (tests pass short durations).
    RendezvousTiming? rendezvousTiming,
    // Extra predicate for garlic hop candidates (tests pin local nodes).
    bool Function(PeerStats peer)? hopCandidateFilter,
    // Clock for the connection routine's time-based decisions (see [_now]).
    DateTime Function()? now,
    // DNS resolution for the alias dedup (see [_lookup]).
    Future<List<InternetAddress>> Function(String host)? lookup,
  }) : _rendezvousTiming = rendezvousTiming ?? RendezvousTiming(),
       _now = now ?? DateTime.now,
       _lookup = lookup ?? InternetAddress.lookup,
       _socketFactory =
           socketFactory ??
           // The explicit timeout matters (T27): without one, a dial started
           // while the network is down hangs for the OS SYN timeout (~2 min
           // on Linux/Android). The hanging ActivePeer occupies its _peers
           // slot, _runConnectionCheck skips occupied addresses, and no
           // fresh dial happens until the OS gives up — post-airplane-mode
           // reconnects took ~2 min even though the network was back.
           ((h, p) => Socket.connect(h, p, timeout: connectTimeout)),
       _peerRepository = peerRepository ?? InMemoryPeerRepository() {
    _hopSelector = HopSelector(
      _peerRepository,
      candidateFilter: hopCandidateFilter,
      nodeScorer: _nodeScorer,
    );
    _rgbBuilder = RgbBuilder(_hopSelector);
    _peerRepository.load().then((_) {
      _peerRepository.addAll(seeds);
      // Fast boot: Trigger immediate check after load
      _runConnectionCheck();
    });
  }

  /// Called when app goes to background
  @override
  void onPause() {
    // _isBackgrounded = true;
    _peerRepository.save();
    // Maybe reduce timer frequency?
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _runConnectionCheck(),
    );
  }

  /// Called when app resumes
  @override
  void onResume() {
    // _isBackgrounded = false;
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _runConnectionCheck(),
    );
    _runConnectionCheck(); // Immediate
    // T26 (iOS foreground-only reception): catch up NOW instead of on the
    // next poll tick — a resume is chat activity (fast cadence for the
    // activity window) and the first mailbox fetch is pulled forward, so
    // messages that arrived while suspended show up within seconds.
    if (_pollingEnabled) {
      _notePollActivity();
      _schedulePoll(const Duration(seconds: 1));
    }
  }

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      seededStream(() => [_currentStatus], _connectionStatusController.stream);

  @override
  Stream<int> get peerCountStream =>
      seededStream(() => [_sendablePeers.length], _peerCountController.stream);

  /// PROVISIONAL: Stream of currently connected peer addresses.
  Stream<List<String>> get activePeersStream => seededStream(
    () => [_verifiedAddresses(true)],
    // The peer-count controller is the change trigger; the addresses are read
    // fresh on every tick.
    _peerCountController.stream.map((_) => _verifiedAddresses(true)),
  );

  Stream<List<String>> get connectingPeersStream => seededStream(
    () => [_verifiedAddresses(false)],
    _peerCountController.stream.map((_) => _verifiedAddresses(false)),
  );

  // "Active" = can carry commands (encryption up, T156), matching the
  // aggregate status: ActivePeer reports "connected" only at that point.
  List<String> _verifiedAddresses(bool verified) => _peers.values
      .where((p) => p.canSendCommands == verified)
      .map((p) => p.address)
      .toList();

  /// Currently active peer addresses: handshake done AND transport
  /// encryption active ([ActivePeer.canSendCommands], T156).
  Set<String> get activePeerAddresses =>
      _sendablePeers.map((p) => p.address).toSet();

  /// Currently connecting (handshake or key exchange pending) addresses.
  Set<String> get connectingPeerAddresses => _peers.values
      .where((p) => !p.canSendCommands && !p.isDisconnected)
      .map((p) => p.address)
      .toSet();

  @override
  Stream<PeerStatsSnapshot> get peerStatsStream => seededStream(
    () => [_peerStatsSnapshot()],
    _peerCountController.stream.map((_) => _peerStatsSnapshot()),
  );

  PeerStatsSnapshot _peerStatsSnapshot() => PeerStatsSnapshot(
    allPeers: getDebugPeerStats(),
    activePeerAddresses: activePeerAddresses,
    connectingPeerAddresses: connectingPeerAddresses,
  );

  void _updateStatus(ConnectionStatus status) {
    // Recalculate connected peers
    int connectedCount = _sendablePeers.length;
    _peerCountController.add(connectedCount);

    // Simple aggregation: If ANY connected -> Connected.
    // If ALL disconnected -> Disconnected.
    // Logic:
    // If incoming status is connected -> set global connected.
    // If incoming is disconnected -> Check if others are connected.

    if (status == ConnectionStatus.connected) {
      // Defence in depth (T156): a late "connected" from a peer that already
      // shut down must not flip the aggregate status with nothing sendable.
      if (_sendablePeers.isEmpty) return;
      if (_currentStatus != ConnectionStatus.connected) {
        _currentStatus = ConnectionStatus.connected;
        _connectionStatusController.add(ConnectionStatus.connected);

        // Clear backoff for connected peers
        // Note: The logic here is global status, but we want per-peer reset.
        // Better to do it in the loop or listener?
        // Actually, onStatusChange is called by specific peer.
        // We don't have the peer address here easily unless passed.
        // Let's modify ActivePeer to pass itself or address?
        // Or cleaner: Iterate peers and clear for connected ones.
        for (final entry in _peers.entries) {
          if (entry.value.canSendCommands) {
            _nextRetryTime.remove(entry.key);
            _retryCounts.remove(entry.key);
          }
        }

        // T27: (re-)connected — run a catch-up poll right away instead of
        // waiting for the next scheduled tick (up to 30 s). Deliberately
        // does NOT start the fast-cadence window; a non-empty fetch does.
        // Only a FULL cycle in flight makes this redundant (it fetches every
        // mailbox and re-arms itself); a T167 follow-up fetches just the
        // notified mailboxes and keeps [_nextPollAt], so the catch-up must
        // still be scheduled then.
        if (_pollingEnabled && !_fullCycleInProgress) {
          _schedulePoll(const Duration(seconds: 1));
        }

        // T38: a subscription lives only for its connection, so re-subscribe
        // every handle for real-time Notify on (re-)connect. _peerForHandle
        // routes each subscribe to the handle's own host node (#55).
        _subscribeAllHandles();
      }
    } else if (status == ConnectionStatus.connecting) {
      if (_currentStatus != ConnectionStatus.connected) {
        _currentStatus = ConnectionStatus.connecting;
        _connectionStatusController.add(ConnectionStatus.connecting);
      }
    } else {
      // Check if any peer is connected
      // Same predicate as the connect edge (ActivePeer reports "connected"
      // only once encryption is active, T156): a peer still in its key
      // exchange must not keep the client "connected", or its later connect
      // would not re-run the edge (subscribe, catch-up poll).
      bool anyConnected = _sendablePeers.isNotEmpty;
      if (!anyConnected && _currentStatus != ConnectionStatus.disconnected) {
        _currentStatus = ConnectionStatus.disconnected;
        _connectionStatusController.add(ConnectionStatus.disconnected);
      }
    }
  }

  /// Starts (and maintains) the network connection.
  ///
  /// **Single-use contract (TD015).** A [RedPandaLightClient] is a one-shot
  /// object. [disconnect] is a *terminal* full shutdown — it permanently
  /// closes every broadcast stream controller and clears the OH registry — so
  /// calling [connect] again on the same instance would restore nothing (no
  /// mailbox polling, no incoming events) while the status still flips back to
  /// "connecting"/"connected". That silent half-dead state is the TD015 trap,
  /// so reusing a disconnected client is treated as a programming error and
  /// throws [StateError]; construct a fresh instance instead.
  ///
  /// A brief-offline / reconnect cycle is NOT this method: transient link loss
  /// is handled at the peer level ([_forceReconnect], per-[ActivePeer]
  /// redial) and the app lifecycle uses [onPause]/[onResume], neither of which
  /// tears the client down. The production isolate worker likewise never
  /// reuses a client — it builds a new [RedPandaLightClient] on every respawn.
  @override
  Future<void> connect() async {
    if (_disconnected) {
      throw StateError(
        'RedPandaLightClient.connect() called after disconnect(): this object '
        'is single-use. disconnect() is a terminal shutdown that closes all '
        'stream controllers and clears the OH registry, so it cannot be '
        'reconnected. Construct a new RedPandaLightClient instead. For a '
        'brief-offline cycle, rely on the built-in peer reconnect / '
        'onPause()/onResume() — do not call disconnect().',
      );
    }
    _updateStatus(ConnectionStatus.connecting);
    RpLog.info('RedPandaLightClient: Starting connection routine...');

    _startConnectionRoutine();
  }

  void _startConnectionRoutine() {
    _runConnectionCheck();
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _runConnectionCheck();
    });
  }

  /// Timestamp of the last [_logNotConnected] line, for its 15 s throttle.
  DateTime? _lastNotConnectedLog;

  /// Emits one aggregate line every 15 s for as long as the client is not
  /// connected, and nothing at all once it is.
  ///
  /// Called first thing in [_runConnectionCheck], so the numbers are the state
  /// the *previous* cycle left behind — before this one reaps disconnected
  /// peers and fills slots. That is deliberate: it runs on every tick, including
  /// the ones the bad-internet throttle cuts short, and a peer still counted
  /// here that is gone in the next line is itself the interesting detail.
  ///
  /// Counts only, never addresses — that is what keeps it on the info side of
  /// the privacy boundary. Everything the connection routine says about *which*
  /// peer it is dialling goes through [RpLog.debug], which is suppressed by
  /// default and which the isolate worker deliberately does not forward, so a
  /// client that fails to connect produced exactly no evidence: the emulator
  /// gate's `client never connected to the node` (T81/T89b) could not be told
  /// apart from "never dialled", "dialled and got nowhere" and "connected
  /// without the app noticing". These five numbers separate those cases.
  void _logNotConnected() {
    if (_currentStatus == ConnectionStatus.connected) {
      _lastNotConnectedLog = null;
      return;
    }
    final now = _now();
    final last = _lastNotConnectedLog;
    if (last != null && now.difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastNotConnectedLog = now;
    final verified = _peers.values.where((p) => p.isHandshakeVerified).length;
    final inBackoff = _nextRetryTime.values.where(now.isBefore).length;
    RpLog.info(
      'RedPandaLightClient: still ${_currentStatus.name} — '
      'known=${_peerRepository.knownAddresses.length} '
      'peers=${_peers.length} verified=$verified '
      'dialsInFlight=${_dialsInFlight.length} inBackoff=$inBackoff',
    );
  }

  Future<void> _runConnectionCheck() async {
    _logNotConnected();

    RpLog.debug(
      'RedPandaLightClient: Running connection check. Known peers: ${_peerRepository.knownAddresses.length}',
    );

    // 1. Cleanup disconnected
    _peers.removeWhere((address, peer) {
      if (peer.isDisconnected) {
        RpLog.debug('RedPandaLightClient: Removing disconnected peer $address');
        return true;
      }
      // Also ping active peers periodically
      if (peer.canSendCommands) {
        // If hasn't pinged in 10s, ping
        // We can do this based on timer or here
        peer.ping();
      }
      return false;
    });

    // Nodes hosting one of our own mailboxes (T163). Neither the capacity
    // trim nor the rotation may pick them: fetch, ack, renew and the Notify
    // subscription only work over the connection to exactly that node.
    final mailboxHosts = _ownMailboxHostAddresses();

    final limit = connectionLimit(
      peerAddresses: _peers.keys,
      protected: mailboxHosts,
    );

    // 2. Classify Current Peers
    // A. Verify Capacity: trim the worst extra peers, never a mailbox host
    // while an unprotected peer is left.
    if (_peers.length > limit) {
      final victims = pickOverCapacityVictims(
        peers: [
          for (final p in _peers.values)
            (address: p.address, latencyMs: p.averageLatencyMs),
        ],
        protected: mailboxHosts,
        limit: limit,
      );
      for (final address in victims) {
        RpLog.debug(
          'RedPandaLightClient: Over capacity. Disconnecting $address',
        );
        // Not a failure of the node: no score penalty (as for a rotation).
        _intentionalDisconnects.add(address);
        _peers[address]?.disconnect();
      }
    }

    // B. Rotate Roaming Peers
    final victimAddress = pickRotationVictim(
      verifiedPeers: [
        for (final p in _peers.values)
          if (p.isHandshakeVerified)
            (
              address: p.address,
              connectedSince: p.connectedSince,
              score: _peerRepository.getPeer(p.address)?.score ?? 0,
            ),
      ],
      protected: mailboxHosts,
      slotsTaken: _peers.length,
      limit: limit,
      now: DateTime.now(),
    );
    final victim = victimAddress == null ? null : _peers[victimAddress];
    if (victim != null) {
      final age = DateTime.now().difference(victim.connectedSince).inSeconds;
      RpLog.debug(
        'RedPandaLightClient: Rotating ONE roaming peer ${victim.address} (Connected ${age}s). Keeping others. '
        'Own mailbox hosts (never rotated): ${mailboxHosts.toList()..sort()}',
      );
      _intentionalDisconnects.add(victim.address);
      victim.disconnect();
    }

    // 3. Slot Filling
    // Identify Best Candidates from Repository
    // Strategy: Reserve 3 slots for Core (Best), 2 for Roaming (Random/New)
    final int targetCore = 3;

    final candidates = _peerRepository.getBestPeers(10);
    int connectedCount = _peers.length;

    final toConnect = <String>[];

    // A. CORE: Fill up to targetCore with Best Peers
    for (final candidate in candidates) {
      if (connectedCount >= limit) break; // Hard limit
      if (connectedCount >= targetCore && _peers.length >= targetCore) {
        // If we already have enough core-like connections, stop filling from top list
        // Note: _peers.length includes current connections. We need to be careful not to count roaming as core?
        // Actually, we just want to ensure we don't fill ALL slots with candidates.
        // We break if we have reached the "Core" saturation for this loop.
        break;
      }

      if (!_peers.containsKey(candidate.address) &&
          !_dialsInFlight.contains(candidate.address)) {
        if (_waitInBackoff(candidate.address)) continue;
        toConnect.add(candidate.address);
        connectedCount++;
      }
    }

    // Random filling if we still have space (Roaming)
    if (connectedCount < limit) {
      final all = _peerRepository.knownAddresses.toList()..shuffle();
      for (final addr in all) {
        if (connectedCount >= limit) break;
        if (!_peers.containsKey(addr) &&
            !_dialsInFlight.contains(addr) &&
            !toConnect.contains(addr)) {
          if (_waitInBackoff(addr)) continue;
          toConnect.add(addr);
          connectedCount++;
        }
      }
    }

    // Nothing to dial and nothing connected: every known address is either
    // occupied or still inside its retry backoff. Nothing left for this cycle.
    //
    // There is deliberately no extra "bad internet" throttle here (TD078).
    // An earlier one set a flag in this branch and made the next ~10 s of
    // checks return immediately. It never fired where it was meant to — after
    // an outage every address sits in backoff, and the flag was gated on
    // *no* address having been skipped for backoff — and switching it on
    // would have been a regression: the 3 s timer keeps ticking either way,
    // so the throttle saves no wakeup and no traffic (this branch does pure
    // in-memory bookkeeping, the dial suppression is entirely the backoff
    // map's work), while it would delay the first redial after a 2 s backoff
    // expires by up to ~9 s — the opposite of what T27 tuned the 30 s backoff
    // cap for. See the outage-cycle test in connection_logic_test.dart.
    if (toConnect.isEmpty && _peers.isEmpty) {
      RpLog.debug('RedPandaLightClient: No peer left to dial this cycle.');
      return;
    }

    // 4. Connect
    // Claim the slots BEFORE the first await: everything below suspends, and a
    // concurrent check must not pick the same address again (see
    // [_dialsInFlight]).
    final claimed = toConnect.toSet();
    _dialsInFlight.addAll(claimed);

    try {
      for (final address in toConnect) {
        try {
          final resolved = await _resolveEndpoint(address);
          if (_disconnected) break; // shut down during the lookup
          // Everything from here to `_peers[address] = peer` is synchronous
          // (see [_resolvedEndpoints]).
          _resolvedEndpoints[address] = resolved;
          if (_isAliasOfConnected(address, resolved)) {
            // E.g. a host-name seed next to its own IP. Park it
            // (without scoring a failure) so a permanent alias does not take
            // a dial slot in every check.
            _nextRetryTime[address] = _now().add(aliasRetryDelay);
            continue;
          }

          late final ActivePeer peer;
          peer = ActivePeer(
            address: address,
            selfNodeId: selfNodeId,
            selfKeys: selfKeys,
            socketFactory: _socketFactory,
            onStatusChange: (status) {
              // The client-wide connect edge in [_updateStatus] subscribes
              // every handle; it only fires for the FIRST sendable peer. A
              // mailbox host that (re)connects while other peers stay up
              // needs its own re-subscribe (T163).
              final wasConnected = _currentStatus == ConnectionStatus.connected;
              if (status == ConnectionStatus.connected) _diagConnUp(peer);
              _updateStatus(status);
              if (status == ConnectionStatus.connected && wasConnected) {
                _onPeerConnected(address);
              }
            },
            onNodeIdDiscovered: (nodeId, encryptionPublicKey) {
              _peerRepository.updatePeer(
                address,
                nodeId: nodeId,
                encryptionPublicKey: encryptionPublicKey,
              );
            },
            onDisconnect: () {
              _diagConnDown(
                peer,
                intentional: _intentionalDisconnects.contains(address),
              );
              if (_intentionalDisconnects.contains(address)) {
                RpLog.debug(
                  'RedPandaLightClient: Peer $address disconnected intentionally (Rotation). No failure recorded.',
                );
                _intentionalDisconnects.remove(address);
                _handleBackoff(address); // Still backoff to ensure we rotate
              } else {
                _recordConnectionFailure(address);
              }
            },
            onPeersReceived: (peers) {
              RpLog.debug(
                'RedPandaLightClient: Received ${peers.length} peers from $address',
              );
              for (final peer in peers) {
                // Stores identity (node id + X25519 key, MS04) when included.
                _peerRepository.updatePeer(
                  peer.address,
                  nodeId: peer.nodeId,
                  encryptionPublicKey: peer.encryptionPublicKey,
                );
              }
              // Trigger check to potentially fill slots immediately?
              // _runConnectionCheck();
            },
            onPeerListRequested: () {
              // Return top 20 best peers to share. IP literals only: nodes
              // drop gossiped host names (redpandaj
              // Utils.isPlausibleAdvertisedAddress), seeds are local config.
              // Filter before capping so host-name entries (seeds) never
              // eat the 20-slot budget (Copilot review on #129).
              return _peerRepository
                  .getBestPeers(60)
                  .map((p) => p.address)
                  .where(_isIpLiteralAddress)
                  .take(20)
                  .toList();
            },
            onHandshakeComplete: () {
              _peerRepository.updatePeer(address, isSuccess: true);
              // Clear backoff
              _nextRetryTime.remove(address);
            },
            onLatencyUpdate: (latency) {
              _peerRepository.updatePeer(
                address,
                latencyMs: latency,
                isSuccess: true,
              );
            },
          );
          peer.onCommandResponse = _handleCommandResponse;
          _peers[address] = peer;
          peer.connect(); // Fire and forget (it is async inside)
        } catch (e) {
          RpLog.debug(
            'RedPandaLightClient: Failed to initiate peer $address: $e',
          );
          _diagDialFailed(address, 'init_failed: $e', ageMs: 0, node: null);
          // Same failure bookkeeping as a dropped connection: this peer never
          // reached _peers, so its onDisconnect will never fire and only the
          // backoff armed here keeps the next check from redialling it on the
          // very next 3 s tick.
          _recordConnectionFailure(address);
        } finally {
          // Released in the same synchronous step that inserted into [_peers]
          // (and on the alias-skip / error paths), so there is never a moment
          // where neither map nor set holds the address.
          claimed.remove(address);
          _dialsInFlight.remove(address);
        }
      }
    } finally {
      // Safety net for an unexpected throw before the loop released a claim: a
      // leaked entry would block that address from ever being dialled again.
      // Only what we still hold is released — an address a later check has
      // re-claimed in the meantime is no longer in [claimed].
      _dialsInFlight.removeAll(claimed);
    }
  }

  // --- Helper Methods ---

  /// Connection limit for this cycle (T163 review B): [maxConnections], plus
  /// exactly one extra slot while EVERY regular slot is held by a node that
  /// hosts one of our own mailboxes ([protected]). Those nodes are never
  /// rotated, so without the extra slot nothing would rotate and the client
  /// would stop meeting new nodes. The extra connection is an ordinary
  /// unprotected roaming peer and rotates like one.
  ///
  /// Depends only on which hosts are connected, not on the repository
  /// scores, so it does not flip between two values as latencies move.
  /// Pure; public for tests only.
  static int connectionLimit({
    required Iterable<String> peerAddresses,
    required Set<String> protected,
  }) {
    final hosts = peerAddresses.where(protected.contains).length;
    return hosts >= maxConnections ? maxConnections + 1 : maxConnections;
  }

  /// The roaming peer the connection check disconnects this cycle, or null.
  ///
  /// Nodes in [protected] (hosting one of our own mailboxes, T163) are never
  /// victims — rotating one away killed its Notify subscription and left
  /// fetches failing until the redial (~4–5 s per message and spurious T21
  /// failovers in the 5-node lab).
  ///
  /// Slots: [coreSlots] stable + [roamingSlots] rotating. A connected host is
  /// pinned just like a core peer, so it uses up core budget first; the core
  /// budget left over goes to the best-scored unprotected peers, every other
  /// unprotected peer is roaming (T163 review B: when hosts filled the
  /// roaming slots, the old "not in the repository's best three" rule left
  /// nothing to rotate). Rotation starts once [slotsTaken] reaches [limit]
  /// (see [connectionLimit]); the victim is the oldest roaming peer
  /// connected for at least [minAge].
  ///
  /// Pure (no client state) so the selection is testable without sockets or
  /// a 10 s wall-clock wait. Public for tests only.
  static String? pickRotationVictim({
    required Iterable<({String address, DateTime connectedSince, double score})>
    verifiedPeers,
    required Set<String> protected,
    required int slotsTaken,
    required int limit,
    required DateTime now,
    Duration minAge = const Duration(seconds: 10),
  }) {
    if (slotsTaken < limit) return null;
    final peers = verifiedPeers.toList();
    final hosts = peers.where((p) => protected.contains(p.address)).length;
    final unprotected =
        peers.where((p) => !protected.contains(p.address)).toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    final coreBudget = max(0, coreSlots - hosts);
    final candidates =
        unprotected
            .skip(coreBudget)
            .where((p) => now.difference(p.connectedSince) >= minAge)
            .toList()
          ..sort((a, b) => a.connectedSince.compareTo(b.connectedSince));
    return candidates.firstOrNull?.address;
  }

  /// Peers the capacity trim disconnects when more than [limit] are open:
  /// everything past the first [limit] after ordering [protected] nodes
  /// first, then lower latency first. A protected node is therefore only
  /// trimmed when there are more protected nodes than [limit].
  /// Pure; public for tests only.
  static List<String> pickOverCapacityVictims({
    required Iterable<({String address, int latencyMs})> peers,
    required Set<String> protected,
    required int limit,
  }) {
    final sorted = peers.toList()
      ..sort((a, b) {
        final hostA = protected.contains(a.address) ? 1 : 0;
        final hostB = protected.contains(b.address) ? 1 : 0;
        if (hostA != hostB) return hostB - hostA;
        return a.latencyMs.compareTo(b.latencyMs);
      });
    return [for (final p in sorted.skip(limit)) p.address];
  }

  /// A peer reached [ActivePeer.canSendCommands] while the client was
  /// already connected (T163). A Notify subscription lives only for its
  /// connection, so every own mailbox this peer hosts is re-subscribed, and
  /// the next poll is pulled forward to collect what arrived while the host
  /// was unreachable — the same two steps the client-wide connect edge in
  /// [_updateStatus] runs for all handles. Before this, a host that
  /// reconnected after the first connect edge (rotation, T33 forced
  /// reconnect, a dropped socket) stayed unsubscribed until the client lost
  /// ALL peers, and its mail arrived only with the poll.
  void _onPeerConnected(String address) {
    final peer = _peers[address];
    if (peer == null || !peer.canSendCommands) return;
    var hosted = 0;
    for (final oh in List.of(_registeredOHs)) {
      final endpoint = oh.serverEndpoint;
      if (endpoint == null || !identical(_livePeerFor(endpoint), peer)) {
        continue;
      }
      _enqueueSubscribe(oh);
      hosted++;
    }
    if (hosted == 0) return;
    // Address only on debug: together with "hosts our mailbox" it is exactly
    // what the privacy boundary keeps off the info level.
    RpLog.info(
      'RedPandaLightClient: a mailbox host reconnected — '
      're-subscribing $hosted handle(s)',
    );
    RpLog.debug('RedPandaLightClient: reconnected mailbox host: $address');
    const catchUp = Duration(seconds: 1);
    final next = _nextPollAt;
    // As above: a follow-up in flight (T167) does not fetch this host's
    // mailboxes, only a full cycle does.
    if (_pollingEnabled &&
        !_fullCycleInProgress &&
        (next == null || next.isAfter(DateTime.now().add(catchUp)))) {
      _schedulePoll(catchUp);
    }
  }

  /// Addresses of the peers hosting our own mailboxes (T163): every
  /// registered, not yet locally expired OH's recorded endpoint plus the
  /// live peer serving it under another name ([_hostAddresses]), and the
  /// target of every registration still waiting for its response
  /// ([_registrationsInFlight]).
  Set<String> _ownMailboxHostAddresses() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return {
      for (final oh in _registeredOHs)
        if (oh.serverEndpoint != null && oh.expiresAtMs > nowMs)
          ..._hostAddresses(oh.serverEndpoint),
      ..._registrationsInFlight.keys,
    };
  }

  /// [_ownMailboxHostAddresses] as the connection check sees it. Tests only.
  Set<String> get ownMailboxHostAddressesForTesting =>
      _ownMailboxHostAddresses();

  /// Peer address → number of [registerOutboundHandle] calls currently
  /// waiting on it (T163 review C). Its node is about to host a mailbox, so
  /// it is protected from rotation before the registration lands in
  /// [_registeredOHs] — the register round trip can take up to 10 s, and the
  /// peer it picks (the oldest sendable one) is the preferred rotation
  /// victim.
  final Map<String, int> _registrationsInFlight = {};

  /// Whether [address] is still inside its retry backoff and must not be
  /// dialled in this cycle.
  bool _waitInBackoff(String address) {
    final next = _nextRetryTime[address];
    return next != null && _now().isBefore(next);
  }

  /// Records a lost/failed connection to [address]: arms the retry backoff
  /// AND scores the failure against the peer, in that order and in ONE
  /// synchronous step (TD080).
  ///
  /// The order is the contract, not an accident. `updatePeer(isFailure: true)`
  /// is the client's outward "this dial failed" signal; anything that reacts
  /// to it — a repository listener, a connection check kicked off from one —
  /// must already see the backoff, otherwise it immediately re-dials the
  /// address that just failed. Both halves must also stay in the same
  /// synchronous step: an `await` between them reopens the same window.
  /// `connection_logic_test.dart` pins this by re-entering a connection check
  /// from inside the failure report.
  void _recordConnectionFailure(String address) {
    _handleBackoff(address);
    _peerRepository.updatePeer(address, isFailure: true);
  }

  void _handleBackoff(String address) {
    int count = (_retryCounts[address] ?? 0) + 1;
    _retryCounts[address] = count;

    // Exponential backoff: 2s, 4s, 8s...
    // 2 * (2^(count-1))
    // count > 5 already hits the cap; clamping first also keeps the shift
    // from overflowing for an address that fails for hours.
    int seconds = count > 5 ? 30 : 2 * (1 << (count - 1));
    // Cap at 30 s (was 5 min): after a ~1 min outage the old cap made the
    // next reconnect attempt wait up to several minutes — the dominant part
    // of post-airplane-mode delivery delay (T27). A capped attempt is one
    // TCP dial per address per 30 s, negligible traffic/battery.
    if (seconds > 30) seconds = 30;

    _nextRetryTime[address] = _now().add(Duration(seconds: seconds));
    // T180: the backoff of a repeated identical dial failure is as
    // suppressed as the failure itself (see [_diagDialFailed]).
    if (_diagSilentBackoff.remove(address)) return;
    RpDiag.emit(DiagEvt.connBackoff, {
      DiagKey.addr: address,
      DiagKey.retry: count,
      DiagKey.waitMs: seconds * 1000,
    });
  }

  // --- Field diagnostics (T180) ---------------------------------------------

  /// Whether [address] hosts one of our own mailboxes (diagnostics only).
  bool _diagIsMailboxHost(String address) =>
      _ownMailboxHostAddresses().contains(address);

  /// Address → class of the dial failure last reported for it (T180). While
  /// an address keeps failing for the same reason, only its FIRST failure is
  /// emitted: offline, every known address fails every ≤30 s for hours, and
  /// that flood would evict the start of the outage from the app's buffer.
  /// Cleared when the address connects or fails differently.
  final Map<String, String> _diagDialFailClass = {};

  /// Suppressed failed dials per address since its last reported failure;
  /// reported on that address's next `conn.up` / differing `conn.down`.
  final Map<String, int> _diagDialFailSuppressed = {};

  /// Addresses whose next `conn.backoff` belongs to a suppressed failure.
  final Set<String> _diagSilentBackoff = {};

  /// Suppressed failed dials since the last `fetch.summary`.
  int _diagSuppressedDials = 0;

  /// Bounded like the peer repository's address set; this only caps it.
  static const int _diagDialFailCapacity = 256;

  /// `dial_failed: SocketException: … errno = 101` → `dial_failed#101`:
  /// the reason without the parts that differ on every attempt (local
  /// port, message text).
  static String _diagFailureClass(String reason) {
    final head = reason.split(':').first.trim();
    final errno = RegExp(r'errno\s*=\s*(\d+)').firstMatch(reason)?.group(1);
    return errno == null ? head : '$head#$errno';
  }

  /// A dial (or a connection that never came up) failed: emits `conn.down`
  /// unless it repeats the address's last reported failure class.
  void _diagDialFailed(
    String address,
    String reason, {
    required int ageMs,
    required String? node,
    bool intentional = false,
  }) {
    if (!RpDiag.enabled) return;
    final cls = _diagFailureClass(reason);
    if (!intentional && _diagDialFailClass[address] == cls) {
      _diagDialFailSuppressed.update(address, (n) => n + 1, ifAbsent: () => 1);
      _diagSuppressedDials++;
      _diagSilentBackoff.add(address);
      return;
    }
    if (_diagDialFailClass.length >= _diagDialFailCapacity &&
        !_diagDialFailClass.containsKey(address)) {
      _diagDialFailClass.remove(_diagDialFailClass.keys.first);
    }
    if (!intentional) _diagDialFailClass[address] = cls;
    RpDiag.emit(DiagEvt.connDown, {
      DiagKey.addr: address,
      DiagKey.node: node,
      DiagKey.reason: reason,
      DiagKey.ageMs: ageMs,
      DiagKey.wasUp: false,
      DiagKey.intentional: intentional,
      DiagKey.mailboxHost: _diagIsMailboxHost(address),
      DiagKey.peers: _sendablePeers.length,
      DiagKey.dialFail: _diagDialFailSuppressed.remove(address),
    });
  }

  /// Suppressed failed dials so far (tests).
  @visibleForTesting
  int get diagSuppressedDialsForTesting => _diagSuppressedDials;

  void _diagConnUp(ActivePeer peer) {
    if (!RpDiag.enabled) return;
    _diagDialFailClass.remove(peer.address);
    RpDiag.emit(DiagEvt.connUp, {
      DiagKey.dialFail: _diagDialFailSuppressed.remove(peer.address),
      DiagKey.addr: peer.address,
      DiagKey.node: peer.discoveredNodeId,
      DiagKey.dialMs: DateTime.now()
          .difference(peer.connectedSince)
          .inMilliseconds,
      DiagKey.mailboxHost: _diagIsMailboxHost(peer.address),
      DiagKey.peers: _sendablePeers.length,
    });
  }

  void _diagConnDown(ActivePeer peer, {required bool intentional}) {
    if (!RpDiag.enabled) return;
    final upSince = peer.upSince;
    if (upSince == null) {
      _diagDialFailed(
        peer.address,
        peer.disconnectReason ?? 'unknown',
        ageMs: DateTime.now().difference(peer.connectedSince).inMilliseconds,
        node: peer.discoveredNodeId,
        intentional: intentional,
      );
      return;
    }
    RpDiag.emit(DiagEvt.connDown, {
      DiagKey.addr: peer.address,
      DiagKey.node: peer.discoveredNodeId,
      DiagKey.reason: peer.disconnectReason ?? 'unknown',
      DiagKey.ageMs: DateTime.now().difference(upSince).inMilliseconds,
      DiagKey.wasUp: true,
      DiagKey.intentional: intentional,
      DiagKey.mailboxHost: _diagIsMailboxHost(peer.address),
      DiagKey.peers: _sendablePeers.length,
    });
  }

  /// State of the connection to the node at [endpoint] — the conditions an
  /// `oh.unreachable` / `oh.failover` event is judged by (T168).
  Map<String, Object?> _diagHostConditions(String? endpoint) {
    if (endpoint == null) return const {};
    final live = _livePeerFor(endpoint);
    final String state;
    if (live == null) {
      state = 'absent';
    } else if (live.canSendCommands) {
      state = 'connected';
    } else if (live.isDisconnected) {
      state = 'disconnected';
    } else {
      state = 'connecting';
    }
    final next = _nextRetryTime[endpoint];
    final now = _now();
    final hostAddresses = _hostAddresses(endpoint);
    return {
      DiagKey.hostState: state,
      DiagKey.hostRetry: _retryCounts[endpoint] ?? 0,
      DiagKey.hostBackoffMs: next != null && now.isBefore(next)
          ? next.difference(now).inMilliseconds
          : 0,
      DiagKey.hostDialing: _dialsInFlight.contains(endpoint),
      DiagKey.altPeers: _sendablePeers
          .where((p) => !hostAddresses.contains(p.address))
          .length,
    };
  }

  /// Comma-separated node ids of [hops] (diagnostics only).
  static String _diagHopIds(List<GarlicHop> hops) =>
      hops.map((h) => _hexEncode(h.nodeId)).join(',');

  /// Message id → when its first send attempt left, for the latency of
  /// `ack.delivered`. Filled only while diagnostics are on; bounded.
  final LinkedHashMap<String, int> _diagSentAtMs = LinkedHashMap();
  static const int _diagSentAtCapacity = 512;

  void _diagNoteSent(String? messageIdHex) {
    if (messageIdHex == null) return;
    if (_diagSentAtMs.containsKey(messageIdHex)) return;
    while (_diagSentAtMs.length >= _diagSentAtCapacity) {
      _diagSentAtMs.remove(_diagSentAtMs.keys.first);
    }
    _diagSentAtMs[messageIdHex] = DateTime.now().millisecondsSinceEpoch;
  }

  /// One `send.attempt` per garlic packet handed to [submitVia]. Never
  /// throws: diagnostics must not turn a completed send into an error.
  void _diagSendAttempt({
    required String kind,
    required ActivePeer submitVia,
    required List<GarlicHop> hops,
    required List<int> targetOhId,
    required Uint8List packet,
    required String channelId,
    String? messageIdHex,
    String? targetHost,
    int? routeIndex,
    ReturnPathBlock? returnPath,
    String? sessionTagHex,
  }) {
    if (!RpDiag.enabled) return;
    try {
      final submitNode = submitVia.discoveredNodeId;
      RpDiag.emit(DiagEvt.sendAttempt, {
        DiagKey.kind: kind,
        DiagKey.msg: messageIdHex,
        DiagKey.channel: channelId,
        DiagKey.target: _hexEncode(targetOhId),
        DiagKey.targetHost: targetHost,
        DiagKey.route: routeIndex,
        DiagKey.hops: _diagHopIds(hops),
        DiagKey.submit: submitVia.address,
        DiagKey.submitNode: submitNode,
        DiagKey.pktHash: RpDiag.hash16(packet),
        DiagKey.ackRequested: returnPath != null,
        DiagKey.ackTag: returnPath == null
            ? null
            : _hexEncode(returnPath.ackSessionTag),
        DiagKey.retHops: returnPath == null
            ? null
            : _diagHopIds(returnPath.hops),
        DiagKey.selfHop:
            hops.length == 1 &&
            submitNode != null &&
            _hexEncode(hops.single.nodeId) == submitNode,
        DiagKey.sessionTag: sessionTagHex,
      });
      if (kind != 'channel-ack') _diagNoteSent(messageIdHex);
    } catch (_) {}
  }

  /// Per-minute polling summary (`fetch.summary`): routine polls are
  /// counted here instead of each producing an event.
  final _DiagFetchStats _diagFetchStats = _DiagFetchStats();

  /// Runs at the end of every poll cycle. Emits once a minute when
  /// something happened (failures, items, Notifies, suppressed dials, rate
  /// limit drops), otherwise only as a heartbeat every
  /// [_DiagFetchStats.heartbeatMs] — an idle device must not wake the radio
  /// for an upload every minute. Clock: [_now].
  void _diagMaybeFlushFetchSummary() {
    final nowMs = _now().millisecondsSinceEpoch;
    if (!RpDiag.enabled) {
      _diagFetchStats.reset(nowMs);
      _diagSuppressedDials = 0;
      return;
    }
    final interesting =
        _diagFetchStats.failures > 0 ||
        _diagFetchStats.items > 0 ||
        _diagFetchStats.notifies > 0 ||
        _diagSuppressedDials > 0 ||
        RpDiag.dropped > 0;
    if (!_diagFetchStats.due(nowMs, interesting: interesting)) return;
    RpDiag.emit(DiagEvt.fetchSummary, {
      DiagKey.windowMs: nowMs - _diagFetchStats.sinceMs!,
      DiagKey.dialFail: _diagSuppressedDials,
      DiagKey.polls: _diagFetchStats.polls,
      DiagKey.fetchOk: _diagFetchStats.ok,
      DiagKey.fetchFail: _diagFetchStats.failures,
      DiagKey.items: _diagFetchStats.items,
      DiagKey.notifies: _diagFetchStats.notifies,
      DiagKey.mailboxes: _registeredOHs.length,
      DiagKey.peers: _sendablePeers.length,
      DiagKey.intervalS: _pollInterval.inSeconds,
      DiagKey.diagDropped: RpDiag.takeDropped(),
    });
    _diagFetchStats.reset(nowMs);
    _diagSuppressedDials = 0;
  }

  /// Runs the summary check as the end of a poll cycle would (tests).
  @visibleForTesting
  void diagFlushFetchSummaryForTesting() => _diagMaybeFlushFetchSummary();

  /// Tears down a suspected half-open connection and redials immediately
  /// (T33). Without this, every fetch into the dead socket costs a full
  /// [fetchResponseTimeout] and reconnect only happens once the OS notices
  /// the peer is gone — after an emulator kill/restart that took ~3 timeout
  /// cycles (~33 s) and pushed the S3 catch-up over its 60 s budget.
  Future<void> _forceReconnect(ActivePeer peer) async {
    RpLog.info(
      'RedPandaLightClient: ${peer.consecutiveFetchTimeouts} consecutive '
      'fetch timeouts on ${peer.address} — dropping suspected half-open '
      'connection and redialing',
    );
    // Intentional: the node is not proven bad, the CONNECTION is — do not
    // score a failure against the address.
    _intentionalDisconnects.add(peer.address);
    await peer.disconnect();
    // The disconnect callback applies the regular retry backoff; clear it so
    // the redial happens on this connection check, not seconds later.
    _nextRetryTime.remove(peer.address);
    _retryCounts.remove(peer.address);
    await _runConnectionCheck();
  }

  /// Whether one of [endpoints] belongs to a live entry of [_peers] other
  /// than [address] itself.
  bool _isAliasOfConnected(String address, Set<String> endpoints) {
    for (final entry in _peers.entries) {
      if (entry.key == address || entry.value.isDisconnected) continue;
      final known = _resolvedEndpoints[entry.key];
      if (known != null && known.any(endpoints.contains)) return true;
    }
    return false;
  }

  /// The live peer serving [endpoint]: the connection under that exact
  /// address, else one under another name of the same `ip:port` (T154 alias
  /// dedup only ever keeps one of them connected). Falls back to the exact
  /// entry, live or not, so callers keep their previous view of it.
  ActivePeer? _livePeerFor(String endpoint) {
    final exact = _peers[endpoint];
    if (exact != null && !exact.isDisconnected) return exact;
    final wanted = _resolvedEndpoints[endpoint] ?? _literalEndpoint(endpoint);
    if (wanted == null || wanted.isEmpty) return exact;
    for (final entry in _peers.entries) {
      if (entry.value.isDisconnected) continue;
      final known = _resolvedEndpoints[entry.key];
      if (known != null && known.any(wanted.contains)) return entry.value;
    }
    return exact;
  }

  /// [endpoint] plus the address of the live peer serving it under another
  /// name (see [_livePeerFor]) — for excluding an OH's host node by address.
  Set<String> _hostAddresses(String? endpoint) => {
    ?endpoint,
    if (endpoint != null) ?_livePeerFor(endpoint)?.address,
  };

  /// Node identity of the live peer serving [endpoint] (under any of its
  /// names), for excluding an OH's host node from its own garlic routes even
  /// when the peer list knows it under a different address.
  String? _hostNodeId(String? endpoint) =>
      endpoint == null ? null : _livePeerFor(endpoint)?.discoveredNodeId;

  /// T162: the node hosting our own mailbox [ownOh] as the closing hop of a
  /// path that ends in that mailbox (our RGBs and R-ACK return paths).
  ///
  /// Without it the last relay receives a deliver for an OH it does not host
  /// and has to resolve the host through the DHT (MS02b `OhForwarder`). On
  /// the testnet nodes that lookup is rejected whenever the same node looked
  /// the same OH up in the last 30 s (the anti-loop blacklist of
  /// `KademliaSearchJob`) — and a reply plus the R-ACK of the message it
  /// answers hit the same OH within milliseconds, so replies were dropped
  /// with HANDLE_EXPIRED after a 15 s parked retry. With the host closing the
  /// path the deliver is deposited locally; no node resolves anything. The
  /// last relay no longer learns the oh_id either (only the host, which
  /// knows it anyway, decrypts the deliver layer).
  ///
  /// The host's identity (node id AND X25519 key) is taken only from our
  /// own handshake with the live connection serving the OH endpoint — never
  /// from the peer repository, whose entries any node can overwrite with
  /// its peer lists (T162 review F1: a stale or planted pair would make the
  /// host unable to decrypt — or a third node able to drop — every reply
  /// and every R-ACK). Null without such a connection; the path then ends at
  /// the last relay as before (pre-T162 shape).
  GarlicHop? _ownHostHop(OHRegistration ownOh) {
    final endpoint = ownOh.serverEndpoint;
    if (endpoint == null) return null;
    // Only a connection that is still up (review G3): _livePeerFor may hand
    // back a disconnected entry until the next connection check removes it.
    final live = _livePeerFor(endpoint);
    return live == null || live.isDisconnected ? null : _selfHop(live);
  }

  /// T162: [relays] closed by the host of [ownOh] (see [_ownHostHop]).
  ///
  /// Without relays the path stays empty: a 0-hop return path makes the
  /// depositing node the final station (local deposit, MS02b otherwise),
  /// while `[host]` would make it build an onion whose first hop may be
  /// itself — in a single-node network (T45 self-hop) the depositing node IS
  /// the host and has no route to itself, so the R-ACK was dropped. A relay
  /// that is the host under another address is removed rather than letting
  /// the host forward to itself.
  List<GarlicHop> _closeAtOwnHost(
    List<GarlicHop> relays,
    OHRegistration ownOh,
  ) {
    if (relays.isEmpty) return relays;
    final host = _ownHostHop(ownOh);
    if (host == null) return relays;
    final hostHex = _hexEncode(host.nodeId);
    final onlyRelays = [
      for (final hop in relays)
        if (_hexEncode(hop.nodeId) != hostHex) hop,
    ];
    return onlyRelays.isEmpty ? onlyRelays : [...onlyRelays, host];
  }

  /// T162: the hops of a path that the [NodeScorer] should learn from — the
  /// relays, without a closing mailbox host. The closing host is never a
  /// relay choice (it is fixed by where the OH lives), so crediting or
  /// blaming it would only skew its score as a relay in OTHER channels.
  /// [closingHostHex] is our own host for our return paths; a partner's RGB
  /// longer than [defaultHopCount] ends at the partner's host.
  Iterable<String> _scoredHopIds(
    List<GarlicHop> hops, {
    String? closingHostHex,
  }) sync* {
    for (var i = 0; i < hops.length; i++) {
      final hex = _hexEncode(hops[i].nodeId);
      final isLast = i == hops.length - 1;
      if (isLast && (hex == closingHostHex || hops.length > defaultHopCount)) {
        continue;
      }
      yield hex;
    }
  }

  /// T162 route diagnostics (debug level only, i.e. only in a lab/test client
  /// log): `address/nodeId-prefix` of a garlic hop as the peer list knows it.
  String _diagHop(List<int> nodeId) {
    final hex = _hexEncode(nodeId);
    for (final address in _peerRepository.knownAddresses) {
      if (_peerRepository.getPeer(address)?.nodeId == hex) {
        return '$address/${hex.substring(0, 8)}';
      }
    }
    return '?/${hex.substring(0, 8)}';
  }

  /// T162: `a > b > c` for a hop list, see [_diagHop].
  String _diagRoute(List<GarlicHop> hops) =>
      hops.isEmpty ? '(none)' : hops.map((h) => _diagHop(h.nodeId)).join(' > ');

  /// T162: one debug line per garlic send naming every station, the target
  /// mailbox and the return path of the requested R-ACK. Built only when
  /// debug logging is on (hop ids and OH ids are privacy-sensitive).
  void _diagSend(
    String kind, {
    required String channelId,
    required List<GarlicHop> hops,
    required List<int> ohId,
    String? messageIdHex,
    ReturnPathBlock? returnPath,
  }) {
    if (RpLog.minLevel != LogLevel.debug) return;
    // Diagnostics must never turn a completed send into an error (the RGB
    // would then be reused): build the line defensively.
    try {
      _diagSendLine(kind, channelId, hops, ohId, messageIdHex, returnPath);
    } catch (_) {}
  }

  void _diagSendLine(
    String kind,
    String channelId,
    List<GarlicHop> hops,
    List<int> ohId,
    String? messageIdHex,
    ReturnPathBlock? returnPath,
  ) {
    final rp = returnPath == null
        ? 'none'
        : 'ackOh=${_hexEncode(returnPath.ackOhId).substring(0, 8)} '
              'via ${_diagRoute(returnPath.hops)}';
    RpLog.debug(
      'RedPandaLightClient: T162 route $kind msg=${messageIdHex ?? '-'} '
      'channel=${channelId.substring(0, 8)} '
      'oh=${_hexEncode(ohId).substring(0, 8)} '
      'hops=${_diagRoute(hops)} exit=${hops.isEmpty ? '-' : _diagHop(hops.last.nodeId)} '
      'returnPath=$rp',
    );
  }

  /// `{ip:port}` for an IP-literal [address], null for a host name or a
  /// malformed address.
  static Set<String>? _literalEndpoint(String address) {
    final parts = address.split(':');
    if (parts.length != 2) return null;
    final literal = InternetAddress.tryParse(parts[0]);
    return literal == null ? null : {'${literal.address}:${parts[1]}'};
  }

  static bool _isIpLiteralAddress(String address) =>
      InternetAddress.tryParse(address.split(':').first) != null;

  /// The `ip:port` endpoints [address] (`host:port`) resolves to. IP literals
  /// skip DNS (TD260). A failed or timed-out lookup yields an empty set: the
  /// address is then not recognised as an alias and simply dialled, where
  /// the same failure ends in the regular backoff.
  Future<Set<String>> _resolveEndpoint(String address) async {
    final literal = _literalEndpoint(address);
    if (literal != null) return literal;
    final parts = address.split(':');
    if (parts.length != 2) return const {};
    final host = parts[0];
    final port = parts[1];
    try {
      final lookup = await _lookup(host).timeout(lookupTimeout);
      return {for (final addr in lookup) '${addr.address}:$port'};
    } catch (e) {
      RpLog.debug('RedPandaLightClient: Lookup of $host failed: $e');
      return const {};
    }
  }

  @override
  Future<void> addPeer(String address) async {
    _peerRepository.updatePeer(address);
    _runConnectionCheck();
  }

  /// Terminal full shutdown (see [connect] for the single-use contract):
  /// stops all timers, disconnects every peer, clears all in-memory state and
  /// permanently closes every broadcast stream controller. The instance is
  /// dead afterwards — a subsequent [connect] throws [StateError]. Idempotent:
  /// closing already-closed controllers is a no-op.
  @override
  Future<void> disconnect() async {
    if (_disconnected) return; // idempotent: the teardown runs exactly once
    _disconnected = true;
    _connectionTimer?.cancel();
    _pollingEnabled = false; // stop the self-rescheduling poll loop (T27)
    _nextPollAt = null;
    _pollFollowUpOhs.clear();
    _missedNotifyAt.clear();
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    // Copy: a connection check suspended in a DNS lookup may still insert
    // into _peers while we await here.
    for (final peer in List.of(_peers.values)) {
      await peer.disconnect();
    }
    _peers.clear();
    _dialsInFlight.clear();
    _resolvedEndpoints.clear();
    _registeredOHs.clear();
    _pendingResponses.clear();
    _putResponses.clear();
    _registerResponses.clear();
    _subscribeResponses.clear();
    _ratchetSessions.clear();
    _pendingRgbs.clear();
    _restoredChannels.clear();
    _fetchFailureCounts.clear();
    _failoversInProgress.clear();
    _pendingOhUpdates.clear();
    for (final timer in _pairingLookupTimers.values) {
      timer.cancel();
    }
    _pairingLookupTimers.clear();
    for (final timer in _yesterdayLookupTimers.values) {
      timer.cancel();
    }
    _yesterdayLookupTimers.clear();
    for (final hold in _prePublishHolds.values) {
      hold.release(); // release a held publish (it sees _disconnected)
    }
    await _incomingMessageController.close();
    // One channel to close — the old per-event controllers for ACKs, node
    // scores and group state were never closed at all.
    await _stateController.close();
    _updateStatus(ConnectionStatus.disconnected);
  }

  // --- OH Registration & Message state ---
  final List<OHRegistration> _registeredOHs = [];
  final _incomingMessageController =
      StreamController<DecryptedMessage>.broadcast();

  /// The single outbound state channel (see [StateUpdate]): every one-way
  /// state change — ratchet, garlic session, OH mailbox/fetch/own-set/
  /// peer-set, ACKs, node scores, group state — is published here and
  /// nowhere else.
  final _stateController = StreamController<StateUpdate>.broadcast();

  /// Publishes one state change. The only emit path — the closed-check
  /// lives here instead of at ~20 call sites.
  void _emitState(StateUpdate update) {
    if (_stateController.isClosed) return;
    _stateController.add(update);
  }

  // --- OH failover state (T21) ---

  /// Consecutive host-unreachable fetch failures per OH (hex id). Counted
  /// only while an ALTERNATIVE node is connected — total network loss (e.g.
  /// airplane mode) must never look like a dead host node.
  final Map<String, int> _fetchFailureCounts = {};

  /// After this many consecutive host-unreachable fetch cycles the channel
  /// fails over to a reachable node. With the idle cadence (30 s) that is
  /// ~1.5 min of a provably one-sided outage.
  static const int failoverFetchFailureThreshold = 3;

  /// Channels with a failover currently running (guards re-entry — the old
  /// handle keeps failing while the new one registers).
  final Set<String> _failoversInProgress = {};

  /// Pending in-band `oh_update` announcements per channel: the descriptor
  /// of the NEW own mailbox still to be told to the partner. Re-sent (same
  /// message id — the partner deduplicates) on the next poll cycles until
  /// [_PendingOhUpdate.remainingSends] runs out; a lost announce would leave
  /// the partner depositing into the dead mailbox forever.
  final Map<String, _PendingOhUpdate> _pendingOhUpdates = {};
  Timer? _pollingTimer;
  Timer? _renewalTimer;

  // Guards against overlapping timer ticks: fetch cycles share the
  // per-command slot in _pendingResponses, so they must not race.
  bool _pollInProgress = false;
  bool _renewalInProgress = false;

  /// T167: per-OH fetch progress of the running poll cycle (OH hex → phase).
  /// Filled when a cycle starts, cleared when it ends; tells [_handleNotify]
  /// whether the running cycle will still pick up the notified mail.
  final Map<String, _CycleFetchPhase> _cycleFetchPhase = {};

  /// T167 diagnostics: OH hex → when a Notify arrived that the running cycle
  /// had already fetched past; the next fetch of that OH logs the wait.
  final Map<String, DateTime> _missedNotifyAt = {};

  /// Mailbox poll cadence while no conversation is active. Kept at 30 s so
  /// idle traffic/metadata stays as before (T27).
  static const Duration idlePollInterval = Duration(seconds: 30);

  /// Faster poll cadence while a conversation is active (T27): the fixed
  /// 30 s tick dominated delivery latency (emulator duo E2E S2 p95 ~28 s —
  /// latency is simply the distance from a send to the receiver's next
  /// tick). 5 s bounds active-chat latency at ~6 s without touching the
  /// idle cadence. Node-side rate limiting only applies to OH registration
  /// (5/min per connection), not to fetches.
  static const Duration activePollInterval = Duration(seconds: 5);

  /// How long after the last chat activity (own send, non-empty fetch,
  /// fresh OH registration) the fast cadence is kept before falling back
  /// to [idlePollInterval].
  static const Duration pollActivityWindow = Duration(seconds: 60);

  /// Minimum pause between two poll cycles. Cycles are scheduled at a
  /// fixed rate (the last cycle's duration is subtracted from the next
  /// delay): a cycle involves multiple signed round-trips and decryptions,
  /// which on slow devices/debug builds can take several seconds —
  /// fixed-delay scheduling would silently stretch the effective cadence
  /// by that amount (T27: it pushed the active cadence from 5 s to ~12 s
  /// in the emulator harness).
  static const Duration minPollGap = Duration(seconds: 1);

  /// Whether the self-rescheduling poll loop is running (between
  /// [_startPolling] and [disconnect]).
  bool _pollingEnabled = false;

  /// Timestamp of the last chat activity; drives [_pollInterval].
  DateTime _lastChatActivity = DateTime.fromMillisecondsSinceEpoch(0);

  /// When the next regular (full) poll cycle is due — lets fresh activity
  /// pull an already-scheduled (slow) poll forward. Follow-up fetches (T167)
  /// run in between without moving it, so a stream of Notifies cannot starve
  /// the maintenance work of the full cycle.
  DateTime? _nextPollAt;

  /// T167: OHs (hex) notified after the running cycle had already fetched
  /// past them. Fetched by a follow-up right after the cycle, or first by
  /// the next full cycle, whichever runs first.
  final Set<String> _pollFollowUpOhs = {};

  /// T167: how many poll cycles (full or follow-up) may start back to back
  /// before the start rate is capped — see [_pollStartDelay].
  static const int pollBurst = 5;

  /// T167: once [pollBurst] is spent, one cycle start per this period.
  /// Shorter than [minPollGap] on purpose: [minPollGap] spaces the *full*
  /// cycles (many signed round trips, decryptions, maintenance) of the
  /// fixed-rate loop, while the starts this bucket mostly paces are
  /// follow-ups — one signed fetch per notified mailbox, driven by real mail.
  /// A conversation produces about three Notifies per message (the partner
  /// deposits into every one of our [ohRedundancy] mailboxes); at one start
  /// per [minPollGap] the lab saw follow-ups queue up for ~0.9 s.
  static const Duration pollStartRefill = Duration(milliseconds: 500);

  /// T167: an idle Notify waits this long before its follow-up starts, so
  /// the redundant copies' Notifies (lab: within 15–40 ms) share one start.
  static const Duration notifyCoalesceDelay = Duration(milliseconds: 25);

  /// T167: poll-start budget, a token bucket kept as time credit: each cycle
  /// start costs [pollStartRefill], the credit grows with wall time and is
  /// capped at [pollBurst] × [pollStartRefill]. Credit as of
  /// [_pollCreditAtMicros] on [_pollClock].
  int _pollCreditMicros = pollBurst * pollStartRefill.inMicroseconds;
  int? _pollCreditAtMicros;

  /// T167: monotonic clock for the poll-start budget and the coalesce window.
  /// `DateTime.now()` can step backwards (NTP, a user changing the time); a
  /// wall-clock credit would then go negative by the jump and hold back every
  /// cycle for that long.
  final Stopwatch _pollClock = Stopwatch()..start();

  /// T167: when [_pollFollowUpOhs] last went from empty to non-empty.
  int _pollFollowUpSinceMicros = 0;

  /// Whether the running cycle (if any) is a full one. A full cycle sets
  /// [_nextPollAt] itself when it ends; a follow-up keeps it, so a pull
  /// forward requested during a follow-up must still be applied.
  bool _fullCycleInProgress = false;

  /// Serializes fire-and-forget batch acks (T27): AckFetch responses share
  /// the single per-command completer slot, so acks must not overlap.
  Future<void> _ackFetchTail = Future.value();

  /// OHs are renewed when they expire within this window.
  static const Duration renewalThreshold = Duration(days: 1);

  /// Interval for the renewal check timer.
  static const Duration renewalCheckInterval = Duration(minutes: 5);

  /// Pending response completers keyed by command byte.
  final Map<int, Completer<List<int>>> _pendingResponses = {};

  /// Pending FlaschenpostPutResponse (158) completers. Deposits can overlap
  /// (UI send + retry pass), and the node answers them in order on the same
  /// connection, so these are matched FIFO instead of by command byte.
  final _ResponseQueue _putResponses = _ResponseQueue();

  /// Pending RegisterOhResponse (151) completers. Registration and the
  /// periodic renewal can overlap, so these are matched FIFO as well instead
  /// of clobbering a single per-command slot.
  final _ResponseQueue _registerResponses = _ResponseQueue();

  /// Pending SubscribeResponse (160) completers (Connection-Notify, T38).
  /// A SubscribeResponse carries no oh_id, so it is correlated purely by
  /// order. Handles can live on different host nodes whose connections answer
  /// independently, so ordering across connections is NOT guaranteed —
  /// subscribes are therefore serialized through [_subscribeTail] so at most
  /// one is ever in flight and this FIFO stays unambiguous.
  final _ResponseQueue _subscribeResponses = _ResponseQueue();

  /// Serializes subscribes (T38): chains every subscribe so only one
  /// SubscribeRequest is in flight at a time. Without this, two subscribes to
  /// different host nodes could have their (oh_id-less) responses arrive out
  /// of order and be mis-attributed by [_subscribeResponses].
  Future<void> _subscribeTail = Future.value();

  /// Enqueues a serialized subscribe of [oh] (see [_subscribeTail]).
  void _enqueueSubscribe(OHRegistration oh) {
    _subscribeTail = _subscribeTail.then((_) => _subscribe(oh)).catchError((
      Object e,
    ) {
      RpLog.info('RedPandaLightClient: subscribe error: $e');
    });
  }

  void _handleCommandResponse(int command, List<int> payload) {
    if (command == _cmdFlaschenpostPutRes) {
      _putResponses.handle(payload);
      return;
    }
    if (command == _cmdOutboundRegisterOhRes) {
      _registerResponses.handle(payload);
      return;
    }
    if (command == _cmdOutboundSubscribeRes) {
      // Connection-Notify (T38): SubscribeResponse, FIFO-matched.
      _subscribeResponses.handle(payload);
      return;
    }
    if (command == _cmdOutboundNotify) {
      // Connection-Notify (T38): unsolicited Notify — new mail for an OH.
      _handleNotify(payload);
      return;
    }
    final completer = _pendingResponses.remove(command);
    if (completer != null && !completer.isCompleted) {
      completer.complete(payload);
    }
  }

  /// Handles an unsolicited Notify (command 161, T38): the node signals that
  /// a subscribed mailbox received new mail. Pulls the mailbox poll forward
  /// instead of firing a standalone fetch — the poll cycle serializes the
  /// signed fetch round-trips (they share the per-command response slot 153),
  /// so an out-of-band fetch could race a running cycle. A Notify for an
  /// unknown OH is ignored (only logged). The regular poll loop stays as the
  /// fallback for missed Notifies.
  ///
  /// T167: a Notify that lands while a cycle runs is only covered by that
  /// cycle if the cycle has not fetched the OH yet. Otherwise — and whenever
  /// no cycle runs — the OH is queued for a fetch-only follow-up that runs at
  /// once or as soon as the running cycle ends (bounded by
  /// [_pollStartDelay]) instead of waiting out the interval. (Before T167 an
  /// idle Notify pulled the whole cycle forward, with no pause at all.)
  void _handleNotify(List<int> payload) {
    final Notify notify;
    try {
      notify = Notify.fromBuffer(payload);
    } catch (e) {
      RpLog.info('RedPandaLightClient: dropping malformed Notify: $e');
      return;
    }
    final known = _registeredOHs.any((oh) => _sameBytes(oh.ohId, notify.ohId));
    if (!known) {
      RpLog.info(
        'RedPandaLightClient: Notify for unknown OH '
        '${_hexEncode(notify.ohId)} — ignoring',
      );
      return;
    }
    RpLog.debug(
      'RedPandaLightClient: Notify for OH ${_hexEncode(notify.ohId)} — '
      'pulling mailbox poll forward',
    );
    if (RpDiag.enabled) _diagFetchStats.notifies++;
    // Keep the fast cadence going: a Notify means the conversation is live.
    _lastChatActivity = DateTime.now();
    // T167 diagnostics: where in the poll schedule did this Notify land?
    final ohHex = _hexEncode(notify.ohId);
    final timing = _notifyTimingLabel(ohHex);
    RpLog.debug('RedPandaLightClient: Notify timing $timing');
    if (timing != 'idle' && timing != 'before-fetch') {
      _missedNotifyAt.putIfAbsent(ohHex, DateTime.now);
    }
    if (!_pollingEnabled) return;
    // The running cycle still fetches this OH: nothing to do.
    if (timing == 'before-fetch') return;
    // Already fetched (or in flight, or not in the cycle's snapshot), or no
    // cycle running: fetch this OH in a follow-up — at once when idle, right
    // after the running cycle otherwise (that cycle's end arms the timer).
    // The full cycle keeps its own cadence either way, so a stream of
    // Notifies cannot drive its maintenance work (oh_update resends,
    // republish, redundancy sweep) faster than [activePollInterval].
    if (_pollFollowUpOhs.isEmpty) {
      _pollFollowUpSinceMicros = _pollClock.elapsedMicroseconds;
    }
    _pollFollowUpOhs.add(ohHex);
    // The follow-up does not move the full cycle, so pull a slow (idle
    // cadence) full cycle forward explicitly. The old idle path did this
    // implicitly: it ran a full cycle, which rescheduled itself at
    // [activePollInterval]. A conversation that just went live must get its
    // maintenance (oh_update resends, ACK expiry) on the fast cadence.
    _notePollActivity();
    if (!_pollInProgress) _armPollTimer();
  }

  /// T167: how far the running poll cycle has got with [ohHex] — `idle` (no
  /// cycle running), `before-fetch` (this cycle still fetches it),
  /// `during-fetch` (request out, response pending — the new item may or may
  /// not be in it), `after-fetch` (already fetched: this cycle will not see
  /// the new item), `not-in-cycle` (registered after the cycle took its
  /// snapshot).
  String _notifyTimingLabel(String ohHex) {
    if (!_pollInProgress) return 'idle';
    switch (_cycleFetchPhase[ohHex]) {
      case null:
        return 'not-in-cycle';
      case _CycleFetchPhase.pending:
        return 'before-fetch';
      case _CycleFetchPhase.inFlight:
        return 'during-fetch';
      case _CycleFetchPhase.done:
        return 'after-fetch';
    }
  }

  /// Subscribes [oh] for real-time Notify (Connection-Notify, T38). The
  /// SubscribeRequest proves ownership exactly like a fetch (Ed25519 over
  /// [CMD_BYTE(159) | oh_id | timestamp_ms(8 BE) | nonce], 0x02 prefix added
  /// by [OHKeypair.sign]) and must reach the handle's host node. Any failure
  /// (host not connected, timeout, non-OK) is tolerated — polling stays the
  /// fallback. A NOT_FOUND means the host forgot the handle, so the same
  /// recovery as a NOT_FOUND fetch is triggered.
  Future<void> _subscribe(OHRegistration oh) async {
    var result = 'error';
    try {
      await _subscribeOnce(oh, (r) => result = r);
    } finally {
      _diagOhEvent(DiagEvt.ohSubscribe, oh, result);
    }
  }

  Future<void> _subscribeOnce(
    OHRegistration oh,
    void Function(String result) diagResult,
  ) async {
    final activePeer = _peerForHandle(oh, 'subscribe()');
    if (activePeer == null) {
      // _peerForHandle already logged/kicked off the host connection.
      diagResult('host_not_connected');
      return;
    }

    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final now = DateTime.now();

    final signingBuffer = BytesBuilder();
    signingBuffer.addByte(_cmdOutboundSubscribeReq);
    signingBuffer.add(oh.ohId);
    signingBuffer.add(_int64Bytes(now.millisecondsSinceEpoch));
    signingBuffer.add(nonce);
    final signature = await oh.keypair.sign(
      Uint8List.fromList(signingBuffer.toBytes()),
    );

    final request = SubscribeRequest()
      ..ohId = oh.ohId
      ..timestampMs = _toInt64(now.millisecondsSinceEpoch)
      ..nonce = nonce
      ..signature = signature;

    // FIFO-matched: several OH subscribes can be in flight at once.
    final completer = _subscribeResponses.register();
    activePeer.sendCommand(
      _cmdOutboundSubscribeReq,
      Uint8List.fromList(request.writeToBuffer()),
    );

    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      _subscribeResponses.abandon(completer);
      RpLog.info(
        'RedPandaLightClient: subscribe() no response within 10s — '
        'polling remains the fallback',
      );
      diagResult('no_response');
      return;
    }

    final SubscribeResponse response;
    try {
      response = SubscribeResponse.fromBuffer(responseBytes);
    } catch (e) {
      RpLog.info(
        'RedPandaLightClient: dropping malformed SubscribeResponse: $e',
      );
      diagResult('malformed');
      return;
    }
    diagResult(
      response.status == Status.OK ? 'ok' : 'status ${response.status}',
    );
    if (response.status == Status.OK) {
      RpLog.debug(
        'RedPandaLightClient: subscribed OH ${_hexEncode(oh.ohId)} for Notify',
      );
      return;
    }
    if (response.status == Status.NOT_FOUND) {
      RpLog.info(
        'RedPandaLightClient: subscribe() NOT_FOUND for OH '
        '${_hexEncode(oh.ohId)} — re-registering lost handle',
      );
      unawaited(reregisterLostHandle(oh));
      return;
    }
    RpLog.info(
      'RedPandaLightClient: subscribe() non-OK status: ${response.status}',
    );
  }

  /// (Re-)subscribes every registered OH for real-time Notify (T38). Used on
  /// the connect edge: a subscription lives only for its connection, so a
  /// reconnect must renew it.
  void _subscribeAllHandles() {
    for (final oh in List.of(_registeredOHs)) {
      _enqueueSubscribe(oh);
    }
  }

  /// Outstanding loopback self-tests (T20), keyed by message id (hex). The
  /// fetch pipeline completes and removes the entry when the test message
  /// comes back. Entries of timed-out tests stay registered so a late
  /// arrival is still swallowed instead of surfacing as a chat message;
  /// [_maxPendingLoopbacks] bounds the map (tests are manual one-shots, so
  /// evicting the oldest stale entry is safe).
  final Map<String, Completer<void>> _pendingLoopbacks = {};

  /// Upper bound for [_pendingLoopbacks] (insertion-ordered eviction).
  static const int _maxPendingLoopbacks = 16;

  /// Payload of every T20 loopback self-test message. Also used to swallow
  /// re-delivered test messages whose pending entry no longer exists (app
  /// restart, eviction, or a T40 cursor heal replaying old deposits) — they
  /// are diagnostics and must never surface as chat messages.
  static const String _loopbackContent = 'loopback self-test';

  /// Channel encryption keys indexed by channel ID.
  /// Populated externally or via addChannelKeys().
  final Map<String, List<int>> _channelEncryptionKeys = {};

  /// The PRIMARY counterpart OH id per channel (== [_channelCounterpartOhSet].first). Kept
  /// as a plain map so the single-target senders (garlic, RGB reply,
  /// direct-deposit fallback, ack routing) stay unchanged — they always aim
  /// at the primary. The multi-deposit fan-out (T42) uses the full set below.
  final Map<String, List<int>> _channelCounterpartOhIds = {};

  /// host:port of the node hosting the counterpart's PRIMARY OH (from the
  /// OHDescriptor), excluded from garlic hop candidates (MS04: no hop ==
  /// destination node).
  final Map<String, String> _channelCounterpartOhEndpoints = {};

  /// The live encryption key of [channelId] (read-only view, for tests and
  /// diagnostics).
  List<int>? channelEncryptionKeyOf(String channelId) {
    final key = _channelEncryptionKeys[channelId];
    return key == null ? null : List.unmodifiable(key);
  }

  /// The display name currently advertised for [channelId] in its rendezvous
  /// record (read-only view, for tests and diagnostics).
  String? rendezvousOwnNameOf(String channelId) =>
      _rendezvous.ownNameOf(channelId);

  /// TD117: restores a channel's rendezvous merge state after a worker
  /// respawn (driven by `CmdRestoreRendezvousState`, whose payload came from
  /// [rendezvousMergeStateOf] before the old worker died). Newest-wins, so it
  /// can only add knowledge.
  void restoreRendezvousMergeState(String channelId, String mergeStateJson) =>
      _rendezvous.restoreMergeState(channelId, mergeStateJson);

  /// The serialized rendezvous merge state of [channelId] (for the worker
  /// -restore projection and for tests), or null when there is nothing known.
  String? rendezvousMergeStateOf(String channelId) =>
      _rendezvous.exportMergeState(channelId);

  /// Refreshes the rendezvous own-OH projection of [channelId] from the live
  /// handle set and reports whether it changed.
  ///
  /// The own-OH list inside [RendezvousManager] is a PROJECTION of
  /// [registeredOutboundHandles], and only the two publish triggers
  /// (a fresh registration, an own-OH set change) ever fed it. A respawned
  /// worker — and an app restart, which is the same thing one level up — gets
  /// its mailboxes back through [restoreOutboundHandle], which is
  /// deliberately not a publish trigger, so the projection stayed EMPTY:
  /// `buildSignedStore` then returns null and the republish sweep silently
  /// published nothing until the next mailbox change (Copilot HIGH on #123).
  /// That would have left the restored merge state (TD117) unpublishable —
  /// the record would keep expiring with the counterpart in it.
  ///
  /// Called by the republish sweep, so the projection is re-derived wherever
  /// the record is about to be refreshed instead of depending on who set it.
  bool refreshRendezvousOwnOhs(String channelId) =>
      _rendezvous.setOwnOhs(channelId, _ownDescriptorsFor(channelId));

  /// The partner's currently known mailbox ids for [channelId], primary
  /// first (read-only view, for tests and diagnostics — mirrors
  /// [registeredOutboundHandles] for the own side).
  ///
  /// T143 (TD153): named with the `Oh` morpheme used by the
  /// `counterpartOh*` parameters of [addChannelKeys] and the
  /// `_channelCounterpartOh*` state; these two accessors were the last
  /// `counterpartMailbox*` spellings for the same concept.
  List<List<int>> counterpartOhIds(String channelId) => [
    for (final oh
        in _channelCounterpartOhSet[channelId] ?? const <_CounterpartOh>[])
      List.unmodifiable(oh.ohId),
  ];

  /// host:port of the node hosting the partner's PRIMARY mailbox, if known
  /// (read-only view, for tests and diagnostics).
  String? counterpartOhEndpoint(String channelId) =>
      _channelCounterpartOhEndpoints[channelId];

  /// T42: the FULL set of the partner's known OH mailboxes per channel.
  /// A send deposits into EVERY entry in parallel (the receiver deduplicates
  /// by message_id), so one dead OH-host node no longer stalls delivery — the
  /// copy on the surviving node arrives without waiting for a failover. The
  /// set is seeded from the QR/primary OH and grown/replaced by the in-band
  /// `oh_update` announce (a JSON array of descriptors, T42). The first entry
  /// mirrors [_channelCounterpartOhIds]/[_channelCounterpartOhEndpoints].
  final Map<String, List<_CounterpartOh>> _channelCounterpartOhSet = {};

  /// Sets the primary counterpart OH (id + endpoint) for [channelId] and seeds the
  /// counterpart OH set with it when no richer set is known yet.
  ///
  /// Only ever called while the channel has NO live counterpart mailbox at all (see
  /// [addChannelKeys]): a set grown via `oh_update` or the T44 rendezvous
  /// lookup is always at least as fresh as anything the app layer persisted,
  /// so a re-registration must not re-point the primary at it.
  void _seedPrimaryCounterpartOh(
    String channelId,
    List<int> ohId,
    String? endpoint,
  ) {
    _channelCounterpartOhIds[channelId] = ohId;
    if (endpoint != null) {
      _channelCounterpartOhEndpoints[channelId] = endpoint;
    }
    final existing = _channelCounterpartOhSet[channelId];
    if (existing == null || existing.isEmpty) {
      _channelCounterpartOhSet[channelId] = [
        _CounterpartOh(ohId: ohId, endpoint: endpoint),
      ];
    }
  }

  /// Replaces the counterpart OH set for [channelId] with [descriptors] (deduplicated
  /// by OH id, order preserved) and re-points the primary at the first entry.
  /// Returns true when the set actually changed.
  bool _replaceCounterpartOhSet(
    String channelId,
    List<OHDescriptor> descriptors,
  ) {
    final deduped = <_CounterpartOh>[];
    for (final d in descriptors) {
      if (d.handleId.length != GarlicHop.nodeIdLength) continue;
      if (deduped.any((e) => _sameBytes(e.ohId, d.handleId))) continue;
      deduped.add(_CounterpartOh(ohId: d.handleId, endpoint: d.serverEndpoint));
    }
    if (deduped.isEmpty) return false;
    final previous = _channelCounterpartOhSet[channelId];
    if (previous != null &&
        previous.length == deduped.length &&
        List.generate(
          previous.length,
          (i) =>
              _sameBytes(previous[i].ohId, deduped[i].ohId) &&
              previous[i].endpoint == deduped[i].endpoint,
        ).every((x) => x)) {
      return false; // identical — a duplicate announce
    }
    _channelCounterpartOhSet[channelId] = deduped;
    _channelCounterpartOhIds[channelId] = deduped.first.ohId;
    final primaryEndpoint = deduped.first.endpoint;
    if (primaryEndpoint != null) {
      _channelCounterpartOhEndpoints[channelId] = primaryEndpoint;
    }
    return true;
  }

  /// The distinct own OH descriptors of [channelId] (T42) — the payload of an
  /// `oh_update` announce. Only OHs with a known host endpoint are included:
  /// a descriptor without an endpoint carries no place for the partner to
  /// deposit to.
  List<OHDescriptor> _ownDescriptorsFor(String channelId) {
    final out = <OHDescriptor>[];
    for (final oh in _registeredOHs) {
      if (oh.channelId != channelId) continue;
      final endpoint = oh.serverEndpoint;
      if (endpoint == null) continue;
      if (out.any((d) => _sameBytes(d.handleId, oh.ohId))) continue;
      out.add(
        OHDescriptor(
          serverEndpoint: endpoint,
          handleId: oh.ohId,
          authPublicKey: oh.keypair.publicKeyBytes,
        ),
      );
    }
    return out;
  }

  /// Channel ratchet sessions (MS03b), keyed by channel id. Stored as
  /// futures because session initialization is async while [addChannelKeys]
  /// is sync; consumers await the future right before encrypt/decrypt.
  final Map<String, Future<RatchetSession>> _ratchetSessions = {};

  /// Restores a channel's persisted state into this worker so
  /// sendMessage/fetchMessages can use it.
  ///
  /// T111 — the worker owns channel state; this is a RESTORE, not an
  /// assignment. The first call for a [channelId] adopts the snapshot; every
  /// later call may only fill gaps. Concretely, for a channel already known
  /// ([knowsChannel]):
  ///
  /// - the encryption key is kept (it is derived from the channel secret, so
  ///   a re-registration carries the same bytes — a differing one is a bug
  ///   and is logged, not applied),
  /// - the rendezvous display name is only updated when one is supplied
  ///   ([ownDisplayName] non-null); a caller that does not know it must not
  ///   blank the name already being published,
  /// - the partner's mailbox set is kept whenever ANY is live (it is grown by
  ///   `oh_update` and the T44 rendezvous lookup),
  /// - the ratchet session and the garlic session are kept — a live session
  ///   is always at least as advanced as a persisted snapshot.
  ///
  /// So a caller that knows only part of a channel's state can no longer cost
  /// the worker the rest of it (the H8 bug class).
  @override
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? channelSecret,
    String? ownDisplayName,
    List<int>? counterpartOhId,
    String? counterpartOhEndpoint,
    List<OHDescriptor>? counterpartOhSet,
    required bool isChannelCreator,
    String? ratchetState,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
  }) {
    // `add` returns false for a channel we already hold live state for.
    final isFirstRegistration = _restoredChannels.add(channelId);
    final liveKey = _channelEncryptionKeys[channelId];
    if (liveKey == null) {
      _channelEncryptionKeys[channelId] = encryptionKey;
    } else if (!_sameBytes(liveKey, encryptionKey)) {
      RpLog.info(
        'RedPandaLightClient: ignoring a re-registration of channel '
        '$channelId with a DIFFERENT encryption key — the live key wins '
        '(the channel id is derived from the secret, so this is a wiring bug)',
      );
    }
    // T44: register the rendezvous state (QR v4). Without the channel secret
    // (legacy caller) the rendezvous DHT layer stays dormant for this channel.
    if (channelSecret != null && channelSecret.length == 32) {
      _rendezvous.register(
        channelId,
        channelSecret: channelSecret,
        isCreator: isChannelCreator,
        ownName: ownDisplayName,
      );
    } else if (channelSecret != null) {
      // A non-null but wrong-length secret silently disables rendezvous for
      // this channel — surface it so a wiring bug (e.g. mis-sized bytes) is
      // visible instead of a channel that quietly can't heal over the DHT.
      RpLog.info(
        'RedPandaLightClient: ignoring channelSecret for $channelId — '
        'expected 32 bytes, got ${channelSecret.length}; rendezvous disabled',
      );
    }
    // T42/T111: restore the persisted counterpart mailbox set (multi-OH first, then
    // the primary) ONLY while no live mailbox is known for the channel. Every
    // other source of a counterpart mailbox — the in-band `oh_update` announce and
    // the T44 rendezvous lookup — is newer by construction, so a
    // re-registration from persisted data must not undo it. The primary used
    // to be re-pointed unconditionally here, which let a re-register carrying
    // a stale row silently redirect every single-target send (garlic, RGB
    // reply, channel-ACK) at a dead mailbox.
    final liveCounterpartOhSet = _channelCounterpartOhSet[channelId];
    if (liveCounterpartOhSet == null || liveCounterpartOhSet.isEmpty) {
      if (counterpartOhSet != null && counterpartOhSet.isNotEmpty) {
        _replaceCounterpartOhSet(channelId, counterpartOhSet);
      }
      if (counterpartOhId != null) {
        _seedPrimaryCounterpartOh(
          channelId,
          counterpartOhId,
          counterpartOhEndpoint,
        );
      }
    }
    // MS05: the garlic session snapshot is adopted on the first registration
    // only — outstanding tags are consumed and the pending RGB is replaced by
    // live traffic, so re-applying a snapshot could resurrect a burnt tag.
    if (isFirstRegistration) {
      _restoreGarlicSession(channelId, sessionTags, pendingRgbHex);
    }
    // A live session is always at least as advanced as any persisted state,
    // so re-registrations never replace it.
    _ratchetSessions.putIfAbsent(channelId, () async {
      if (ratchetState != null) {
        try {
          return RatchetSession.fromJson(ratchetState);
        } on FormatException catch (e) {
          RpLog.info(
            'RedPandaLightClient: discarding unreadable ratchet state for '
            'channel $channelId ($e), starting a fresh session',
          );
        }
      }
      return RatchetSession.create(
        channelKey: encryptionKey,
        isChannelCreator: isChannelCreator,
      );
    });
  }

  /// Restores persisted reverse-garlic session state (MS05). Called only on
  /// the first registration of a channel (the caller owns that guard) —
  /// live state is always at least as advanced as anything persisted.
  void _restoreGarlicSession(
    String channelId,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
  ) {
    sessionTags?.forEach((tagHex, createdAtMs) {
      _sessionTagStore.store(tagHex, channelId, createdAtMs: createdAtMs);
    });
    if (pendingRgbHex != null) {
      try {
        _pendingRgbs[channelId] = ReverseGarlicBlock.deserialize(
          _hexDecode(pendingRgbHex),
        );
      } on FormatException catch (e) {
        RpLog.info(
          'RedPandaLightClient: discarding unreadable persisted RGB for '
          'channel $channelId ($e)',
        );
      }
    }
  }

  /// Publishes the garlic session state of [channelId] (outstanding tags +
  /// pending RGB) so the app layer can persist it (on-device only).
  void _emitGarlicSession(String channelId) {
    final rgb = _pendingRgbs[channelId];
    _emitState(
      GarlicSessionUpdate(
        channelId: channelId,
        sessionTags: _sessionTagStore.tagsForChannel(channelId),
        pendingRgbHex: rgb != null ? _hexEncode(rgb.serialize()) : null,
      ),
    );
  }

  /// The single state channel (see [StateUpdate]). Consumers take the typed
  /// projection they need: `stateUpdates.of<RoutingAckUpdate>()`.
  @override
  Stream<StateUpdate> get stateUpdates => _stateController.stream;

  /// Restores persisted node scores (startup). Live in-memory scores win.
  @override
  void restoreNodeScores(List<NodeScore> scores) {
    _nodeScorer.restore(scores);
  }

  void _emitNodeScores() {
    _emitState(NodeScoreUpdate(_nodeScorer.snapshot()));
  }

  /// Publishes the advanced ratchet state of [channelId] so the app layer
  /// can persist it (on-device only).
  void _emitRatchetState(String channelId, RatchetSession session) {
    _emitState(
      RatchetStateUpdate(channelId: channelId, stateJson: session.toJson()),
    );
  }

  @override
  Stream<DecryptedMessage> get incomingMessages =>
      _incomingMessageController.stream;

  /// Timestamp (ms since epoch) of the last successful mailbox fetch per
  /// channel id. Fed by [_emitFetchStatus]; read by [runChannelDoctor] to
  /// judge how fresh the receiving pipeline is. Purely diagnostic.
  final Map<String, int> _lastFetchOkAtMs = {};

  /// Reports the outcome of one fetch attempt (success AND failure — unlike
  /// [OhMailboxUpdate], which only fires on state changes).
  void _emitFetchStatus(OHRegistration oh, bool success, [String? detail]) {
    if (RpDiag.enabled) {
      _diagFetchStats.polls++;
      if (success) {
        _diagFetchStats.ok++;
      } else {
        _diagFetchStats.failures++;
      }
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final channelId = oh.channelId;
    if (success && channelId != null) {
      _lastFetchOkAtMs[channelId] = nowMs;
    }
    _emitState(
      OhFetchStatus(
        ohId: oh.ohId,
        channelId: oh.channelId,
        success: success,
        atMs: nowMs,
        detail: detail,
      ),
    );
  }

  /// Currently registered/restored OHs (read-only view, for tests).
  List<OHRegistration> get registeredOutboundHandles =>
      List.unmodifiable(_registeredOHs);

  @override
  Future<void> restoreOutboundHandle(OHRegistration registration) async {
    final alreadyKnown = _registeredOHs.any(
      (oh) => _sameBytes(oh.ohId, registration.ohId),
    );
    if (alreadyKnown) return;

    _registeredOHs.add(registration);
    _startPolling();
  }

  /// Byte-wise equality (OH ids, channel keys).
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<String> sendMessage(
    String channelId,
    String content, {
    String? messageId,
  }) async {
    // Review G4: a send that stops early must not report the previous one.
    lastOwnRgbShape = OwnReplyPathShape.none;
    // Resolve a stable 16-byte message id. Callers (e.g. the retry queue) pass
    // the same id on every attempt so re-sends deduplicate at the receiver via
    // the ChannelMessage.message_id carried inside the encrypted payload. A
    // fresh random IV per attempt is fine — the inner id is the dedup key.
    final Uint8List messageIdBytes;
    if (messageId != null && messageId.isNotEmpty) {
      messageIdBytes = Uint8List.fromList(_hexDecode(messageId));
    } else {
      final random = Random.secure();
      messageIdBytes = Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)),
      );
    }
    final messageIdHex = _hexEncode(messageIdBytes);

    final encKey = _channelEncryptionKeys[channelId];
    if (encKey == null) {
      // Channel keys not yet registered in the network layer. The message
      // stays pending in the app database; the retry queue re-sends it once
      // the keys have been registered.
      throw StateError(
        'sendMessage: channel $channelId has no encryption keys registered',
      );
    }

    // T27: an own send starts/extends the active-conversation window — a
    // reply is likely, so the mailbox poll switches to the fast cadence.
    _notePollActivity();

    // MS05: attach a fresh Reverse Garlic Block when this channel has an own
    // OH mailbox to reply to — one RGB per message (master spec MS05, OQ 2),
    // so the partner always holds a fresh return path.
    // Build the inner ChannelMessage (message_id + timestamp + content +
    // optional reply path) and encrypt it into a v4 payload with the channel
    // ratchet (MS03b): the AES-GCM key is the per-message key MK_n, not the
    // static K_enc.
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    ChannelMessage messageWith(ReverseGarlicBlock? reply) => ChannelMessage(
      messageId: messageIdBytes,
      timestampMs: timestampMs,
      content: content,
      replyPath: reply?.serialize(),
    );
    final rgb = _fitOwnRgb(channelId, _buildOwnRgb(channelId), messageWith);
    if (rgb != null) _commitOwnRgb(channelId, rgb);
    lastOwnRgbShape = rgb == null
        ? OwnReplyPathShape.none
        : _endsAtOwnHost(channelId, rgb.hops)
        ? OwnReplyPathShape.hostClosed
        : OwnReplyPathShape.open;
    final channelMessage = messageWith(rgb);
    final session = await _ratchetSessions[channelId]!;
    final payload = await session.encrypt(channelMessage, channelId);
    // Persist immediately: the sending chain has advanced even if the
    // deposit below fails — a retry re-encrypts with the next message key.
    _emitRatchetState(channelId, session);

    // Send to a connected peer (best available). The node routes garlic
    // packets toward their first hop / deposits direct puts locally or
    // forwards them (MS02b), so any connected Full Node works.
    final activePeer = _sendablePeers.firstOrNull;

    if (activePeer == null) {
      // No connected Full Node — the retry queue will try again later.
      throw StateError('sendMessage: no active peer available');
    }

    lastSendViaRgb = false;
    lastSendAckRequested = false;

    // MS05: reply over the partner's reverse garlic block when a valid one
    // is pending — the reply reaches their OH mailbox without us needing to
    // know (or pick a path to) it.
    final pendingRgb = _pendingRgbs[channelId];
    if (pendingRgb != null) {
      if (pendingRgb.isExpired()) {
        // OQ 3: expired RGB → discard it and fall back to the forward path.
        _pendingRgbs.remove(channelId);
        _emitGarlicSession(channelId);
        RpLog.info(
          'RedPandaLightClient: sendMessage() pending RGB for channel '
          '$channelId expired, falling back to the forward path',
        );
      } else if (_routeFor(channelId, payload.length).kind ==
          _RouteKind.viaRgb) {
        await _sendViaRgb(
          activePeer,
          pendingRgb,
          payload,
          channelId,
          messageIdHex: messageIdHex,
        );
        _pendingRgbs.remove(channelId); // single-use
        _emitGarlicSession(channelId);
        return messageIdHex;
      } else {
        RpLog.info(
          'RedPandaLightClient: sendMessage() payload of ${payload.length} '
          'bytes exceeds the tagged reply budget (or only the forward path '
          'keeps its R-ACK), using the forward path',
        );
      }
    }

    // T45: garlic-only deposit into the counterpart's mailbox set. A deposit is NEVER
    // sent as a direct FlaschenpostPut anymore — the connected node must not be
    // able to observe every deposit pattern (MS04 privacy; binding user
    // decision 2026-07-20: Garlic ALWAYS, one hop-disjoint route per counterpart OH).
    // Each known counterpart OH gets its own garlic route with forward hops kept
    // disjoint across routes (best-effort anti-correlation); a degenerate net
    // with no relay candidates routes the packet through the connected node
    // itself (uniform garlic — still command 142, never a direct 141 deposit).
    final targets =
        _channelCounterpartOhSet[channelId]
            ?.where((t) => t.ohId.length == GarlicHop.nodeIdLength)
            .toList(growable: false) ??
        const <_CounterpartOh>[];
    if (targets.isEmpty) {
      // No known counterpart OH — no route can be built. Keep the message pending
      // (the app retries it) and kick off a rendezvous DHT recovery so a later
      // retry finds the counterpart's current mailboxes (T44).
      RpLog.info(
        'RedPandaLightClient: sendMessage() channel $channelId has no known '
        'counterpart OH — message stays pending for retry',
      );
      unawaited(_recoverViaRendezvous(channelId));
      throw UnknownCounterpartException(channelId);
    }
    await _depositViaGarlicToAll(
      activePeer,
      targets,
      payload,
      channelId,
      messageIdHex: messageIdHex,
    );
    return messageIdHex;
  }

  /// How long [runLoopbackTest] waits for the test message to come back.
  /// Matches the MS-MH hard delivery budget (60 s).
  static const Duration loopbackTimeout = Duration(seconds: 60);

  @override
  Future<LoopbackResult> runLoopbackTest(
    String channelId, {
    Duration timeout = loopbackTimeout,
  }) async {
    final result = await _runLoopbackTest(channelId, timeout: timeout);
    RpDiag.emit(DiagEvt.loopbackResult, {
      DiagKey.channel: channelId,
      DiagKey.ok: result.success,
      DiagKey.rttMs: result.roundtripMs,
      DiagKey.hopCount: result.hopCount,
      DiagKey.error: result.error,
    });
    return result;
  }

  Future<LoopbackResult> _runLoopbackTest(
    String channelId, {
    required Duration timeout,
  }) async {
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .firstOrNull;
    if (ownOh == null) {
      return const LoopbackResult.failed('no own mailbox registered');
    }
    final encKey = _channelEncryptionKeys[channelId];
    if (encKey == null) {
      return const LoopbackResult.failed('channel keys not registered');
    }
    final activePeer = _sendablePeers.firstOrNull;
    if (activePeer == null) {
      return const LoopbackResult.failed('not connected to any node');
    }

    // The test message is encrypted with the static channel key (v3), NOT
    // the ratchet: ratchet chains are asymmetric between the two devices, so
    // a self-addressed v4 payload could never be decrypted on fetch — and
    // the ratchet must not advance for a diagnostic message anyway. The
    // fetch pipeline dispatches on the version byte and decrypts v3 with
    // the same static key.
    final random = Random.secure();
    final messageIdBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final messageIdHex = _hexEncode(messageIdBytes);
    final payload = await MessageCryptoV3.encrypt(
      ChannelMessage(
        messageId: messageIdBytes,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        content: _loopbackContent,
      ),
      encKey,
      channelId,
    );

    // Bound the map: evict the oldest (stale) entries first — Dart maps
    // iterate in insertion order.
    while (_pendingLoopbacks.length >= _maxPendingLoopbacks) {
      _pendingLoopbacks.remove(_pendingLoopbacks.keys.first);
    }
    final completer = Completer<void>();
    _pendingLoopbacks[messageIdHex] = completer;
    final started = DateTime.now();

    // Deposit into the OWN mailbox over the same garlic path a regular send
    // uses (T45: NEVER a direct FlaschenpostPut — with no relay candidate the
    // route goes through the connected node itself). T41: retry over FRESH,
    // disjoint hops when the round trip does not complete, so a single dead
    // relay hop cannot make a healthy channel look broken (realnet
    // 2026-07-18). Over a genuine relay path the deposit requests an R-ACK, so
    // the [NodeScorer] learns which hops delivered and steers later routes
    // around a bad one (option b); a self-hop has no return path.
    const maxAttempts = 2;
    final attemptTimeout = Duration(
      milliseconds: (timeout.inMilliseconds / maxAttempts).round(),
    );
    final triedNodeIds = <String>{};
    var lastHopCount = 0;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final route = _garlicRoute(
        activePeer,
        ohEndpoint: ownOh.serverEndpoint,
        excludeNodeIds: triedNodeIds,
      );
      if (route == null) {
        _pendingLoopbacks.remove(messageIdHex);
        return const LoopbackResult.failed('no route to own mailbox');
      }
      lastHopCount = route.selfHop ? 0 : route.hops.length;
      for (final hop in route.hops) {
        triedNodeIds.add(_hexEncode(hop.nodeId));
      }
      try {
        await _sendViaGarlic(
          activePeer,
          route.hops,
          ownOh.ohId,
          payload,
          channelId,
          messageIdHex: route.selfHop ? null : messageIdHex,
          diagKind: 'loopback',
          diagMessageIdHex: messageIdHex,
          diagTargetHost: ownOh.serverEndpoint,
          diagRouteIndex: attempt,
        );
      } catch (e) {
        _pendingLoopbacks.remove(messageIdHex);
        return LoopbackResult.failed(
          'deposit failed: $e',
          hopCount: lastHopCount,
        );
      }

      // Pull the next mailbox poll forward so the result does not wait for
      // the idle cadence; the active window keeps polling fast afterwards.
      _notePollActivity();
      _schedulePoll(const Duration(seconds: 1));

      try {
        await completer.future.timeout(attemptTimeout);
        return LoopbackResult.ok(
          roundtripMs: DateTime.now().difference(started).inMilliseconds,
          hopCount: lastHopCount,
        );
      } on TimeoutException {
        // No round trip yet — retry over fresh, disjoint hops (or give up
        // after the last attempt). The entry stays registered so a late
        // arrival is still swallowed.
      }
    }
    return LoopbackResult.failed(
      'not received within ${timeout.inSeconds}s',
      hopCount: lastHopCount,
    );
  }

  /// A successful mailbox fetch newer than this counts as green in the
  /// doctor's "last fetch" stage (roughly three idle poll cycles).
  static const Duration _doctorFetchFreshWindow = Duration(seconds: 90);

  /// A last successful fetch older than [_doctorFetchFreshWindow] but newer
  /// than this counts as amber; older than this is red.
  static const Duration _doctorFetchStaleWindow = Duration(minutes: 5);

  @override
  Future<ChannelDoctorReport> runChannelDoctor(
    String channelId, {
    Duration timeout = loopbackTimeout,
  }) async {
    final stages = <DoctorStage>[];
    final sw = Stopwatch()..start();

    // Stage 1+2 PER own OH mailbox (T42 multi-OH): a "Host node reachable"
    // and an "Own mailbox announced" traffic light for EACH own mailbox, so a
    // dead host on one mailbox shows red while the redundant mailbox stays
    // green. A " N/M" suffix disambiguates when more than one mailbox exists;
    // with a single mailbox the names are unchanged.
    final ownOhs = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .toList(growable: false);
    final verifiedCount = _sendablePeers.length;
    if (ownOhs.isEmpty) {
      stages.add(
        verifiedCount > 0
            ? _stage(
                'Host node reachable',
                DoctorStatus.warn,
                sw,
                'No own mailbox yet, so no dedicated host node. '
                    'Connected to $verifiedCount node(s).',
              )
            : _stage(
                'Host node reachable',
                DoctorStatus.fail,
                sw,
                'Not connected to any node.',
              ),
      );
      sw
        ..reset()
        ..start();
      stages.add(
        _stage(
          'Own mailbox announced',
          DoctorStatus.fail,
          sw,
          'No own mailbox registered for this channel.',
        ),
      );
    } else {
      for (var i = 0; i < ownOhs.length; i++) {
        final ownOh = ownOhs[i];
        final suffix = ownOhs.length > 1 ? ' ${i + 1}/${ownOhs.length}' : '';
        final endpoint = ownOh.serverEndpoint;

        // Host-reachable stage.
        sw
          ..reset()
          ..start();
        if (endpoint != null) {
          final hostPeer = _livePeerFor(endpoint);
          if (hostPeer != null && hostPeer.canSendCommands) {
            stages.add(
              _stage(
                'Host node reachable$suffix',
                DoctorStatus.ok,
                sw,
                'Connected to $endpoint (handshake verified).',
              ),
            );
          } else if (hostPeer != null && !hostPeer.isDisconnected) {
            stages.add(
              _stage(
                'Host node reachable$suffix',
                DoctorStatus.warn,
                sw,
                'Connecting to host node $endpoint…',
              ),
            );
          } else {
            stages.add(
              _stage(
                'Host node reachable$suffix',
                DoctorStatus.fail,
                sw,
                'Host node $endpoint is not connected.',
              ),
            );
          }
        } else {
          stages.add(
            verifiedCount > 0
                ? _stage(
                    'Host node reachable$suffix',
                    DoctorStatus.warn,
                    sw,
                    'Own mailbox has no recorded host node. '
                        'Connected to $verifiedCount node(s).',
                  )
                : _stage(
                    'Host node reachable$suffix',
                    DoctorStatus.fail,
                    sw,
                    'Not connected to any node.',
                  ),
          );
        }

        // Announce/validity stage.
        sw
          ..reset()
          ..start();
        final remaining = Duration(
          milliseconds:
              ownOh.expiresAtMs - DateTime.now().millisecondsSinceEpoch,
        );
        if (remaining.isNegative || remaining == Duration.zero) {
          stages.add(
            _stage(
              'Own mailbox announced$suffix',
              DoctorStatus.fail,
              sw,
              'Registration expired ${_fmtDuration(-remaining)} ago.',
            ),
          );
        } else if (remaining <= renewalThreshold) {
          stages.add(
            _stage(
              'Own mailbox announced$suffix',
              DoctorStatus.warn,
              sw,
              'Registration renews soon (valid for '
                  '${_fmtDuration(remaining)}).',
            ),
          );
        } else {
          stages.add(
            _stage(
              'Own mailbox announced$suffix',
              DoctorStatus.ok,
              sw,
              'Announced on ${endpoint ?? 'a node'}, valid for '
                  '${_fmtDuration(remaining)}.',
            ),
          );
        }
      }
    }

    // Stage 3: counterpart mailboxes known (required for sending). Reports
    // how many of the partner's mailboxes we can deposit into (T42 fan-out).
    sw
      ..reset()
      ..start();
    final counterpartSet =
        _channelCounterpartOhSet[channelId] ?? const <_CounterpartOh>[];
    if (counterpartSet.isEmpty) {
      stages.add(
        _stage(
          "Recipient's mailbox known",
          DoctorStatus.warn,
          sw,
          "Recipient's mailbox unknown — scan their QR code to enable "
              'sending. Receiving still works.',
        ),
      );
    } else {
      final endpoints = counterpartSet
          .map((p) => p.endpoint)
          .whereType<String>()
          .toList(growable: false);
      stages.add(
        _stage(
          "Recipient's mailbox known",
          DoctorStatus.ok,
          sw,
          counterpartSet.length == 1
              ? (endpoints.isNotEmpty
                    ? "Recipient's mailbox on ${endpoints.first}."
                    : "Recipient's mailbox id known.")
              : '${counterpartSet.length} recipient mailboxes known'
                    '${endpoints.isNotEmpty ? ' (${endpoints.join(', ')})' : ''}.',
        ),
      );
    }

    // Stage 4: Last successful fetch age.
    sw
      ..reset()
      ..start();
    final lastOk = _lastFetchOkAtMs[channelId];
    if (lastOk == null) {
      stages.add(
        _stage(
          'Last fetch success',
          DoctorStatus.warn,
          sw,
          'No successful mailbox check since app start.',
        ),
      );
    } else {
      final age = Duration(
        milliseconds: DateTime.now().millisecondsSinceEpoch - lastOk,
      );
      final status = age <= _doctorFetchFreshWindow
          ? DoctorStatus.ok
          : age <= _doctorFetchStaleWindow
          ? DoctorStatus.warn
          : DoctorStatus.fail;
      stages.add(
        _stage(
          'Last fetch success',
          status,
          sw,
          'Last successful mailbox check ${_fmtDuration(age)} ago.',
        ),
      );
    }

    // Stage 5: Loopback self-test (reuses the T20 path end to end).
    sw
      ..reset()
      ..start();
    final loopback = await runLoopbackTest(channelId, timeout: timeout);
    final loopbackMs = loopback.roundtripMs ?? sw.elapsedMilliseconds;
    stages.add(
      loopback.success
          ? DoctorStage(
              name: 'Loopback self-test',
              status: DoctorStatus.ok,
              durationMs: loopbackMs,
              detail:
                  'Round trip in ${(loopbackMs / 1000).toStringAsFixed(1)} s '
                  'via ${loopback.hopCount} relay hop(s).',
            )
          : DoctorStage(
              name: 'Loopback self-test',
              status: DoctorStatus.fail,
              durationMs: loopbackMs,
              detail: 'Failed: ${loopback.error ?? 'unknown error'}',
            ),
    );

    // Stage 6 (T44): Rendezvous — can the channel heal over the DHT if every
    // host node dies? Green once we know the channel secret AND have an own OH
    // set to publish (and therefore a record peers can resolve).
    sw
      ..reset()
      ..start();
    if (!_rendezvous.knows(channelId)) {
      stages.add(
        _stage(
          'Rendezvous',
          DoctorStatus.warn,
          sw,
          'No channel secret registered — DHT rendezvous is unavailable '
              '(re-pair with a v4 QR code).',
        ),
      );
    } else if (_ownDescriptorsFor(channelId).isEmpty) {
      stages.add(
        _stage(
          'Rendezvous',
          DoctorStatus.warn,
          sw,
          'Channel secret known, but no own mailbox is published yet — the '
              'DHT record cannot advertise a reply address.',
        ),
      );
    } else {
      stages.add(
        _stage(
          'Rendezvous',
          DoctorStatus.ok,
          sw,
          'Own mailbox set is published to the DHT rendezvous record; the '
              'channel can heal even if every host node goes down.',
        ),
      );
    }

    return ChannelDoctorReport(stages);
  }

  /// Builds a [DoctorStage] and stamps it with the elapsed [sw] runtime.
  static DoctorStage _stage(
    String name,
    DoctorStatus status,
    Stopwatch sw,
    String detail,
  ) => DoctorStage(
    name: name,
    status: status,
    durationMs: sw.elapsedMilliseconds,
    detail: detail,
  );

  /// "12 s" / "3 min" / "2 h" / "5 d" — coarse, human-readable duration.
  static String _fmtDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 48) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  /// Builds a garlic hop for the connected node [submitVia] itself, or null
  /// when its identity/encryption key are not yet known. Used as the
  /// last-resort single hop in a degenerate network with no other relay
  /// candidates (T45): the node peels its own layer and deposits/forwards
  /// locally. This carries no relay privacy, but keeps the send path a single,
  /// uniform garlic path — a deposit is NEVER a direct FlaschenpostPut.
  GarlicHop? _selfHop(ActivePeer submitVia) {
    final nodeIdHex = submitVia.discoveredNodeId;
    if (nodeIdHex == null || nodeIdHex.length != GarlicHop.nodeIdLength * 2) {
      return null;
    }
    // T162 review F1: node id AND key from this connection's own handshake
    // (one public export). The peer repository entry for the address may
    // have been overwritten by another node's peer list with a stale or
    // foreign key the node cannot decrypt with.
    final keyHex = submitVia.discoveredEncryptionKey;
    if (keyHex == null || keyHex.length != 64) return null;
    return GarlicHop(
      nodeId: _hexDecode(nodeIdHex),
      encryptionPublicKey: _hexDecode(keyHex),
    );
  }

  /// Selects the forward hop list for one garlic route to a mailbox at
  /// [ohEndpoint] (T45). Prefers genuine relay hops disjoint from
  /// [excludeNodeIds] (sibling routes) and the submit node; when no relay
  /// candidate is left, falls back to routing through the connected node
  /// itself ([selfHop] true). Returns null only when not even a self-hop can
  /// be formed. A self-hop route carries no privacy; it can still request an
  /// R-ACK over a 0-hop return path (the depositing node answers straight into
  /// our own mailbox), which is what [_depositViaGarlicToAll] relies on for
  /// delivery feedback in a degenerate net.
  ({List<GarlicHop> hops, bool selfHop})? _garlicRoute(
    ActivePeer submitVia, {
    String? ohEndpoint,
    Set<String> excludeNodeIds = const {},
  }) {
    var hops = _hopSelector.selectHops(
      count: defaultHopCount,
      excludeAddresses: {submitVia.address, ..._hostAddresses(ohEndpoint)},
      excludeNodeIds: {
        ?submitVia.discoveredNodeId,
        ?_hostNodeId(ohEndpoint),
        ...excludeNodeIds,
      },
    );
    if (hops.isEmpty && excludeNodeIds.isNotEmpty) {
      // Not enough DISJOINT candidates left for this extra route — reuse relay
      // hops rather than degrade to a privacy-less self-hop. Disjointness
      // across routes is best-effort under hop scarcity (fewer than
      // routeCount × hopCount relay candidates).
      hops = _hopSelector.selectHops(
        count: defaultHopCount,
        excludeAddresses: {submitVia.address, ..._hostAddresses(ohEndpoint)},
        excludeNodeIds: {?submitVia.discoveredNodeId, ?_hostNodeId(ohEndpoint)},
      );
    }
    if (hops.isNotEmpty) return (hops: hops, selfHop: false);
    final self = _selfHop(submitVia);
    if (self == null) return null;
    return (hops: [self], selfHop: true);
  }

  /// T45: deposits [payload] into EVERY known counterpart OH in [targets], each over
  /// its OWN garlic route (command 142) — never a direct FlaschenpostPut.
  /// Forward hop sets are kept disjoint across the routes as far as relay
  /// candidates allow (best-effort anti-correlation: no single relay observes
  /// all copies). The receiver deduplicates the copies by message_id.
  ///
  /// The PRIMARY route (first OH) requests an R-ACK when it travels a genuine
  /// relay path, so the send is confirmed and the [NodeScorer] learns which
  /// hops delivered; the remaining routes are redundant fire-and-forget copies
  /// (a single R-ACK expectation avoids sibling-timeout bookkeeping while the
  /// extra copies still add delivery redundancy). A missing R-ACK stays
  /// unconfirmed (T39) — the app re-sends over fresh hops, and the scorer
  /// steers the retry away from a dead hop.
  ///
  /// Throws [DepositException] when not a single route could be built (the
  /// message then stays pending and is retried); a rendezvous recovery is
  /// kicked off so a later retry has fresh targets.
  Future<void> _depositViaGarlicToAll(
    ActivePeer submitVia,
    List<_CounterpartOh> targets,
    Uint8List payload,
    String channelId, {
    String? messageIdHex,
  }) async {
    final usedNodeIds = <String>{};
    var sent = 0;
    var primaryHopCount = 0;
    var primaryAckRequested = false;
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      if (target.ohId.length != GarlicHop.nodeIdLength) continue;
      final route = _garlicRoute(
        submitVia,
        ohEndpoint: target.endpoint,
        excludeNodeIds: usedNodeIds,
      );
      if (route == null) continue;
      // The primary route requests an R-ACK so the send gets delivery feedback
      // (and the app re-sends over fresh hops on a timeout, T39/T41). This is
      // requested even for a self-hop route: the depositing node answers with
      // a RoutingAck (STORED on success, HANDLE_EXPIRED when the OH is not yet
      // hosted / could not be resolved), via a 0-hop return path straight into
      // our own mailbox — so a deposit that races an OH registration in a
      // degenerate net is retried instead of being silently lost.
      final wantAck = i == 0;
      try {
        await _sendViaGarlic(
          submitVia,
          route.hops,
          target.ohId,
          payload,
          channelId,
          messageIdHex: wantAck ? messageIdHex : null,
          diagMessageIdHex: messageIdHex,
          diagTargetHost: target.endpoint,
          diagRouteIndex: i,
        );
      } on DepositException catch (e) {
        // A payload that exceeds the garlic budget is permanently
        // undeliverable — re-sending the SAME content over any route can
        // never succeed, so surface it instead of retrying forever.
        if (e.isBadRequest) rethrow;
        RpLog.info(
          'RedPandaLightClient: garlic deposit to one counterpart OH for channel '
          '$channelId failed: $e',
        );
        continue;
      } catch (e) {
        RpLog.info(
          'RedPandaLightClient: garlic deposit to one counterpart OH for channel '
          '$channelId failed: $e',
        );
        continue;
      }
      sent++;
      for (final hop in route.hops) {
        usedNodeIds.add(_hexEncode(hop.nodeId));
      }
      if (i == 0) {
        primaryHopCount = route.selfHop ? 0 : route.hops.length;
        primaryAckRequested = wantAck && lastSendAckRequested;
      }
    }
    if (sent == 0) {
      unawaited(_recoverViaRendezvous(channelId));
      throw DepositException(
        'no garlic route could be built for channel $channelId',
      );
    }
    // Report the primary route's diagnostics regardless of send order.
    lastSendHopCount = primaryHopCount;
    lastSendViaRgb = false;
    lastSendAckRequested = primaryAckRequested;
  }

  /// Builds a fresh Reverse Garlic Block for [channelId] (MS05) and registers
  /// its session tag, or returns null when the channel has no own OH mailbox
  /// or no eligible return hops are known (the message then travels without
  /// a reply path and the partner falls back to the forward path).
  ///
  /// The RGB is NOT registered yet — [sendMessage] may still swap it for a
  /// smaller one (see [_fitOwnRgb]); [_commitOwnRgb] registers the one that
  /// is actually sent. [closeAtHost] false builds the pre-T162 shape.
  ReverseGarlicBlock? _buildOwnRgb(
    String channelId, {
    bool closeAtHost = true,
  }) {
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .firstOrNull;
    if (ownOh == null) return null;

    // The mailbox host never becomes a return RELAY (mirrors the MS04
    // counterpartOhEndpoint exclusion on the forward path; excluded by
    // address AND node id, it may be known under several addresses) — it
    // closes the path instead (T162, see [_ownHostHop]).
    final host = closeAtHost ? _ownHostHop(ownOh) : null;
    final rgb = _rgbBuilder.build(
      ohId: ownOh.ohId,
      hopCount: defaultHopCount,
      excludeAddresses: _hostAddresses(ownOh.serverEndpoint),
      excludeNodeIds: {
        ?_hostNodeId(ownOh.serverEndpoint),
        if (host != null) _hexEncode(host.nodeId),
      },
      closingHop: host,
    );
    if (rgb == null) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() no eligible return hops known, '
        'sending without a reply path',
      );
    }
    return rgb;
  }

  /// T162/C5 + review F2: the RGB rides inside the encrypted payload, and
  /// closing it at the host adds a hop descriptor (~58 bytes); the R-ACK
  /// return path closed at the host costs another 52 bytes of the acked
  /// budget. Neither may cost a message what it had before T162:
  ///
  /// 1. the R-ACK — a send without one is never re-sent when it is lost. The
  ///    RGB is kept host-closed only while the payload still fits the acked
  ///    budget with a return path WITHOUT the host (the return path itself
  ///    falls back to that shape first, see [_buildReturnPath]); otherwise
  ///    the pre-T162 RGB is used if that keeps the R-ACK;
  /// 2. deliverability — beyond any acked budget, the host-closed RGB, then
  ///    the pre-T162 one, then none, whichever still fits the hard budget.
  ReverseGarlicBlock? _fitOwnRgb(
    String channelId,
    ReverseGarlicBlock? rgb,
    ChannelMessage Function(ReverseGarlicBlock? rgb) messageWith,
  ) {
    if (rgb == null) return null;
    int lengthWith(ReverseGarlicBlock? r) =>
        MessageCryptoV4.minPayloadLength + messageWith(r).encode().length;
    if (_routeFor(channelId, 0).kind == _RouteKind.none) {
      return rgb; // no path at all — the send fails anyway
    }
    ReverseGarlicBlock? open;
    var openBuilt = false;
    ReverseGarlicBlock? openRgb() {
      if (!openBuilt) {
        openBuilt = true;
        final candidate = _endsAtOwnHost(channelId, rgb.hops)
            ? _buildOwnRgb(channelId, closeAtHost: false)
            : null;
        open = candidate != null && candidate.hops.length < rgb.hops.length
            ? candidate
            : null;
      }
      return open;
    }

    // Judged on the route sendMessage will actually take for that length
    // (review G1): the acked budgets of the pending RGB and of the forward
    // path differ, and the route is chosen per payload.
    final withHost = _routeFor(channelId, lengthWith(rgb));
    if (withHost.acked) return rgb;
    final shorter = openRgb();
    if (shorter != null && _routeFor(channelId, lengthWith(shorter)).acked) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() attaching the pre-T162 reply '
        'path to keep the R-ACK',
      );
      return shorter;
    }
    if (withHost.kind != _RouteKind.none) return rgb;
    if (shorter != null &&
        _routeFor(channelId, lengthWith(shorter)).kind != _RouteKind.none) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() payload too large for a '
        'host-closed reply path, attaching the shorter one',
      );
      return shorter;
    }
    RpLog.info(
      'RedPandaLightClient: sendMessage() payload too large to carry a reply '
      'path, sending without one',
    );
    return null;
  }

  /// The route [sendMessage] takes for a payload of [length] bytes on
  /// [channelId], and whether its R-ACK fits — one decision for both the
  /// RGB fitting ([_fitOwnRgb]) and the send (review G1):
  ///
  /// - over the pending partner RGB when the payload fits its tagged budget
  ///   — unless the R-ACK fits only on the forward path (a counterpart OH is
  ///   known, and an own OH exists to receive an R-ACK at all): then the
  ///   forward path, and the RGB stays pending for a later message;
  /// - otherwise the forward garlic path when a counterpart OH is known and
  ///   the payload fits its budget;
  /// - otherwise none.
  ///
  /// The acked budgets assume a return path of [defaultHopCount] relays
  /// WITHOUT the closing host (the shape [_buildReturnPath] falls back to)
  /// and [defaultHopCount] forward hops — conservative in small networks.
  ({_RouteKind kind, bool acked}) _routeFor(String channelId, int length) {
    final pending = _pendingRgbs[channelId];
    final rgbHops = pending != null && !pending.isExpired()
        ? pending.hops.length
        : 0;
    final hasTargets =
        _channelCounterpartOhSet[channelId]?.any(
          (t) => t.ohId.length == GarlicHop.nodeIdLength,
        ) ??
        false;
    final canAck = _registeredOHs.any((oh) => oh.channelId == channelId);
    final rgbFits =
        rgbHops > 0 &&
        length <= GarlicBuilder.maxPayloadLength(rgbHops, tagged: true);
    final rgbAcked =
        rgbFits &&
        canAck &&
        length <=
            GarlicBuilder.maxAckedPayloadLength(
              rgbHops,
              tagged: true,
              returnHopCount: defaultHopCount,
            );
    final forwardFits =
        hasTargets && length <= GarlicBuilder.maxPayloadLength(defaultHopCount);
    final forwardAcked =
        forwardFits &&
        canAck &&
        length <=
            GarlicBuilder.maxAckedPayloadLength(
              defaultHopCount,
              tagged: false,
              returnHopCount: defaultHopCount,
            );
    if (rgbFits && (rgbAcked || !forwardAcked)) {
      return (kind: _RouteKind.viaRgb, acked: rgbAcked);
    }
    if (forwardFits) return (kind: _RouteKind.forward, acked: forwardAcked);
    return (kind: _RouteKind.none, acked: false);
  }

  /// Whether [hops] end at the host of the own OH of [channelId] (as known
  /// from our own handshake, see [_ownHostHop]).
  bool _endsAtOwnHost(String channelId, List<GarlicHop> hops) {
    if (hops.isEmpty) return false;
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .firstOrNull;
    final host = ownOh == null ? null : _ownHostHop(ownOh);
    return host != null &&
        _hexEncode(hops.last.nodeId) == _hexEncode(host.nodeId);
  }

  /// Registers the session tag of the RGB that is actually sent.
  void _commitOwnRgb(String channelId, ReverseGarlicBlock rgb) {
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .firstOrNull;
    final relayCount =
        rgb.hops.length - (_endsAtOwnHost(channelId, rgb.hops) ? 1 : 0);
    if (relayCount < defaultHopCount) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() reply path has only '
        '$relayCount of $defaultHopCount relay hops — reduced privacy',
      );
    }
    _sessionTagStore.store(rgb.sessionTagHex, channelId);
    _emitGarlicSession(channelId);
    if (RpLog.minLevel == LogLevel.debug) {
      RpLog.debug(
        'RedPandaLightClient: T162 rgb built channel=${channelId.substring(0, 8)} '
        'ownOh=${_hexEncode(rgb.ohId).substring(0, 8)} '
        'host=${ownOh?.serverEndpoint} hops=${_diagRoute(rgb.hops)}',
      );
    }
  }

  /// Builds the tagged reply onion over the partner's RGB hops and hands it
  /// to the connected node (command 142). The inner message_id deduplicates
  /// re-sends. With an own OH (MS06) the innermost layer requests an R-ACK.
  Future<void> _sendViaRgb(
    ActivePeer submitVia,
    ReverseGarlicBlock rgb,
    Uint8List payload,
    String channelId, {
    String? messageIdHex,
  }) async {
    final returnPath = messageIdHex != null
        ? _buildReturnPath(
            channelId,
            submitVia,
            messageIdHex: messageIdHex,
            forwardHops: rgb.hops,
            payloadLength: payload.length,
            tagged: true,
          )
        : null;
    final packet = await GarlicBuilder.build(
      hops: rgb.hops,
      ohId: rgb.ohId,
      payload: payload,
      sessionTag: rgb.sessionTag,
      returnPath: returnPath,
    );
    submitVia.sendCommand(_cmdFlaschenpostV2, packet);
    _diagSendAttempt(
      kind: 'rgb-reply',
      submitVia: submitVia,
      hops: rgb.hops,
      targetOhId: rgb.ohId,
      packet: packet,
      channelId: channelId,
      messageIdHex: messageIdHex,
      returnPath: returnPath,
      sessionTagHex: rgb.sessionTagHex,
    );
    _diagSend(
      'rgb-reply',
      channelId: channelId,
      hops: rgb.hops,
      ohId: rgb.ohId,
      messageIdHex: messageIdHex,
      returnPath: returnPath,
    );
    lastSendHopCount = rgb.hops.length;
    lastSendViaRgb = true;
    lastSendAckRequested = returnPath != null;
    RpLog.debug(
      'RedPandaLightClient: sendMessage() submitted a tagged reverse-garlic '
      'reply over ${rgb.hops.length} hops for channel $channelId'
      '${returnPath != null ? ' (R-ACK requested)' : ''}',
    );
  }

  /// Builds the MS06 return-path block for an outgoing message when this
  /// channel has an own OH mailbox to receive the R-ACK, registers the ack
  /// tag, and returns it — or null when no own OH exists, no messageId is
  /// tracked, or the payload would no longer fit the acked budget (the send
  /// then degrades to the un-acked pre-MS06 format).
  ReturnPathBlock? _buildReturnPath(
    String channelId,
    ActivePeer submitVia, {
    required String messageIdHex,
    required List<GarlicHop> forwardHops,
    required int payloadLength,
    required bool tagged,
    String? memberIdHex,
    bool isRotation = false,
  }) {
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .firstOrNull;
    if (ownOh == null) return null;

    // Return hops: same selector and exclusions as the RGB (the ack OH host
    // never relays its own acks; the submit node sees us directly). Like the
    // RGB, the path is closed by the ack OH host itself (T162).
    final closed = _closeAtOwnHost(
      _hopSelector.selectHops(
        count: defaultHopCount,
        excludeAddresses: {
          ..._hostAddresses(ownOh.serverEndpoint),
          submitVia.address,
        },
        excludeNodeIds: {
          ?submitVia.discoveredNodeId,
          ?_hostNodeId(ownOh.serverEndpoint),
        },
      ),
      ownOh,
    );
    bool fits(List<GarlicHop> hops) =>
        payloadLength <=
        GarlicBuilder.maxAckedPayloadLength(
          forwardHops.length,
          tagged: tagged,
          returnHopCount: hops.length,
        );
    // T162 review F2: the closing host costs a hop descriptor of the acked
    // budget — rather drop the host than the R-ACK (a lost unacked send is
    // never re-sent).
    final List<GarlicHop> returnHops;
    if (fits(closed)) {
      returnHops = closed;
    } else if (_endsAtOwnHost(channelId, closed) &&
        fits(closed.sublist(0, closed.length - 1))) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() payload of $payloadLength bytes '
        'too large for a host-closed return path, using the shorter one',
      );
      returnHops = closed.sublist(0, closed.length - 1);
    } else {
      RpLog.info(
        'RedPandaLightClient: sendMessage() payload of $payloadLength bytes '
        'exceeds the acked budget — sending without an R-ACK request',
      );
      return null;
    }

    final ackTag = CryptoUtils.randomBytes(GarlicBuilder.sessionTagLength);
    final ackTagHex = _hexEncode(ackTag);
    _ackTagStore.store(
      ackTagHex,
      channelId: channelId,
      messageIdHex: messageIdHex,
      hopNodeIdsHex: [
        ..._scoredHopIds(forwardHops),
        ..._scoredHopIds(
          returnHops,
          closingHostHex: switch (_ownHostHop(ownOh)) {
            final host? => _hexEncode(host.nodeId),
            null => null,
          },
        ),
      ],
      memberIdHex: memberIdHex,
      isRotation: isRotation,
    );
    return ReturnPathBlock(
      ackOhId: ownOh.ohId,
      ackSessionTag: ackTag,
      hops: returnHops,
    );
  }

  /// Picks up to [defaultHopCount] garlic relay hops for [channelId],
  /// excluding the node the packet is submitted through (anti-correlation:
  /// it sees the sender directly) and the destination OH endpoint.
  List<GarlicHop> _selectGarlicHops(
    String channelId,
    ActivePeer submitVia, {
    // T160/P6: a node to keep off this route entirely (yesterday's rendezvous
    // lookup avoids the node that executed today's).
    String? avoidExitNodeId,
  }) {
    final ohEndpoint = _channelCounterpartOhEndpoints[channelId];
    return _hopSelector.selectHops(
      count: defaultHopCount,
      excludeAddresses: {submitVia.address, ..._hostAddresses(ohEndpoint)},
      excludeNodeIds: {
        // The submission node and the OH host may be known in the peer list
        // under a different address (e.g. seed alias) — exclude by identity too.
        ?submitVia.discoveredNodeId,
        ?_hostNodeId(ohEndpoint),
        ?avoidExitNodeId,
      },
    );
  }

  /// Builds the layered Flaschenpost v2 packet and hands it to the connected
  /// node (command 142), which routes it to the first hop by KademliaId.
  ///
  /// With an own OH mailbox (MS06) the innermost layer is CMD_DELIVER_ACKED
  /// carrying a return path — the depositing node confirms with an R-ACK.
  /// Without one the send stays fire-and-forget; a re-send is deduplicated
  /// at the receiver via the inner message_id either way.
  ///
  /// The `diag*` parameters only feed the T180 `send.attempt` event:
  /// [diagMessageIdHex] names the message even when no R-ACK is requested
  /// (redundant fan-out copies, self-hop loopbacks).
  Future<void> _sendViaGarlic(
    ActivePeer submitVia,
    List<GarlicHop> hops,
    List<int> counterpartOhId,
    Uint8List payload,
    String channelId, {
    String? messageIdHex,
    String diagKind = 'forward',
    String? diagMessageIdHex,
    String? diagTargetHost,
    int? diagRouteIndex,
  }) async {
    if (payload.length > GarlicBuilder.maxPayloadLength(hops.length)) {
      // The fixed 2048-byte packet cannot carry this payload over the
      // selected path — re-sending the same content can never succeed.
      RpLog.info(
        'RedPandaLightClient: sendMessage() payload of ${payload.length} '
        'bytes exceeds the garlic budget of '
        '${GarlicBuilder.maxPayloadLength(hops.length)} bytes',
      );
      throw DepositException(DepositStatus.badRequest);
    }

    if (hops.length < defaultHopCount) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() only ${hops.length} of '
        '$defaultHopCount garlic hops available — reduced privacy',
      );
    }

    final returnPath = messageIdHex != null
        ? _buildReturnPath(
            channelId,
            submitVia,
            messageIdHex: messageIdHex,
            forwardHops: hops,
            payloadLength: payload.length,
            tagged: false,
          )
        : null;
    final packet = await GarlicBuilder.build(
      hops: hops,
      ohId: counterpartOhId,
      payload: payload,
      returnPath: returnPath,
    );
    submitVia.sendCommand(_cmdFlaschenpostV2, packet);
    _diagSendAttempt(
      kind: diagKind,
      submitVia: submitVia,
      hops: hops,
      targetOhId: counterpartOhId,
      packet: packet,
      channelId: channelId,
      messageIdHex: diagMessageIdHex ?? messageIdHex,
      targetHost: diagTargetHost,
      routeIndex: diagRouteIndex,
      returnPath: returnPath,
    );
    _diagSend(
      'forward',
      channelId: channelId,
      hops: hops,
      ohId: counterpartOhId,
      messageIdHex: messageIdHex,
      returnPath: returnPath,
    );
    lastSendHopCount = hops.length;
    lastSendAckRequested = returnPath != null;
    RpLog.debug(
      'RedPandaLightClient: sendMessage() submitted a ${packet.length}-byte '
      'flaschenpost v2 over ${hops.length} hops for channel $channelId'
      '${returnPath != null ? ' (R-ACK requested)' : ''}',
    );
  }

  @override
  Future<OHRegistration> registerOutboundHandle({
    String? channelId,
    Set<String> excludeEndpoints = const {},
    // T180 diagnostics only: why this mailbox is registered — `new`,
    // `redundancy` (top-up to k mailboxes) or `failover`.
    String diagPurpose = 'new',
  }) async {
    final keypair = await OHKeypair.generate();
    final random = Random.secure();
    final ohId = Uint8List.fromList(
      List<int>.generate(20, (_) => random.nextInt(256)),
    );

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 7));
    final request = await _buildRegisterRequest(ohId, keypair, now, expiresAt);

    // Send to best active peer. A failover registration (T21) excludes the
    // dead host so the replacement mailbox lands on a different node.
    final activePeer = _sendablePeers
        .where((p) => !excludeEndpoints.contains(p.address))
        .firstOrNull;
    // T163 review C: protect the target from rotation until the handle is in
    // [_registeredOHs] (or the registration failed).
    final target = activePeer?.address;
    if (target != null) {
      _registrationsInFlight.update(target, (n) => n + 1, ifAbsent: () => 1);
    }
    // T180 diagnostics: what came of this registration.
    var diagResult = 'no_peer';
    try {
      var expiresAtMs = expiresAt.millisecondsSinceEpoch;
      if (activePeer != null) {
        final buffer = request.writeToBuffer();
        RpLog.debug(
          'RedPandaLightClient: registerOutboundHandle() serialized ${buffer.length} bytes',
        );

        // Await the RegisterOhResponse (command 151). The node may reject with
        // RATE_LIMIT (MS02b: max 5 registrations/min per connection) — surface
        // that as a typed error instead of returning a dead registration. On
        // timeout, keep the legacy optimistic behavior (the handle is returned
        // and renewed/confirmed later).
        final completer = _registerResponses.register();
        activePeer.sendCommand(
          _cmdOutboundRegisterOhReq,
          Uint8List.fromList(buffer),
        );

        List<int>? responseBytes;
        try {
          responseBytes = await completer.future.timeout(
            const Duration(seconds: 10),
          );
        } on TimeoutException {
          _registerResponses.abandon(completer);
          diagResult = 'no_response';
          RpLog.info(
            'RedPandaLightClient: registerOutboundHandle() no response within 10s, '
            'returning unconfirmed registration',
          );
        }

        if (responseBytes != null) {
          final response = RegisterOhResponse.fromBuffer(responseBytes);
          if (response.status == Status.RATE_LIMIT) {
            RpLog.info(
              'RedPandaLightClient: registerOutboundHandle() rate-limited',
            );
            diagResult = 'rate_limited';
            throw RateLimitException();
          }
          if (response.status == Status.OK) {
            diagResult = 'ok';
            // The server may clamp the requested TTL.
            expiresAtMs = response.expiresAtMs.toInt();
          } else {
            diagResult = 'status ${response.status}';
            RpLog.info(
              'RedPandaLightClient: registerOutboundHandle() non-OK status: '
              '${response.status}',
            );
          }
        }
      } else {
        RpLog.info(
          'RedPandaLightClient: registerOutboundHandle() no active peer available',
        );
      }

      final registration = OHRegistration(
        ohId: ohId.toList(),
        keypair: keypair,
        expiresAtMs: expiresAtMs,
        channelId: channelId,
        serverEndpoint: activePeer?.address,
      );

      _registeredOHs.add(registration);
      _startPolling();
      // T44: a freshly registered mailbox is a new own-OH — publish/refresh the
      // rendezvous record so peers can discover us over the DHT (idempotent:
      // only republishes when the own-OH set actually changed). Gated on relay
      // availability so it schedules ZERO work on a single-node network, keeping
      // the fragile OH-registration/first-delivery window free of any churn.
      if (channelId != null && _hasRendezvousRelays) {
        unawaited(
          _publishRendezvousIfChanged(channelId, freshRegistration: true),
        );
      }
      // T27: a freshly registered handle means a brand-new channel — the
      // partner's first message is expected shortly, so poll fast right away
      // (fixes the ~30 s first-message latency after a channel join).
      _notePollActivity();
      // T38: subscribe the new handle for real-time Notify.
      _enqueueSubscribe(registration);

      return registration;
    } catch (e) {
      if (diagResult != 'rate_limited') diagResult = 'error: $e';
      rethrow;
    } finally {
      RpDiag.emit(DiagEvt.ohRegister, {
        DiagKey.result: diagResult,
        DiagKey.host: target,
        DiagKey.mailbox: RpDiag.enabled ? _hexEncode(ohId) : null,
        DiagKey.channel: channelId,
        DiagKey.purpose: diagPurpose,
      });
      if (target != null) {
        final left = (_registrationsInFlight[target] ?? 1) - 1;
        if (left <= 0) {
          _registrationsInFlight.remove(target);
        } else {
          _registrationsInFlight[target] = left;
        }
      }
    }
  }

  /// Builds a signed RegisterOhRequest. Signing bytes (v2, Ed25519):
  /// [0x02 | CMD_BYTE(150) | oh_id | requested_expires_at(8 BE) | timestamp_ms(8 BE) | nonce]
  /// (the 0x02 version prefix is added by [OHKeypair.sign]).
  Future<RegisterOhRequest> _buildRegisterRequest(
    List<int> ohId,
    OHKeypair keypair,
    DateTime now,
    DateTime expiresAt,
  ) async {
    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );

    final signingBuffer = BytesBuilder();
    signingBuffer.addByte(_cmdOutboundRegisterOhReq);
    signingBuffer.add(ohId);
    signingBuffer.add(_int64Bytes(expiresAt.millisecondsSinceEpoch));
    signingBuffer.add(_int64Bytes(now.millisecondsSinceEpoch));
    signingBuffer.add(nonce);

    final signature = await keypair.sign(
      Uint8List.fromList(signingBuffer.toBytes()),
    );

    return RegisterOhRequest()
      ..ohId = ohId
      ..ohAuthPublicKey = keypair.publicKeyBytes
      ..requestedExpiresAt = _toInt64(expiresAt.millisecondsSinceEpoch)
      ..timestampMs = _toInt64(now.millisecondsSinceEpoch)
      ..nonce = nonce
      ..signature = signature;
  }

  /// Peers that may carry payload commands: connected with transport
  /// encryption active ([ActivePeer.canSendCommands], T156/TD273).
  ///
  /// EVERY peer selection that ends in [ActivePeer.sendCommand] goes through
  /// this (or checks [ActivePeer.canSendCommands] on a specific peer).
  /// The peer counts and connection status use it too. Only connection
  /// management (backoff, rotation) and diagnostics use
  /// [ActivePeer.isHandshakeVerified] — it flips at the plaintext magic,
  /// before the codec exists, and a command sent then is plaintext the node
  /// drops the connection over.
  Iterable<ActivePeer> get _sendablePeers =>
      _peers.values.where((p) => p.canSendCommands);

  /// The connected peer hosting [oh]'s mailbox.
  ///
  /// OH state (mailbox, cursor, expiry) lives ONLY on the node the handle
  /// was registered with — fetch/ack/renew against any other node returns
  /// NOT_FOUND (observed in the field: after a reconnect the peer map
  /// order changed and every mailbox check silently asked the wrong node).
  /// When the host is currently not connected, a connection attempt is
  /// kicked off and null is returned — the caller skips this cycle and the
  /// next one reaches the host. Registrations without a recorded endpoint
  /// (never talked to a node) fall back to the first sendable peer.
  ActivePeer? _peerForHandle(OHRegistration oh, String what) {
    final endpoint = oh.serverEndpoint;
    if (endpoint == null) return _sendablePeers.firstOrNull;
    final candidate = _livePeerFor(endpoint);
    final host = candidate != null && candidate.canSendCommands
        ? candidate
        : null;
    if (host == null) {
      RpLog.info(
        'RedPandaLightClient: $what: host node $endpoint not connected — '
        'requesting a connection',
      );
      unawaited(addPeer(endpoint));
    }
    return host;
  }

  /// OHs currently being re-registered after a NOT_FOUND fetch, by hex id.
  final Set<String> _reregisteringOhs = {};

  /// Recreates [oh] on its host node after the node answered NOT_FOUND.
  ///
  /// The host no longer knows the handle (registration expired server-side —
  /// e.g. renewals went to the wrong node before the host-node fix, or the
  /// node lost its store) while the LOCAL expiry can still be days away, so
  /// the regular renewal timer would never act and the mailbox would stay
  /// dead until the local expiry. Re-registering with the same id and
  /// keypair recreates the mailbox. The fetch cursor restarts at 0: a fresh
  /// mailbox numbers its items from 1 again, so keeping the old cursor
  /// would silently swallow all new mail.
  Future<void> reregisterLostHandle(OHRegistration oh) async {
    final key = _hexEncode(oh.ohId);
    if (!_reregisteringOhs.add(key)) return;
    try {
      oh.lastCursor = 0;
      // Persist the reset immediately — even when the re-registration
      // below cannot reach the host yet, a restored stale cursor after an
      // app restart must not swallow the recreated mailbox's items.
      _emitState(
        OhMailboxUpdate(
          ohId: oh.ohId,
          channelId: oh.channelId,
          lastCursor: 0,
          expiresAtMs: oh.expiresAtMs,
        ),
      );
      final renewed = await renewOutboundHandle(oh);
      RpLog.info(
        'RedPandaLightClient: re-registered lost handle $key '
        '(confirmed: $renewed)',
      );
    } catch (e) {
      RpLog.info(
        'RedPandaLightClient: re-registration of lost handle $key failed: $e',
      );
    } finally {
      _reregisteringOhs.remove(key);
    }
  }

  /// Counts a host-unreachable fetch failure for [oh] and, at the threshold,
  /// kicks off the OH failover (T21).
  ///
  /// Counted only while an ALTERNATIVE verified node is connected: a dead
  /// host is only provably dead when the rest of the network is reachable —
  /// otherwise this is a local outage (airplane mode, no WiFi) and moving
  /// the mailbox would not help anyone.
  ///
  /// [reason] (why the fetch failed) is diagnostics only (T180).
  void _noteHostUnreachable(OHRegistration oh, String reason) {
    final hostAddresses = _hostAddresses(oh.serverEndpoint);
    final hasAlternative = _sendablePeers.any(
      (p) => !hostAddresses.contains(p.address),
    );
    if (!hasAlternative) return;
    final key = _hexEncode(oh.ohId);
    final count = (_fetchFailureCounts[key] ?? 0) + 1;
    _fetchFailureCounts[key] = count;
    if (RpDiag.enabled) {
      RpDiag.emit(DiagEvt.ohUnreachable, {
        DiagKey.mailbox: key,
        DiagKey.channel: oh.channelId,
        DiagKey.host: oh.serverEndpoint,
        DiagKey.reason: reason,
        DiagKey.failCount: count,
        DiagKey.threshold: failoverFetchFailureThreshold,
        ..._diagHostConditions(oh.serverEndpoint),
      });
    }
    if (count < failoverFetchFailureThreshold) return;

    final channelId = oh.channelId;
    if (channelId == null) return;
    // Group mailboxes (MS08) have no 1:1 ratchet to announce over — out of
    // scope for T21.
    if (_groups.containsKey(channelId)) return;
    if (_failoversInProgress.contains(channelId)) return;
    // Without a forward path to the partner the new mailbox could never be
    // announced — the failover would strand the channel on a handle the
    // partner does not know.
    final counterpartOhId = _channelCounterpartOhIds[channelId];
    if (counterpartOhId == null ||
        counterpartOhId.length != GarlicHop.nodeIdLength) {
      return;
    }
    if (_ratchetSessions[channelId] == null) return;

    unawaited(
      _failoverOwnHandle(
        oh,
        diagReason: reason,
        diagFailCount: count,
      ).catchError((Object e) {
        RpLog.info(
          'RedPandaLightClient: OH failover for channel $channelId failed: $e',
        );
      }),
    );
  }

  /// Moves the channel of [oldOh] to a fresh mailbox on a reachable node
  /// (T21): registers a NEW handle (new id + keypair) on a node other than
  /// the dead host, retires the old handle, publishes the replacement via
  /// an [OwnOhSetUpdate] and queues the in-band `oh_update` announce.
  ///
  /// Messages already deposited in the dead mailbox are not lost silently:
  /// the partner's unacknowledged sends re-queue on R-ACK timeout and are
  /// re-sent — to the new mailbox once the announce arrived.
  ///
  /// [diagReason] / [diagFailCount] only feed the T180 `oh.failover start`
  /// event, emitted here after the re-entry guard so that every `start` is
  /// followed by exactly one `done`.
  Future<void> _failoverOwnHandle(
    OHRegistration oldOh, {
    String? diagReason,
    int? diagFailCount,
  }) async {
    final channelId = oldOh.channelId;
    if (channelId == null) return;
    if (!_failoversInProgress.add(channelId)) return;
    if (RpDiag.enabled) {
      RpDiag.emit(DiagEvt.ohFailover, {
        DiagKey.phase: 'start',
        DiagKey.mailbox: _hexEncode(oldOh.ohId),
        DiagKey.channel: channelId,
        DiagKey.from: oldOh.serverEndpoint,
        DiagKey.reason: diagReason,
        DiagKey.failCount: diagFailCount,
        DiagKey.threshold: failoverFetchFailureThreshold,
        DiagKey.peers: _sendablePeers.length,
        ..._diagHostConditions(oldOh.serverEndpoint),
      });
    }
    // T180 diagnostics: how the failover ended.
    var diagResult = 'error';
    OHRegistration? diagReplacement;
    try {
      final OHRegistration replacement;
      try {
        replacement = await registerOutboundHandle(
          channelId: channelId,
          excludeEndpoints: _hostAddresses(oldOh.serverEndpoint),
          diagPurpose: 'failover',
        );
      } on RateLimitException {
        RpLog.info(
          'RedPandaLightClient: OH failover for channel $channelId '
          'rate-limited — retrying on a later cycle',
        );
        diagResult = 'rate_limited';
        return;
      }
      if (replacement.serverEndpoint == null) {
        // Never reached a node — roll back; the failure counter stays at
        // the threshold, so the next failing fetch retries the failover.
        _registeredOHs.remove(replacement);
        diagResult = 'no_node';
        return;
      }

      diagResult = 'moved';
      diagReplacement = replacement;
      _registeredOHs.remove(oldOh);
      _fetchFailureCounts.remove(_hexEncode(oldOh.ohId));
      RpLog.info(
        'RedPandaLightClient: OH failover for channel $channelId — mailbox '
        'moved from ${oldOh.serverEndpoint} to ${replacement.serverEndpoint}',
      );
      _emitOwnOhSet(channelId);

      // T42: announce the FULL current own-OH set (JSON array), not just the
      // replacement — the partner replaces its whole deposit fan-out set.
      _queueOwnOhAnnounce(channelId);
      await _sendPendingOhUpdate(channelId);
    } finally {
      _failoversInProgress.remove(channelId);
      if (RpDiag.enabled) {
        RpDiag.emit(DiagEvt.ohFailover, {
          DiagKey.phase: 'done',
          DiagKey.mailbox: _hexEncode(oldOh.ohId),
          DiagKey.channel: channelId,
          DiagKey.from: oldOh.serverEndpoint,
          DiagKey.to: diagReplacement?.serverEndpoint,
          DiagKey.toMailbox: diagReplacement == null
              ? null
              : _hexEncode(diagReplacement.ohId),
          DiagKey.result: diagResult,
        });
      }
    }
  }

  /// Emits the current own-OH set of [channelId] (T42) so the app layer syncs
  /// its persisted rows to exactly this set — additions (redundancy top-up)
  /// and failover replacements both flow through here, replacing the old
  /// per-channel handle rows.
  void _emitOwnOhSet(String channelId) {
    final set = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .toList(growable: false);
    // The set is a REPLACEMENT instruction, so an empty one would mean "this
    // channel has no mailbox any more" — a state the app cannot act on today
    // (it would only drop the persisted rows and the replay entries). Both
    // call sites run after a successful registration, so this never fires;
    // the guard keeps [OwnOhSetUpdate.handles]'s never-empty contract true.
    if (set.isEmpty) return;
    _emitState(OwnOhSetUpdate(channelId: channelId, handles: set));
    // T44: our OH set just changed — refresh the rendezvous record so peers
    // can still find us over the DHT (publish on every own-OH change). Gated on
    // relay availability so a single-node network schedules no work here.
    if (_hasRendezvousRelays) {
      unawaited(_publishRendezvousIfChanged(channelId));
    }
  }

  /// T44: if our OH set for [channelId] changed, republish the rendezvous
  /// record. Best-effort — a failed publish is retried on the next change and
  /// by the daily refresh.
  /// Cheap count of known nodes that could serve as garlic relays (have both a
  /// KademliaId and a 32-byte X25519 encryption key). Rendezvous store/lookup
  /// must travel garlic-wrapped to a REMOTE node, so it is only meaningful with
  /// at least two such nodes (the connected submit node plus one relay). On an
  /// isolated single-node network this is 1, keeping the whole rendezvous
  /// network layer dormant so it never competes with the mailbox pairing path.
  bool get _hasRendezvousRelays {
    var n = 0;
    for (final address in _peerRepository.knownAddresses) {
      final peer = _peerRepository.getPeer(address);
      if (peer?.nodeId == null) continue;
      if (peer?.encryptionPublicKey?.length != 64) continue;
      if (++n >= 2) return true;
    }
    return false;
  }

  Future<void> _publishRendezvousIfChanged(
    String channelId, {
    bool freshRegistration = false,
  }) async {
    if (!_hasRendezvousRelays) return;
    if (!_rendezvous.knows(channelId)) return;
    final descriptors = _ownDescriptorsFor(channelId);
    if (descriptors.isEmpty) return;
    if (!_rendezvous.setOwnOhs(channelId, descriptors)) return;
    // T160: the one blind write there is — the creator's very first publish,
    // straight from registering the channel's first own mailbox in this
    // process (channel creation). Everything else reads first.
    if (freshRegistration &&
        _rendezvous.isCreatorOf(channelId) == true &&
        _creatorFirstPublishUsed.add(channelId) &&
        !_rendezvousPublishedOnce.contains(channelId) &&
        !_rendezvous.knowsCounterpartEntry(channelId) &&
        !_hasCounterpartOh(channelId) &&
        _registeredOHs.where((oh) => oh.channelId == channelId).length == 1) {
      _creatorFirstPublish.add(channelId);
    }
    // Force a republish of the changed set (drop any prior publish stamp so
    // the poll-cycle retry also kicks in should this attempt find no hops).
    _lastRendezvousPublish.remove(channelId);
    await _publishRendezvous(channelId);
  }

  /// T44/T160: publishes the channel's rendezvous record — after READING it
  /// first whenever this side knows no entry of the counterpart
  /// ([_needsReadBeforeWrite]). A publish requested while such a read is in
  /// flight returns: the held publish writes the current own-OH set when it
  /// ends, so nothing is lost.
  Future<void> _publishRendezvous(String channelId) async {
    // Review 2/Q2: the creation exemption is used up by the FIRST attempt,
    // whatever its outcome — a retry seconds or hours later (no sendable
    // peer, no hops, a build error the first time) may come after the
    // joiner has written, so it reads first like any other publish.
    final blindFirst = _creatorFirstPublish.remove(channelId);
    if (_prePublishHolds.containsKey(channelId)) return;
    if (blindFirst) {
      await _publishRendezvousNow(channelId);
      return;
    }
    if (_needsReadBeforeWrite(channelId)) {
      await _publishAfterRead(channelId);
      return;
    }
    await _publishRendezvousNow(channelId);
  }

  /// T160: a side that knows no entry of the counterpart must not write the
  /// channel's ONE rendezvous record before it has read it. The node keeps
  /// only the newest record (`KadStoreManager.put`, strictly higher
  /// timestamp wins), so a blind write replaces every entry the writer has
  /// not seen. This holds for EVERY publish of such a side — first,
  /// change-driven and periodic, joiner and creator alike: a joiner whose
  /// read timed out has written only itself, and a creator that was offline
  /// at the scan, restarted, or registered late would otherwise erase the
  /// joiner on each 3-minute republish while neither side reads (review
  /// P1/P2/P4). The single exception is the creator's first publish at
  /// channel creation ([_creatorFirstPublish]): there is nothing to read yet,
  /// and holding it would only widen the window in which a quick scan finds
  /// no record at all.
  bool _needsReadBeforeWrite(String channelId) =>
      _rendezvous.knows(channelId) &&
      !_rendezvous.knowsCounterpartEntry(channelId);

  bool _hasCounterpartOh(String channelId) =>
      _channelCounterpartOhSet[channelId]?.isNotEmpty ?? false;

  /// T160: read-before-write. Sends today's lookup first and holds the
  /// publish until a record found under today's key has been merged (see
  /// [_PrePublishHold] for why nothing else releases it) — at most
  /// [RendezvousTiming.prePublishHoldMax]: a counterpart that is offline or
  /// whose store was lost must not keep this side out of the DHT. The held
  /// publish writes the MERGED record. If no lookup could be sent (no relay
  /// hops, no own mailbox) nothing is written; the republish sweep retries,
  /// with the read first.
  ///
  /// A joiner that does not know the counterpart's mailboxes yet also starts
  /// its pairing lookup sequence here (once per channel and worker), and its
  /// first round asks yesterday's key too — on its own route, a moment
  /// later — so a creator that last published before UTC midnight is found.
  Future<void> _publishAfterRead(String channelId) async {
    final hold = _PrePublishHold();
    _prePublishHolds[channelId] = hold;
    var sent = 0;
    try {
      // Review 2/Q5: the sequence (and with it the first round's
      // yesterday lookup) starts only with a lookup that actually went out;
      // a read that could not be sent leaves it for the next attempt.
      final wantsPairing =
          _rendezvous.isCreatorOf(channelId) == false &&
          !_hasCounterpartOh(channelId) &&
          !_pairingSequenceStarted.contains(channelId);
      sent = await _lookupRendezvous(
        channelId,
        force: true,
        includeYesterday: wantsPairing,
        hold: hold,
      );
      if (wantsPairing && sent > 0 && _pairingSequenceStarted.add(channelId)) {
        _schedulePairingLookup(channelId);
      }
      if (sent > 0) {
        final holdMax = _rendezvousTiming.prePublishHoldMax;
        RpLog.debug(
          'RedPandaLightClient: rendezvous publish for $channelId held until '
          'the lookup answers (max ${holdMax.inMilliseconds} ms)',
        );
        final answered = await hold.done.future
            .then((_) => true)
            .timeout(holdMax, onTimeout: () => false);
        if (!answered) {
          RpLog.info(
            'RedPandaLightClient: rendezvous lookup for $channelId did not '
            'answer within ${holdMax.inMilliseconds} ms — publishing the own '
            'entry anyway (a late answer still merges and republishes)',
          );
        }
      }
    } catch (e) {
      RpLog.info(
        'RedPandaLightClient: rendezvous read-before-write for $channelId '
        'failed: $e',
      );
    } finally {
      _prePublishHolds.remove(channelId);
    }
    if (_disconnected) return;
    if (sent == 0) {
      // Nothing was read, so nothing may be written. The stamp stays as it
      // was: a never-published or changed set retries on the next sweep
      // (30 s), a periodic refresh on the one after.
      RpLog.debug(
        'RedPandaLightClient: rendezvous publish for $channelId deferred — '
        'no lookup could be sent',
      );
      return;
    }
    _lastRendezvousPublish.remove(channelId);
    await _publishRendezvousNow(channelId);
  }

  /// T160: the creator's first publish at channel creation — the only one
  /// that does not read first (see [_needsReadBeforeWrite]).
  final Set<String> _creatorFirstPublish = {};

  /// Channels whose creation exemption has been granted once (it is never
  /// granted again in this worker, review 2/Q2).
  final Set<String> _creatorFirstPublishUsed = {};

  /// Channels this worker has published a rendezvous record for.
  final Set<String> _rendezvousPublishedOnce = {};

  /// T44: builds the signed rendezvous record and stores it in the DHT via a
  /// `record_store` garlic packet routed to a REMOTE node (the connected node
  /// never sees the query interest). Best-effort, no response.
  Future<bool> _publishRendezvousNow(String channelId) async {
    try {
      final submitVia = _sendablePeers.firstOrNull;
      if (submitVia == null) return false;
      // Select hops BEFORE building the record so the per-poll-cycle retry does
      // no signing/AEAD work while no relay path exists (e.g. a single-node
      // network) — it just no-ops until hops appear.
      final hops = _selectGarlicHops(channelId, submitVia);
      if (hops.isEmpty) {
        RpLog.debug(
          'RedPandaLightClient: rendezvous publish for $channelId skipped — '
          'no relay hops known',
        );
        return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final store = await _rendezvous.buildSignedStore(channelId, now);
      if (store == null) return false;
      final packet = await GarlicBuilder.buildRecordStore(
        hops: hops,
        kademliaStore: store,
      );
      submitVia.sendCommand(_cmdFlaschenpostV2, packet);
      // Mark as published only on an actual send with hops — otherwise the
      // poll cycle keeps retrying until garlic hops become available (the
      // publish-on-registration can race ahead of hop discovery).
      _lastRendezvousPublish[channelId] = DateTime.now();
      _rendezvousPublishedOnce.add(channelId);
      RpLog.debug(
        'RedPandaLightClient: published rendezvous record for $channelId over '
        '${hops.length} hops',
      );
      return true;
    } catch (e) {
      RpLog.info('RedPandaLightClient: rendezvous publish failed: $e');
      return false;
    }
  }

  /// T44: recovery — all of a counterpart's OHs are unreachable, so look the channel's
  /// rendezvous record up over the DHT (today's key, then yesterday's) and
  /// adopt the counterpart's current OH list. The lookups travel garlic-wrapped to a
  /// remote node; the answer returns via a reverse-garlic return path into our
  /// own OH mailbox and is correlated in the fetch loop by its ack tag.
  Future<void> _recoverViaRendezvous(String channelId) async {
    await _lookupRendezvous(channelId, includeYesterday: true);
  }

  /// T160/P6: one lookup round — today's key now and, if [includeYesterday],
  /// yesterday's key after [RendezvousTiming.yesterdayOffset] on a route of
  /// its own that avoids today's executing node, so no single node sees
  /// both UTC-day keys of the channel together. Returns how many of today's
  /// lookups went out; never throws.
  Future<int> _lookupRendezvous(
    String channelId, {
    bool force = false,
    bool includeYesterday = false,
    _PrePublishHold? hold,
  }) async {
    final sent = await _sendRendezvousLookup(
      channelId,
      force: force,
      hold: hold,
    );
    if (sent > 0 && includeYesterday) {
      final avoid = _lastLookupExit[channelId];
      _yesterdayLookupTimers[channelId]?.cancel();
      _yesterdayLookupTimers[channelId] = Timer(
        _rendezvousTiming.yesterdayOffset(),
        () {
          _yesterdayLookupTimers.remove(channelId);
          if (_disconnected) return;
          unawaited(
            _sendRendezvousLookup(
              channelId,
              force: true,
              day: 1,
              hold: _prePublishHolds[channelId],
              avoidExitNodeId: avoid,
            ),
          );
        },
      );
    }
    return sent;
  }

  /// The executing (last forward) node of each channel's latest today-key
  /// lookup — yesterday's lookup of the same round avoids it (P6).
  final Map<String, String> _lastLookupExit = {};
  final Map<String, Timer> _yesterdayLookupTimers = {};

  /// Sends ONE rendezvous lookup of [channelId] — today's key ([day] 0) or
  /// yesterday's ([day] 1) — and returns how many went out (0 or 1); never
  /// throws. Throttled to one attempt per [_recoveryMinInterval] unless
  /// [force]d — the T160 pairing sequence runs on its own bounded schedule,
  /// and its attempts stamp the throttle so the failing sends of the same
  /// pairing do not pile extra lookups on top. A [hold] gets the lookup's
  /// ack tag before the packet leaves, so its answer is correlated with the
  /// held publish however early it comes back.
  Future<int> _sendRendezvousLookup(
    String channelId, {
    bool force = false,
    int day = 0,
    _PrePublishHold? hold,
    String? avoidExitNodeId,
  }) async {
    try {
      return await _sendRendezvousLookupUnguarded(
        channelId,
        force: force,
        day: day,
        hold: hold,
        avoidExitNodeId: avoidExitNodeId,
      );
    } catch (e) {
      RpLog.info('RedPandaLightClient: rendezvous lookup failed: $e');
      return 0;
    }
  }

  Future<int> _sendRendezvousLookupUnguarded(
    String channelId, {
    required bool force,
    required int day,
    required _PrePublishHold? hold,
    required String? avoidExitNodeId,
  }) async {
    if (!_hasRendezvousRelays) return 0;
    if (!_rendezvous.knows(channelId)) return 0;
    // Throttle first (before any peer scan / key derivation): recovery fires
    // on every failing send/deposit, so a retry burst must be cheaply rejected.
    final nowThrottle = DateTime.now();
    final lastAttempt = _lastRecoveryAttempt[channelId];
    if (!force &&
        lastAttempt != null &&
        nowThrottle.difference(lastAttempt) < _recoveryMinInterval) {
      return 0;
    }
    final submitVia = _sendablePeers.firstOrNull;
    if (submitVia == null) return 0;
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId && oh.serverEndpoint != null)
        .firstOrNull;
    if (ownOh == null) return 0; // need an own mailbox to receive the answer

    // Select the relay path FIRST. A record_lookup can only travel
    // garlic-wrapped to a remote node, so with no eligible hops (e.g. a
    // single-node network) recovery is impossible — bail out BEFORE the
    // key-derivation work. This is critical: the derivations below run pure-
    // Dart Ed25519/X25519 keygen on the single-threaded network isolate, and
    // recovery is triggered on every send failure — doing that keygen when we
    // could never send would stall the isolate (fetch/register timeouts).
    var hops = _selectGarlicHops(
      channelId,
      submitVia,
      avoidExitNodeId: avoidExitNodeId,
    );
    if (hops.isEmpty && avoidExitNodeId != null) {
      // Review 2/Q1: in a small network today's executing node may be the
      // only candidate. Losing yesterday's lookup (a creator offline across
      // UTC midnight would stay unfindable) is worse than one node seeing
      // both keys, so fall back to an ordinary route — still a separate
      // packet, still offset in time.
      hops = _selectGarlicHops(channelId, submitVia);
      if (hops.isNotEmpty) {
        RpLog.info(
          'RedPandaLightClient: no route avoids the node of today\'s '
          'rendezvous lookup — yesterday\'s lookup takes an ordinary route',
        );
      }
    }
    if (hops.isEmpty) return 0;
    if (day == 0) _lastLookupExit[channelId] = _hexEncode(hops.last.nodeId);

    // Commit to an attempt only now that we know it can actually be sent.
    _lastRecoveryAttempt[channelId] = nowThrottle;

    // T162: closed by our mailbox host like every own-mailbox path, so the
    // answer is deposited there instead of being resolved via the DHT.
    final returnHops = _closeAtOwnHost(
      _hopSelector.selectHops(
        count: defaultHopCount,
        excludeAddresses: {
          ..._hostAddresses(ownOh.serverEndpoint),
          submitVia.address,
        },
        excludeNodeIds: {
          ?submitVia.discoveredNodeId,
          ?_hostNodeId(ownOh.serverEndpoint),
        },
      ),
      ownOh,
    );
    final now = nowThrottle.millisecondsSinceEpoch;
    final keys = await _rendezvous.lookupKeys(channelId, now);
    var sent = 0;
    for (final recordKey in [keys[day]]) {
      try {
        final ackTag = CryptoUtils.randomBytes(GarlicBuilder.sessionTagLength);
        final ackTagHex = _hexEncode(ackTag);
        _recordLookupTags[ackTagHex] = channelId;
        hold?.track(ackTagHex, decisive: day == 0);
        _recordLookupTagCreatedAt[ackTagHex] = DateTime.now();
        final packet = await GarlicBuilder.buildRecordLookup(
          hops: hops,
          recordKey: recordKey,
          returnPath: ReturnPathBlock(
            ackOhId: ownOh.ohId,
            ackSessionTag: ackTag,
            hops: returnHops,
          ),
        );
        submitVia.sendCommand(_cmdFlaschenpostV2, packet);
        sent++;
        RpLog.debug(
          'RedPandaLightClient: rendezvous lookup for $channelId sent over '
          '${hops.length} hops',
        );
      } catch (e) {
        RpLog.info('RedPandaLightClient: rendezvous lookup failed: $e');
      }
    }
    return sent;
  }

  /// Minimum spacing between rendezvous recovery attempts per channel.
  static const Duration _recoveryMinInterval = Duration(seconds: 30);
  final Map<String, DateTime> _lastRecoveryAttempt = {};

  /// T160: publishes held until their read-before-write lookup answered.
  final Map<String, _PrePublishHold> _prePublishHolds = {};

  /// T160: channels whose pairing lookup sequence has been started (once
  /// per channel and worker).
  final Set<String> _pairingSequenceStarted = {};

  /// T160: the pending timer and the attempts used of each channel's
  /// pairing lookup sequence.
  final Map<String, Timer> _pairingLookupTimers = {};
  final Map<String, int> _pairingLookupAttempts = {};

  /// Number of pairing lookups sent for [channelId] after the first one
  /// (diagnostics and tests).
  int pairingLookupAttemptsOf(String channelId) =>
      _pairingLookupAttempts[channelId] ?? 0;

  /// Whether the pairing lookup sequence of [channelId] is still running.
  bool pairingLookupsActive(String channelId) =>
      _pairingLookupTimers.containsKey(channelId);

  /// Arms the next step of the T160 pairing lookup sequence of [channelId]
  /// ([RendezvousTiming.pairingDelay]: jittered, today's key only — the
  /// first round already asked yesterday's). A step that fails still arms
  /// the next one: the sequence ends only when it is used up or the
  /// counterpart is known.
  void _schedulePairingLookup(String channelId) {
    if (_disconnected) return;
    final attempt = _pairingLookupAttempts[channelId] ?? 0;
    if (attempt >= _rendezvousTiming.pairingLookupDelays.length) {
      RpLog.info(
        'RedPandaLightClient: pairing lookups for $channelId exhausted '
        'without a counterpart mailbox — falling back to the failing-send '
        'recovery and the read before every republish',
      );
      return;
    }
    _pairingLookupTimers[channelId]?.cancel();
    _pairingLookupTimers[channelId] = Timer(
      _rendezvousTiming.pairingDelay(attempt),
      () {
        _pairingLookupTimers.remove(channelId);
        if (_disconnected || !_rendezvous.knows(channelId)) return;
        if (_hasCounterpartOh(channelId)) return;
        _pairingLookupAttempts[channelId] = attempt + 1;
        unawaited(
          // Review 2/Q4: a hold still waiting (its first answer lost) is
          // released by the found answer of this step as well.
          _lookupRendezvous(
                channelId,
                force: true,
                hold: _prePublishHolds[channelId],
              )
              .catchError((Object e) {
                RpLog.info(
                  'RedPandaLightClient: pairing lookup for $channelId '
                  'failed: $e',
                );
                return 0;
              })
              .whenComplete(() => _schedulePairingLookup(channelId)),
        );
      },
    );
  }

  void _stopPairingLookups(String channelId) {
    _pairingLookupTimers.remove(channelId)?.cancel();
  }

  /// T44: handles a `record_lookup` reverse-garlic answer
  /// (`[1 status][KademliaStore]`). On a found + valid + newer record, adopts
  /// the counterpart's OH list into the deposit fan-out set.
  Future<void> _handleRecordLookupAnswer(
    String channelId,
    List<int> payload, {
    String? tagHex,
  }) async {
    try {
      if (payload.isEmpty) return;
      final status = payload[0];
      if (status == 0) {
        // Info, not debug: a visible found=false streak lets a CI timeout log
        // name its cause (e.g. a lost first store waiting out the 3-minute
        // republish window) instead of timing out silently (T91/TD023).
        RpLog.info(
          'RedPandaLightClient: rendezvous lookup for $channelId — no record',
        );
        _prePublishHolds[channelId]?.answered(tagHex, found: false);
        return;
      }
      if (payload.length < 2) {
        // Distinct from "no record": status claims found but the record bytes
        // are missing — that is a malformed answer, not an empty DHT.
        RpLog.info(
          'RedPandaLightClient: rendezvous lookup for $channelId — malformed '
          'answer (status $status, no record bytes)',
        );
        _prePublishHolds[channelId]?.answered(tagHex, found: false);
        return;
      }
      final record = RendezvousManager.recordFromStoreBytes(payload.sublist(1));
      final now = DateTime.now().millisecondsSinceEpoch;
      final mergeStateBefore = _rendezvous.exportMergeState(channelId);
      final resolved = await _rendezvous.applyResolvedRecordDetailed(
        channelId,
        record,
        now,
      );
      final counterpartOhs = resolved?.counterpartOhs;
      // T160: a held publish waits for exactly this — the merge state now
      // holds whatever the record carried, so the held publish writes the
      // merged record. An invalid record counts as "nothing found".
      final hold = _prePublishHolds[channelId];
      if (hold != null) {
        hold.answered(tagHex, found: resolved != null);
        // Review 2/Q3: a record found under YESTERDAY's key was merged but
        // does not release the hold, and adopting its mailboxes ends the
        // pairing sequence — ask today's key once more (on a fresh route),
        // so the held write can carry today's creator entry instead of
        // waiting out the hold and writing yesterday's over it.
        if (resolved != null && hold.claimTodayReask(tagHex)) {
          unawaited(_sendRendezvousLookup(channelId, force: true, hold: hold));
        }
      } else if (resolved != null && resolved.needsRepair) {
        // T160 read-repair: the record in the DHT lacks what we know — either
        // someone wrote it without our current entry (the node keeps only
        // the newest record), or this answer taught us an entry our own last
        // write did not carry (a late answer after a timed-out hold). Write
        // the merged record so the entries of every side survive.
        RpLog.info(
          'RedPandaLightClient: rendezvous record for $channelId lacks an '
          'entry we know — republishing the merged record',
        );
        _lastRendezvousPublish.remove(channelId);
        unawaited(_publishRendezvousNow(channelId));
      }
      // TD117: the merge state is the only place the counterpart's entry_ts
      // lives, and a resolved record is the only way we learn about OTHER
      // participants (publishing also touches the state, but only to re-stamp
      // our own entry from live state, which a respawned worker regenerates).
      // Emit before the early-outs below: a record can advance a third
      // participant (or a counterpart entry that carries no newer OH list)
      // without changing the deposit set, and that knowledge must still
      // survive a respawn. Two lookups in flight (today's + yesterday's key)
      // may both emit; each snapshot is the full current state, so a
      // duplicate is harmless.
      final mergeStateAfter = _rendezvous.exportMergeState(channelId);
      if (mergeStateAfter != null && mergeStateAfter != mergeStateBefore) {
        _emitState(
          RendezvousStateUpdate(
            channelId: channelId,
            mergeStateJson: mergeStateAfter,
          ),
        );
      }
      if (counterpartOhs == null || counterpartOhs.isEmpty) return;
      final changed = _replaceCounterpartOhSet(channelId, counterpartOhs);
      if (changed) {
        _emitCounterpartOhUpdate(channelId, counterpartOhs);
        RpLog.info(
          'RedPandaLightClient: rendezvous recovery for $channelId adopted '
          '${counterpartOhs.length} counterpart OH(s) from the DHT record',
        );
        // T161: we found the counterpart over the DHT, so the counterpart
        // has most likely never heard of OUR mailboxes (a joiner's first
        // contact, or a heal after the counterpart lost our set). Announce
        // the full own set in-band right away — before this, the only
        // announce was the one queued at the redundancy top-up, which was
        // dropped because no counterpart mailbox was known at that time.
        _queueOwnOhAnnounce(channelId);
        unawaited(
          _sendPendingOhUpdate(channelId).catchError((Object e) {
            RpLog.info(
              'RedPandaLightClient: oh_update announce after the rendezvous '
              'adoption for $channelId failed (will retry on the poll '
              'loop): $e',
            );
          }),
        );
      }
    } catch (e) {
      RpLog.info('RedPandaLightClient: rendezvous answer decode failed: $e');
    }
  }

  /// Queues an `oh_update` announce of the current own-OH descriptor array
  /// for [channelId] (T42). A pending announce for the channel is replaced
  /// (the newest set supersedes it).
  void _queueOwnOhAnnounce(String channelId) {
    final descriptors = _ownDescriptorsFor(channelId);
    if (descriptors.isEmpty) return;
    final random = Random.secure();
    _pendingOhUpdates[channelId] = _PendingOhUpdate(
      messageId: Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)),
      ),
      descriptorsJson: jsonEncode(
        descriptors.map((d) => d.toJsonMap()).toList(),
      ),
    );
  }

  /// Whether an own-mailbox `oh_update` announce is waiting to be sent for
  /// [channelId] (diagnostics and tests).
  bool hasPendingOhAnnounce(String channelId) =>
      _pendingOhUpdates.containsKey(channelId);

  /// Test seam: queues the announce exactly like the redundancy top-up and
  /// the failover do (both need several verified nodes to get there).
  @visibleForTesting
  void queueOwnOhAnnounceForTesting(String channelId) =>
      _queueOwnOhAnnounce(channelId);

  /// Test seam: one announce attempt, as the poll loop makes it.
  @visibleForTesting
  Future<void> flushPendingOhAnnounceForTesting(String channelId) =>
      _sendPendingOhUpdate(channelId);

  /// Remaining re-send budget of the pending announce (tests).
  @visibleForTesting
  int? pendingOhAnnounceSendsLeftForTesting(String channelId) =>
      _pendingOhUpdates[channelId]?.remainingSends;

  /// Redundancy fixed at k=3 own mailboxes on disjoint nodes (T42). Not a
  /// configuration knob — hard-coded per the plan.
  ///
  /// Bounded from above by the rendezvous record: the whole own OH set is
  /// published into the fixed `ChannelRendezvous.recordSizeBytes` bucket (996
  /// usable bytes), where two participants at k=3 need ~556 bytes on IPv4 and
  /// ~700 on IPv6. k=3 is the last value that also fits three participants
  /// (~833 bytes on IPv4); k=4 overflows at three participants. An overflow
  /// surfaces only as a swallowed publish error, so raise the bucket on BOTH
  /// sides (backend `ChannelDht.RECORD_SIZE_BYTES`) before raising k.
  static const int ohRedundancy = 3;

  /// How often the poll cycle tops channels up to [ohRedundancy] (T111).
  /// The sweep itself is cheap when nothing is missing, but a top-up performs
  /// OH registrations, so it must not run at the fast chat cadence.
  static const Duration redundancySweepInterval = Duration(minutes: 1);
  DateTime? _lastRedundancySweep;

  /// Guards re-entry: the sweep is started fire-and-forget by the poll cycle,
  /// so a slow one must not be joined by the next cycle's.
  bool _redundancySweepInProgress = false;

  /// Tops every known channel up to [ohRedundancy] own mailboxes (T42),
  /// throttled to [redundancySweepInterval]. Only channels that already hold
  /// at least one mailbox are topped up: creating a channel's FIRST mailbox
  /// stays with the app layer (it needs the descriptor synchronously for the
  /// QR code and the rendezvous record), and sweeping from zero would race
  /// that registration onto a second mailbox on the same node.
  ///
  /// Public like [checkAndRenewExpiringHandles], the other periodic
  /// maintenance task: the poll cycle drives it, tests call it directly.
  Future<void> sweepOhRedundancy() async {
    if (_redundancySweepInProgress) return;
    final now = DateTime.now();
    final last = _lastRedundancySweep;
    if (last != null && now.difference(last) < redundancySweepInterval) return;
    _lastRedundancySweep = now;
    _redundancySweepInProgress = true;
    try {
      for (final channelId in _restoredChannels.toList()) {
        if (!_registeredOHs.any((oh) => oh.channelId == channelId)) continue;
        // A T21 failover is mid-flight: its dead handle still counts towards
        // the redundancy target, so a top-up now would register against a set
        // that is about to change — and `_failoverOwnHandle` is written on the
        // assumption that nothing else registers for the channel meanwhile.
        // The next sweep sees the settled set.
        if (_failoversInProgress.contains(channelId)) continue;
        try {
          await ensureOhRedundancy(channelId);
        } catch (e) {
          RpLog.info(
            'RedPandaLightClient: OH redundancy top-up for $channelId '
            'failed: $e',
          );
        }
      }
    } finally {
      _redundancySweepInProgress = false;
    }
  }

  @override
  Future<void> ensureOhRedundancy(String channelId) async {
    // Only 1:1 channels with a live ratchet get a multi-OH announce path;
    // group mailboxes (MS08) are out of scope for T42.
    if (_groups.containsKey(channelId)) return;
    if (_ratchetSessions[channelId] == null) return;

    var own = _registeredOHs.where((oh) => oh.channelId == channelId).toList();
    // Disjointness is by NODE IDENTITY, not just address (T42): the same Full
    // Node can appear under more than one address during a flaky reconnect,
    // and must never be mistaken for a second, redundant node — otherwise the
    // top-up spuriously registers a second mailbox on the SAME node (observed
    // in the single-node emulator gate). Endpoints AND node ids already
    // hosting one of our OHs are excluded.
    final usedEndpoints = <String>{
      for (final oh in own) ..._hostAddresses(oh.serverEndpoint),
    };
    final usedNodeIds = <String>{
      for (final oh in own)
        if (oh.serverEndpoint != null &&
            _livePeerFor(oh.serverEndpoint!)?.discoveredNodeId != null)
          _livePeerFor(oh.serverEndpoint!)!.discoveredNodeId!,
    };
    // Without a known node id for at least one existing OH host we cannot
    // prove a candidate is a DIFFERENT node — defer to a later cycle (node ids
    // are learned right after the handshake, so the next chat-open retries).
    if (own.isNotEmpty && usedNodeIds.isEmpty) return;

    var changed = false;
    while (own.length < ohRedundancy) {
      // A disjoint node must be verified, on a new address AND expose a new,
      // KNOWN node id. When none exists (e.g. the single-node gate) redundancy
      // gracefully degrades to the single reachable mailbox.
      final hasDisjoint = _sendablePeers.any(
        (p) =>
            !usedEndpoints.contains(p.address) &&
            p.discoveredNodeId != null &&
            !usedNodeIds.contains(p.discoveredNodeId),
      );
      if (!hasDisjoint) break;
      final OHRegistration extra;
      try {
        extra = await registerOutboundHandle(
          channelId: channelId,
          excludeEndpoints: usedEndpoints,
          diagPurpose: 'redundancy',
        );
      } on RateLimitException {
        break; // retried on a later cycle
      }
      final endpoint = extra.serverEndpoint;
      final nodeId = endpoint == null
          ? null
          : _peers[endpoint]?.discoveredNodeId;
      if (endpoint == null ||
          usedEndpoints.contains(endpoint) ||
          nodeId == null ||
          usedNodeIds.contains(nodeId)) {
        // Never reached a genuinely fresh node — roll back and stop.
        _registeredOHs.remove(extra);
        break;
      }
      usedEndpoints.add(endpoint);
      usedNodeIds.add(nodeId);
      own = _registeredOHs.where((oh) => oh.channelId == channelId).toList();
      changed = true;
    }
    if (!changed) return;
    _emitOwnOhSet(channelId);
    // Announce the enlarged set to the partner so their deposits fan out.
    _queueOwnOhAnnounce(channelId);
    try {
      await _sendPendingOhUpdate(channelId);
    } catch (e) {
      RpLog.info(
        'RedPandaLightClient: initial oh_update announce for channel '
        '$channelId failed (will retry on the poll loop): $e',
      );
    }
  }

  /// Sends the queued `oh_update` announce for [channelId] to the partner's
  /// mailbox — ratchet-encrypted like any regular message and, since T45, over
  /// GARLIC like any other deposit (never a direct FlaschenpostPut; binding
  /// user decision 2026-07-20). It is deposited into EVERY known counterpart OH (one
  /// hop-disjoint route each) and re-sent on the poll loop over fresh hops
  /// (the [_PendingOhUpdate.remainingSends] budget), so a single dead relay
  /// hop cannot swallow the one message the channel's healing depends on — the
  /// robustness that used to come from the direct deposit now comes from the
  /// budgeted re-send over fresh hops plus the R-ACK-fed scorer steering away
  /// from a bad hop. In a degenerate net the route falls back to the connected
  /// node itself. Each attempt re-encrypts with a fresh message key but keeps
  /// the SAME message id, so the partner applies the first copy and ignores
  /// the duplicates.
  Future<void> _sendPendingOhUpdate(String channelId) async {
    // One send per channel at a time: the poll loop, the failover, the
    // redundancy top-up and both counterpart adoptions all trigger this, and
    // concurrent calls would burn the re-send budget in one burst over the
    // same moment instead of spreading it over fresh hops on later cycles.
    // A call that arrives while a send is in flight is remembered; it runs
    // afterwards only if a NEWER announce has been queued meanwhile.
    if (!_ohUpdateSendsInFlight.add(channelId)) {
      _ohUpdateSendRequested.add(channelId);
      return;
    }
    _PendingOhUpdate? handled;
    try {
      handled = _pendingOhUpdates[channelId];
      await _sendPendingOhUpdateOnce(channelId);
    } finally {
      _ohUpdateSendsInFlight.remove(channelId);
    }
    if (_ohUpdateSendRequested.remove(channelId)) {
      final current = _pendingOhUpdates[channelId];
      if (current != null && !identical(current, handled)) {
        await _sendPendingOhUpdate(channelId);
      }
    }
  }

  final Set<String> _ohUpdateSendsInFlight = {};
  final Set<String> _ohUpdateSendRequested = {};

  Future<void> _sendPendingOhUpdateOnce(String channelId) async {
    final pending = _pendingOhUpdates[channelId];
    if (pending == null) return;
    final sessionFuture = _ratchetSessions[channelId];
    if (sessionFuture == null) {
      // The channel has no ratchet session any more (disconnect/reset) —
      // nothing could ever encrypt the announce; drop the stale entry.
      if (identical(_pendingOhUpdates[channelId], pending)) {
        _pendingOhUpdates.remove(channelId);
      }
      return;
    }
    final targets = _channelCounterpartOhSet[channelId];
    if (targets == null || targets.isEmpty) {
      // T161: no counterpart mailbox known YET — the normal state of a
      // joiner between the redundancy top-up and the rendezvous answer. Keep
      // the announce (budget untouched): adopting a counterpart set sends it
      // (rendezvous: [_handleRecordLookupAnswer]; in-band:
      // [_handleCounterpartOhUpdate]), and the poll loop retries it. Dropping
      // it here left the creator without the joiner's mailboxes.
      return;
    }
    final activePeer = _sendablePeers.firstOrNull;
    if (activePeer == null) return; // retry on the next poll cycle

    final message = ChannelMessage(
      messageId: pending.messageId,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      content: '',
      ohUpdate: Uint8List.fromList(utf8.encode(pending.descriptorsJson)),
    );
    final session = await sessionFuture;
    final payload = await session.encrypt(message, channelId);
    _emitRatchetState(channelId, session);

    // T45/T47d: deposit the announce into EVERY known counterpart OH over garlic (one
    // hop-disjoint route each), with the primary route requesting an R-ACK.
    // The stable message id lets the partner deduplicate the copies.
    final validTargets = targets
        .where((t) => t.ohId.length == GarlicHop.nodeIdLength)
        .toList(growable: false);
    if (validTargets.isEmpty) {
      // The counterpart OH set is (transiently) all-malformed — keep the announce
      // pending and retry on the next poll cycle rather than dropping it and
      // permanently suppressing the channel's healing.
      return;
    }
    try {
      await _depositViaGarlicToAll(
        activePeer,
        validTargets,
        payload,
        channelId,
        messageIdHex: _hexEncode(pending.messageId),
      );
    } catch (e) {
      RpLog.info(
        'RedPandaLightClient: oh_update announce for channel $channelId '
        'failed (will retry on the poll loop): $e',
      );
      return; // budget unchanged — retry on the next poll cycle
    }
    pending.remainingSends--;
    // Remove only THIS announce: a newer one queued while this send was in
    // flight replaces it in the map and must survive.
    if (pending.remainingSends <= 0 &&
        identical(_pendingOhUpdates[channelId], pending)) {
      _pendingOhUpdates.remove(channelId);
    }
  }

  /// Applies a fetched in-band `oh_update` (T21): the partner moved their
  /// mailbox. Authenticity is the ratchet decryption that already happened —
  /// only the partner holds the message keys. Duplicates (the announce is
  /// sent multiple times) are ignored.
  ///
  /// Returns why the update was dropped, or null when it was applied (or a
  /// duplicate) — diagnostics only (T180).
  String? _handleCounterpartOhUpdate(
    String channelId,
    Uint8List ohUpdateBytes,
  ) {
    // T42: the payload is a JSON ARRAY of OHDescriptor maps (breaking change,
    // no pre-T42 compatibility) — the partner's full current mailbox set.
    final List<OHDescriptor> descriptors;
    try {
      final decoded = jsonDecode(utf8.decode(ohUpdateBytes));
      if (decoded is! List) {
        throw const FormatException('oh_update payload is not a JSON array');
      }
      descriptors = [
        for (final entry in decoded)
          OHDescriptor.fromJsonMap(entry as Map<String, dynamic>),
      ];
    } catch (e) {
      RpLog.info(
        'RedPandaLightClient: dropping unreadable oh_update for channel '
        '$channelId: $e',
      );
      return 'unreadable_oh_update';
    }
    if (descriptors.isEmpty) return 'empty_oh_update';
    final changed = _replaceCounterpartOhSet(channelId, descriptors);
    if (!changed) return null; // duplicate announce
    RpLog.info(
      'RedPandaLightClient: channel $channelId counterpart mailbox set updated to '
      '${descriptors.length} OH(s) (in-band oh_update)',
    );
    _emitCounterpartOhUpdate(channelId, descriptors);
    // T161: an announce of our own that waited for a counterpart mailbox can
    // go out now (the poll loop would send it too, one cycle later).
    if (_pendingOhUpdates.containsKey(channelId)) {
      unawaited(
        _sendPendingOhUpdate(channelId).catchError((Object e) {
          RpLog.info(
            'RedPandaLightClient: oh_update announce for $channelId failed '
            '(will retry on the poll loop): $e',
          );
        }),
      );
    }
    // T160: the counterpart exists, but our merge state has no entry of it —
    // the creator's situation after the joiner's first announce. Read the
    // record once so our next publish carries the joiner's entry instead of
    // erasing it (and the read-repair restores ours should the joiner's
    // publish have replaced it). Throttled like any recovery lookup.
    if (_rendezvous.knows(channelId) &&
        !_rendezvous.knowsCounterpartEntry(channelId)) {
      unawaited(_sendRendezvousLookup(channelId));
    }
    return null;
  }

  /// Publishes a counterpart-OH-set change to the app layer (persists the new
  /// deposit fan-out set). Shared by the in-band `oh_update` path and T44
  /// rendezvous recovery.
  void _emitCounterpartOhUpdate(
    String channelId,
    List<OHDescriptor> descriptors,
  ) {
    _stopPairingLookups(channelId); // T160: the counterpart is known
    _emitState(
      CounterpartOhUpdate(channelId: channelId, descriptors: descriptors),
    );
  }

  /// Re-registers [oh] with the same id and keypair to extend its TTL.
  /// On success, updates [OHRegistration.expiresAtMs] and emits an
  /// [OhMailboxUpdate] so the app layer can persist the new expiry.
  /// Returns true if the Full Node confirmed the renewal.
  Future<bool> renewOutboundHandle(OHRegistration oh) async {
    var result = 'error';
    try {
      final ok = await _renewOutboundHandle(oh, (r) => result = r);
      return ok;
    } finally {
      _diagOhEvent(DiagEvt.ohRenew, oh, result);
    }
  }

  /// `oh.renew` / `oh.subscribe` with the handle's identifiers.
  void _diagOhEvent(String name, OHRegistration oh, String result) {
    if (!RpDiag.enabled) return;
    RpDiag.emit(name, {
      DiagKey.result: result,
      DiagKey.host: oh.serverEndpoint,
      DiagKey.mailbox: _hexEncode(oh.ohId),
      DiagKey.channel: oh.channelId,
    });
  }

  Future<bool> _renewOutboundHandle(
    OHRegistration oh,
    void Function(String result) diagResult,
  ) async {
    final activePeer = _peerForHandle(oh, 'renewOutboundHandle()');
    if (activePeer == null) {
      // _peerForHandle already logged the disconnected-host case.
      diagResult('host_not_connected');
      return false;
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 7));
    final request = await _buildRegisterRequest(
      oh.ohId,
      oh.keypair,
      now,
      expiresAt,
    );

    // Await the RegisterOhResponse (151); FIFO-matched so a concurrent
    // registration cannot clobber this renewal's completer.
    final completer = _registerResponses.register();

    activePeer.sendCommand(
      _cmdOutboundRegisterOhReq,
      Uint8List.fromList(request.writeToBuffer()),
    );

    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      _registerResponses.abandon(completer);
      RpLog.info('RedPandaLightClient: renewOutboundHandle() timed out');
      diagResult('no_response');
      return false;
    }

    final response = RegisterOhResponse.fromBuffer(responseBytes);
    if (response.status == Status.RATE_LIMIT) {
      // MS02b: max 5 registrations/min per connection. The renewal timer
      // fires every 5 minutes, so simply failing this cycle is backoff enough.
      RpLog.info('RedPandaLightClient: renewOutboundHandle() rate-limited');
      diagResult('rate_limited');
      return false;
    }
    if (response.status != Status.OK) {
      RpLog.info(
        'RedPandaLightClient: renewOutboundHandle() non-OK status: ${response.status}',
      );
      diagResult('status ${response.status}');
      return false;
    }
    diagResult('ok');

    oh.expiresAtMs = response.expiresAtMs.toInt();
    _emitState(
      OhMailboxUpdate(
        ohId: oh.ohId,
        channelId: oh.channelId,
        lastCursor: oh.lastCursor,
        expiresAtMs: oh.expiresAtMs,
      ),
    );
    // T38: (re-)subscribe for Notify after every confirmed renewal. This
    // covers the renewal timer, reregisterLostHandle (which renews with the
    // same id) and heals subscriptions lost to a partial host reconnect —
    // re-subscribe is idempotent on the node.
    _enqueueSubscribe(oh);
    return true;
  }

  /// Checks all registered OHs and renews those expiring within
  /// [renewalThreshold]. Failures are retried on the next cycle.
  /// Overlapping invocations are skipped.
  Future<void> checkAndRenewExpiringHandles() async {
    if (_renewalInProgress) return;
    _renewalInProgress = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final oh in List.of(_registeredOHs)) {
        if (oh.expiresAtMs - nowMs < renewalThreshold.inMilliseconds) {
          try {
            await renewOutboundHandle(oh);
          } catch (e) {
            RpLog.debug('RedPandaLightClient: OH renewal error: $e');
          }
        }
      }
    } finally {
      _renewalInProgress = false;
    }
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async {
    // Phase telemetry (T27): durations only, logged at the end.
    final fetchStarted = DateTime.now();
    Duration sinceStart() => DateTime.now().difference(fetchStarted);
    var signedAt = Duration.zero;
    var respondedAt = Duration.zero;

    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final now = DateTime.now();

    // Build signing bytes (v2 Ed25519, 0x02 prefix added by OHKeypair.sign):
    // [CMD_BYTE(152) | oh_id | timestamp_ms(8 BE) | nonce | limit(4 BE) | cursor(8 BE)]
    final signingBuffer = BytesBuilder();
    signingBuffer.addByte(_cmdOutboundFetchReq);
    signingBuffer.add(oh.ohId);
    signingBuffer.add(_int64Bytes(now.millisecondsSinceEpoch));
    signingBuffer.add(nonce);
    final limitData = ByteData(4);
    limitData.setInt32(0, 50, Endian.big);
    signingBuffer.add(limitData.buffer.asUint8List());
    signingBuffer.add(_int64Bytes(oh.lastCursor));

    final signature = await oh.keypair.sign(
      Uint8List.fromList(signingBuffer.toBytes()),
    );
    signedAt = sinceStart();

    final request = FetchRequest()
      ..ohId = oh.ohId
      ..limit = 50
      ..timestampMs = _toInt64(now.millisecondsSinceEpoch)
      ..nonce = nonce
      ..signature = signature;

    if (oh.lastCursor != 0) {
      request.cursor = fixnum.Int64(oh.lastCursor);
    }

    // The fetch must go to the node hosting this handle's mailbox.
    final activePeer = _peerForHandle(oh, 'fetchMessages()');

    if (activePeer == null) {
      RpLog.info(
        'RedPandaLightClient: fetchMessages() no active peer available',
      );
      _emitFetchStatus(
        oh,
        false,
        oh.serverEndpoint == null
            ? 'no active peer'
            : 'host node not connected',
      );
      if (oh.serverEndpoint != null) {
        _noteHostUnreachable(oh, 'host node not connected');
      }
      return [];
    }

    // Register completer for command 153 (OUTBOUND_FETCH_RES) before sending
    final completer = Completer<List<int>>();
    _pendingResponses[_cmdOutboundFetchRes] = completer;

    final buffer = request.writeToBuffer();
    RpLog.debug(
      'RedPandaLightClient: fetchMessages() serialized ${buffer.length} bytes',
    );
    activePeer.sendCommand(_cmdOutboundFetchReq, Uint8List.fromList(buffer));

    // Await the response
    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(fetchResponseTimeout);
      activePeer.consecutiveFetchTimeouts = 0;
    } on TimeoutException {
      _pendingResponses.remove(_cmdOutboundFetchRes);
      RpLog.info(
        'RedPandaLightClient: fetchMessages() timed out waiting for response',
      );
      _emitFetchStatus(oh, false, 'timeout');
      if (oh.serverEndpoint != null) {
        _noteHostUnreachable(oh, 'timeout');
      }
      activePeer.consecutiveFetchTimeouts++;
      if (activePeer.consecutiveFetchTimeouts >=
          forceReconnectFetchTimeoutThreshold) {
        // Fire and forget: the caller already waited a full
        // fetchResponseTimeout — the redial must not extend that further.
        unawaited(_forceReconnect(activePeer));
      }
      return [];
    }

    // Parse FetchResponse protobuf
    final response = FetchResponse.fromBuffer(responseBytes);
    respondedAt = sinceStart();
    RpLog.debug(
      'RedPandaLightClient: fetchMessages() status=${response.status} items=${response.items.length}',
    );

    if (response.status != Status.OK) {
      RpLog.info(
        'RedPandaLightClient: fetchMessages() non-OK status: ${response.status}',
      );
      _emitFetchStatus(oh, false, 'status ${response.status}');
      // The host responded — it is alive, whatever it said (T21).
      _fetchFailureCounts.remove(_hexEncode(oh.ohId));
      if (response.status == Status.NOT_FOUND) {
        unawaited(reregisterLostHandle(oh));
      }
      return [];
    }

    // The node answered OK — the mailbox was checked, regardless of whether
    // the items can be decrypted below.
    _emitFetchStatus(oh, true);
    _fetchFailureCounts.remove(_hexEncode(oh.ohId));

    if (response.mailboxOverflow) {
      RpLog.debug(
        'RedPandaLightClient: mailbox overflow detected for OH '
        '${_hexEncode(oh.ohId)} — older messages may have been lost',
      );
    }

    // Update cursor for next fetch
    final previousCursor = oh.lastCursor;
    oh.lastCursor = response.nextCursor.toInt();

    // Group OHs (MS08) are registered under channelId = groupId and have no
    // channel encryption key — their items dispatch through the group state.
    final group = oh.channelId != null ? _groups[oh.channelId] : null;

    // Look up the channel encryption key for this OH
    final encKey = oh.channelId != null
        ? _channelEncryptionKeys[oh.channelId]
        : null;

    if (group == null && encKey == null) {
      RpLog.info(
        'RedPandaLightClient: fetchMessages() no encryption key for channelId=${oh.channelId}',
      );
      for (final item in response.items) {
        _diagFetchItem(oh, item, _DiagItem()..drop('no_key'));
      }
      return [];
    }

    // Decrypt each MailItem. The dedup id and sender timestamp come from the
    // decrypted ChannelMessage (sender-chosen), NOT from the server's
    // MailItem.message_id — the reference node never sets that field.
    // A per-item failure is logged and skipped so one bad item cannot abort
    // the whole batch.
    //
    // Dispatch on the envelope version byte: v4 (MS03b) goes through the
    // channel ratchet, v3 (pre-MS03b transition) through the static K_enc.
    final messages = <DecryptedMessage>[];
    final ackedMessageIds = <Uint8List>[];
    final ackedGroupMessageIds = <Uint8List>[];
    RatchetSession? session;
    var ratchetAdvanced = false;
    var garlicStateChanged = false;
    if (RpDiag.enabled) _diagFetchStats.items += response.items.length;
    for (final item in response.items) {
      // T180: exactly one `fetch.item` per item, emitted once its handler
      // returned (or threw) — see [_DiagItem].
      final diag = _DiagItem();
      try {
        // MS05: a non-empty session tag marks a reverse-garlic reply. It must
        // match an outstanding tag of THIS channel; unknown, already consumed
        // or foreign tags are dropped unread (single-use discipline, master
        // spec MS05, Decision 5 — the server-side dedup only covers 5-minute
        // replays).
        final viaSessionTag = item.sessionTag.isNotEmpty;
        final String? tagHex;
        if (viaSessionTag) {
          tagHex = _hexEncode(item.sessionTag);
          // T44: an outstanding record-lookup ack tag marks this item as a
          // rendezvous `record_lookup` answer (`[1 status][KademliaStore]`),
          // delivered via reverse garlic into our own OH mailbox — never
          // channel-encrypted. Checked ahead of the R-ACK/channel-reply tags.
          final recordLookupChannel = _recordLookupTags.remove(tagHex);
          if (recordLookupChannel != null) {
            _recordLookupTagCreatedAt.remove(tagHex);
            diag.kind = 'lookup-answer';
            await _handleRecordLookupAnswer(
              recordLookupChannel,
              item.payload,
              tagHex: tagHex,
            );
            diag.accept();
            continue;
          }
          // MS06: an outstanding ack tag marks this item as an R-ACK for one
          // of our sends — a plaintext RoutingAck, never channel-encrypted
          // (master spec MS06, Decision 3: correlation via ack_session_tag).
          final ackEntry = _ackTagStore.consume(tagHex);
          if (ackEntry != null) {
            diag
              ..kind = 'r-ack'
              ..msg = ackEntry.messageIdHex;
            diag.finish(
              _handleRoutingAck(ackEntry, item.payload, tagHex: tagHex),
            );
            continue;
          }
          if (group != null) {
            // Groups issue no reply session tags (MS08, Decision 7) — a
            // tagged item that is not an outstanding R-ACK is foreign.
            RpLog.info(
              'RedPandaLightClient: dropping tagged mail item on group OH — '
              'not an outstanding R-ACK',
            );
            diag.drop('tag_not_outstanding_group');
            continue;
          }
          final tagChannel = _sessionTagStore.lookup(tagHex);
          if (tagChannel == null || tagChannel != oh.channelId) {
            RpLog.info(
              'RedPandaLightClient: dropping tagged mail item — session tag '
              '${tagChannel == null ? 'unknown or already consumed' : 'belongs to another channel'}',
            );
            diag.drop(
              tagChannel == null
                  ? 'session_tag_unknown_or_consumed'
                  : 'session_tag_other_channel',
            );
            continue;
          }
        } else {
          tagHex = null;
        }
        if (group != null) {
          diag.kind = 'group';
          await _handleGroupItem(group, item, messages, ackedGroupMessageIds);
          diag.accept();
          continue;
        }
        try {
          final ChannelMessage channelMessage;
          if (item.payload.isNotEmpty &&
              item.payload[0] == MessageCryptoV4.version) {
            session ??= await _ratchetSessions[oh.channelId]!;
            channelMessage = await session.decrypt(item.payload, oh.channelId!);
            ratchetAdvanced = true;
          } else {
            channelMessage = await MessageCryptoV3.decrypt(
              item.payload,
              // Non-null here: group == null implies encKey != null (checked
              // right after the fetch above).
              encKey!,
              oh.channelId!,
            );
          }
          // Consume the tag only for an accepted reply: a transiently
          // undecryptable item is re-delivered on the next fetch and must
          // still find its tag, while a replayed ciphertext fails decryption
          // and can never resurrect an already consumed tag.
          if (tagHex != null) {
            _sessionTagStore.consume(tagHex);
            garlicStateChanged = true;
          }
          // T20: a loopback self-test message coming back — complete the
          // pending test and swallow the item: it never surfaces as a chat
          // message and is never channel-ACKed. Test messages without a
          // pending entry (app restart, eviction, or old deposits replayed
          // by a T40 cursor heal) are swallowed as well.
          final loopback = _pendingLoopbacks.remove(
            _hexEncode(channelMessage.messageId),
          );
          if (loopback != null || channelMessage.content == _loopbackContent) {
            diag
              ..kind = 'loopback'
              ..msg = _hexEncode(channelMessage.messageId);
            if (loopback != null && !loopback.isCompleted) loopback.complete();
            diag.finish(loopback == null ? 'no_pending_loopback' : null);
            continue;
          }
          // T21: an in-band mailbox failover announcement — apply the new
          // counterpart OH and swallow the item (never a chat message).
          if (channelMessage.isOhUpdate) {
            diag
              ..kind = 'oh-update'
              ..msg = _hexEncode(channelMessage.messageId);
            diag.finish(
              _handleCounterpartOhUpdate(
                oh.channelId!,
                channelMessage.ohUpdate!,
              ),
            );
            continue;
          }
          // MS08: a group handshake rides the 1:1 channel — surface it as an
          // event, never as a chat message.
          if (channelMessage.isGroupHandshake) {
            diag
              ..kind = 'group-handshake'
              ..msg = _hexEncode(channelMessage.messageId);
            _emitGroupHandshake(oh.channelId!, channelMessage.groupHandshake!);
            diag.accept();
            continue;
          }
          // MS06: a Channel-ACK confirms the partner received our message —
          // surface it as a status update, never as a chat message.
          if (channelMessage.isChannelAck) {
            diag
              ..kind = 'channel-ack'
              ..msg = _hexEncode(channelMessage.ackMessageId!);
            if (RpDiag.enabled) {
              final ackedHex = _hexEncode(channelMessage.ackMessageId!);
              final sentAt = _diagSentAtMs[ackedHex];
              RpDiag.emit(DiagEvt.ackDelivered, {
                DiagKey.msg: ackedHex,
                DiagKey.channel: oh.channelId,
                DiagKey.latencyMs: sentAt == null
                    ? null
                    : DateTime.now().millisecondsSinceEpoch - sentAt,
                DiagKey.mailbox: _hexEncode(oh.ohId),
              });
            }
            _emitState(
              ChannelAckUpdate(
                channelId: oh.channelId!,
                messageIdHex: _hexEncode(channelMessage.ackMessageId!),
                timestampMs: channelMessage.timestampMs,
              ),
            );
            diag.accept();
            continue;
          }
          diag
            ..kind = 'message'
            ..msg = _hexEncode(channelMessage.messageId);
          if (_storeReplyPath(oh.channelId!, channelMessage.replyPath)) {
            garlicStateChanged = true;
          }
          messages.add(
            DecryptedMessage(
              id: _hexEncode(channelMessage.messageId),
              content: channelMessage.content,
              receivedAtMs: item.receivedAtMs.toInt(),
              senderTimestampMs: channelMessage.timestampMs,
              channelId: oh.channelId,
              viaSessionTag: viaSessionTag,
            ),
          );
          // MS06 (OQ 1): acknowledge on receipt — a Channel-ACK is queued for
          // every accepted regular message and sent after the loop.
          ackedMessageIds.add(Uint8List.fromList(channelMessage.messageId));
          diag.accept();
        } catch (e) {
          RpLog.info('RedPandaLightClient: failed to decrypt mail item: $e');
          diag.drop('processing_failed: $e');
        }
      } finally {
        _diagFetchItem(oh, item, diag);
      }
    }
    if (ratchetAdvanced && session != null) {
      _emitRatchetState(oh.channelId!, session);
    }
    if (garlicStateChanged) {
      _emitGarlicSession(oh.channelId!);
    }

    // MS06 (OQ 1): confirm receipt to the sender — fire-and-forget, a lost
    // ACK only leaves their message at `routed` instead of `delivered`.
    for (final ackedId in ackedMessageIds) {
      unawaited(
        _sendChannelAck(oh.channelId!, ackedId).catchError((Object e) {
          RpLog.info('RedPandaLightClient: failed to send channel ack: $e');
        }),
      );
    }
    // MS08 (Decision 13): group channel-ACKs are v5 broadcasts to all
    // members — every member sees who confirmed.
    if (group != null) {
      for (final ackedId in ackedGroupMessageIds) {
        unawaited(
          _sendGroupAck(group, ackedId).catchError((Object e) {
            RpLog.info('RedPandaLightClient: failed to send group ack: $e');
          }),
        );
      }
    }

    final decryptedAt = sinceStart();

    // Acknowledge the fetched batch so the Full Node can delete it.
    // Fire-and-forget (T27): the ack signs a second request and used to gate
    // delivery — fetched messages reached the app only after it completed.
    // Failures are tolerated: items are re-delivered on the next fetch and
    // deduplicated by message_id in the app layer. The chain serializes
    // overlapping acks, which share the per-command response slot (157).
    if (response.items.isNotEmpty) {
      final ackCursor = response.nextCursor.toInt();
      _ackFetchTail = _ackFetchTail.then(
        (_) => ackFetch(oh, ackCursor)
            .then((ok) {
              if (!ok) {
                RpLog.info(
                  'RedPandaLightClient: background ackFetch reported failure',
                );
              }
            })
            .catchError((Object e) {
              RpLog.info('RedPandaLightClient: background ackFetch failed: $e');
            }),
      );
    }

    if (response.items.isNotEmpty ||
        sinceStart() > const Duration(seconds: 3)) {
      // Phase telemetry (T27): where fetch time goes — durations and item
      // counts only, no identifiers.
      RpLog.info(
        'RedPandaLightClient: fetch phases for ${response.items.length} '
        'item(s): sign ${signedAt.inMilliseconds}ms, response '
        '${(respondedAt - signedAt).inMilliseconds}ms, decrypt+dispatch '
        '${(decryptedAt - respondedAt).inMilliseconds}ms',
      );
    }

    if (response.items.isNotEmpty ||
        response.mailboxOverflow ||
        oh.lastCursor != previousCursor) {
      _emitState(
        OhMailboxUpdate(
          ohId: oh.ohId,
          channelId: oh.channelId,
          lastCursor: oh.lastCursor,
          expiresAtMs: oh.expiresAtMs,
          mailboxOverflow: response.mailboxOverflow,
        ),
      );
    }

    return messages;
  }

  /// Emits the `fetch.item` of one mail item (T180). An item whose handler
  /// threw before reaching a verdict counts as dropped.
  void _diagFetchItem(OHRegistration oh, MailItem item, _DiagItem diag) {
    if (!RpDiag.enabled) return;
    RpDiag.emit(DiagEvt.fetchItem, {
      DiagKey.mailbox: _hexEncode(oh.ohId),
      DiagKey.channel: oh.channelId,
      DiagKey.itemHash: RpDiag.hash16(item.payload),
      DiagKey.kind: diag.kind,
      DiagKey.outcome: diag.outcome ?? 'dropped',
      DiagKey.reason: diag.outcome == null ? 'error' : diag.reason,
      DiagKey.sessionTag: item.sessionTag.isEmpty
          ? null
          : _hexEncode(item.sessionTag),
      DiagKey.recvMs: item.receivedAtMs.toInt(),
      DiagKey.msg: diag.msg,
    });
  }

  /// Parses and keeps an incoming reply path (MS05): the freshest unexpired
  /// RGB per channel replaces any older pending one (each message carries a
  /// fresh RGB, so the newest has the longest remaining lifetime). Returns
  /// true when the pending RGB changed.
  bool _storeReplyPath(String channelId, Uint8List? replyPath) {
    if (replyPath == null || replyPath.isEmpty) return false;
    try {
      final rgb = ReverseGarlicBlock.deserialize(replyPath);
      if (rgb.isExpired()) {
        RpLog.info(
          'RedPandaLightClient: ignoring already expired reply path for '
          'channel $channelId',
        );
        return false;
      }
      _pendingRgbs[channelId] = rgb;
      return true;
    } on FormatException catch (e) {
      RpLog.info(
        'RedPandaLightClient: ignoring unreadable reply path for channel '
        '$channelId: $e',
      );
      return false;
    }
  }

  /// Processes a fetched R-ACK (MS06): scores the involved hops and
  /// forwards the delivery status to the app layer. The arriving R-ACK
  /// proves the forward and return path both worked, so the hops are
  /// credited regardless of the deposit status — the status describes the
  /// recipient's mailbox, not the route.
  ///
  /// Returns why the R-ACK was dropped, or null when it was processed
  /// (diagnostics only, T180).
  String? _handleRoutingAck(
    AckTagEntry entry,
    List<int> payload, {
    String? tagHex,
  }) {
    final RoutingAck ack;
    try {
      ack = RoutingAck.decode(payload);
    } on FormatException catch (e) {
      RpLog.info('RedPandaLightClient: dropping malformed R-ACK: $e');
      return 'malformed_r_ack';
    }
    final latencyMs = (DateTime.now().millisecondsSinceEpoch - entry.sentAtMs)
        .clamp(0, 1 << 31);
    RpDiag.emit(DiagEvt.ackRouted, {
      DiagKey.msg: entry.messageIdHex,
      DiagKey.channel: entry.channelId,
      DiagKey.status: ack.status,
      DiagKey.latencyMs: latencyMs,
      DiagKey.ackTag: tagHex,
    });
    _nodeScorer.recordSuccess(entry.hopNodeIdsHex, latencyMs);
    _emitNodeScores();
    // MS08: the R-ACK of a sealed rotation box confirms its deposit — clear
    // the box from the pending store (Decision 10). Not a message status,
    // so nothing is forwarded to the app's routing-ack stream.
    if (entry.isRotation) {
      final group = _groups[entry.channelId];
      final memberIdHex = entry.memberIdHex;
      if (group != null &&
          memberIdHex != null &&
          ack.status == RoutingAck.statusStored &&
          group.pendingRotations.remove(memberIdHex) != null) {
        _emitGroupState(group);
        RpLog.debug(
          'RedPandaLightClient: rotation box for $memberIdHex confirmed '
          'delivered (${latencyMs}ms)',
        );
      }
      return null;
    }
    _emitState(
      RoutingAckUpdate.ack(
        channelId: entry.channelId,
        messageIdHex: entry.messageIdHex,
        status: ack.status,
        latencyMs: latencyMs,
        memberIdHex: entry.memberIdHex,
      ),
    );
    RpLog.debug(
      'RedPandaLightClient: R-ACK for message ${entry.messageIdHex} '
      '(status ${ack.status}, ${latencyMs}ms)',
    );
    return null;
  }

  /// Sends a Channel-ACK (MS06) for a received message: an empty
  /// ChannelMessage whose ack_message_id references the acknowledged
  /// message, ratchet-encrypted like any other message.
  ///
  /// Only sent when the channel has the partner's OH id (a forward path to
  /// reply over). Without one — a pure reverse-garlic relationship where we
  /// only ever learned a single-use RGB — the ACK is **skipped**: routing it
  /// over the pending RGB would burn the return path the user's real reply
  /// needs, and there is no other destination. The reply the responder does
  /// send is itself the acknowledgement. Skipping also matters for
  /// correctness: encrypting an ACK advances the ratchet, so emitting a
  /// dead-end ACK would renumber the responder's next real message.
  ///
  /// Requests no R-ACK of its own (ACKs stay lightweight; a lost ACK is
  /// repaired by the next one) and never consumes the pending RGB.
  Future<void> _sendChannelAck(String channelId, Uint8List ackedId) async {
    final sessionFuture = _ratchetSessions[channelId];
    if (sessionFuture == null) return;

    // Resolve the destination BEFORE encrypting — a channel-ACK with no
    // forward path must not advance the ratchet or deposit into a void.
    final counterpartOhId = _channelCounterpartOhIds[channelId];
    if (counterpartOhId == null ||
        counterpartOhId.length != GarlicHop.nodeIdLength) {
      return;
    }
    final activePeer = _sendablePeers.firstOrNull;
    if (activePeer == null) {
      RpLog.info(
        'RedPandaLightClient: no active peer to send a channel ack over',
      );
      return;
    }

    final random = Random.secure();
    final ackMessage = ChannelMessage(
      messageId: Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)),
      ),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      content: '',
      ackMessageId: ackedId,
    );
    final session = await sessionFuture;
    final payload = await session.encrypt(ackMessage, channelId);
    _emitRatchetState(channelId, session);

    // T45: the channel ACK travels over garlic like any other deposit — never
    // a direct FlaschenpostPut. In a degenerate net the route falls back to
    // the connected node itself. Lightweight: no R-ACK requested (a lost ACK
    // is repaired by the next one).
    final route = _garlicRoute(
      activePeer,
      ohEndpoint: _channelCounterpartOhEndpoints[channelId],
    );
    if (route == null ||
        payload.length > GarlicBuilder.maxPayloadLength(route.hops.length)) {
      RpLog.info(
        'RedPandaLightClient: dropping channel ack for $channelId — no garlic '
        'route or payload too large',
      );
      return;
    }
    final packet = await GarlicBuilder.build(
      hops: route.hops,
      ohId: counterpartOhId,
      payload: payload,
    );
    activePeer.sendCommand(_cmdFlaschenpostV2, packet);
    // `msg` is the ACKED message: the Channel-ACK's own id is never seen
    // anywhere else.
    _diagSendAttempt(
      kind: 'channel-ack',
      submitVia: activePeer,
      hops: route.hops,
      targetOhId: counterpartOhId,
      packet: packet,
      channelId: channelId,
      messageIdHex: _hexEncode(ackedId),
      targetHost: _channelCounterpartOhEndpoints[channelId],
    );
  }

  // =========================================================================
  // Groups (Frontend MS08)
  // =========================================================================

  /// Registers a group in the network layer. Applied only on the first
  /// registration of a group id — live state is always at least as advanced
  /// as anything persisted (mirrors [addChannelKeys]).
  @override
  void registerGroup(GroupRegistration registration) {
    if (registration.members.length > maxGroupMembers) {
      throw ArgumentError.value(
        registration.members.length,
        'members',
        'groups support at most $maxGroupMembers members (MS08, Decision 2)',
      );
    }
    if (_groups.containsKey(registration.groupId)) return;

    GroupCryptoSession session;
    final stateJson = registration.cryptoStateJson;
    if (stateJson != null) {
      try {
        session = GroupCryptoSession.fromJson(registration.groupId, stateJson);
      } on FormatException catch (e) {
        RpLog.info(
          'RedPandaLightClient: discarding unreadable group crypto state for '
          '${registration.groupId} ($e), starting empty (epoch 0)',
        );
        session = GroupCryptoSession.empty(registration.groupId);
      }
    } else {
      session = GroupCryptoSession.empty(registration.groupId);
    }

    _groups[registration.groupId] = _GroupState(
      groupId: registration.groupId,
      label: registration.label,
      isAdmin: registration.isAdmin,
      myMemberIdHex: registration.myMemberIdHex,
      mySignSeed: Uint8List.fromList(registration.mySignSeed),
      myX25519Priv: Uint8List.fromList(registration.myX25519Priv),
      members: List.of(registration.members),
      session: session,
      pendingItems: [
        for (final item in registration.pendingItems) Uint8List.fromList(item),
      ],
      pendingRotations: {
        for (final entry in registration.pendingRotations.entries)
          entry.key: Uint8List.fromList(entry.value),
      },
    );
  }

  /// Publishes the full mutable state of [group] so the app layer can
  /// persist it (on-device only — the crypto state is key material).
  void _emitGroupState(_GroupState group) {
    _emitState(
      GroupStateUpdate(
        groupId: group.groupId,
        label: group.label,
        keyEpoch: group.session.epoch,
        members: List.unmodifiable(group.members),
        cryptoStateJson: group.session.toJson(),
        pendingItems: [for (final item in group.pendingItems) item.toList()],
        pendingRotations: {
          for (final entry in group.pendingRotations.entries)
            entry.key: entry.value.toList(),
        },
      ),
    );
  }

  @override
  Future<String> sendGroupMessage(
    String groupId,
    String content, {
    String? messageId,
  }) async {
    final group = _groups[groupId];
    if (group == null) {
      throw StateError('sendGroupMessage: group $groupId is not registered');
    }
    if (!group.session.hasEpoch) {
      throw StateError(
        'sendGroupMessage: group $groupId has no key epoch yet '
        '(waiting for the first rotation)',
      );
    }

    final Uint8List messageIdBytes;
    if (messageId != null && messageId.isNotEmpty) {
      messageIdBytes = Uint8List.fromList(_hexDecode(messageId));
    } else {
      messageIdBytes = CryptoUtils.randomBytes(16);
    }
    final messageIdHex = _hexEncode(messageIdBytes);

    // One ciphertext for every recipient (Decision 1: crypto O(1)). A retry
    // re-encrypts with the next chain key — receivers that already got the
    // message deduplicate on the inner message_id, late ones use the
    // skipped-key store.
    final channelMessage = ChannelMessage(
      messageId: messageIdBytes,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      content: content,
    );
    final payload = await group.session.encrypt(
      channelMessage.encode(),
      myMemberIdHex: group.myMemberIdHex,
      mySignSeed: group.mySignSeed,
    );
    // Persist immediately: the sending chain has advanced even if the
    // fan-out below fails partially or completely.
    _emitGroupState(group);

    try {
      await _fanOutToGroup(group, payload, messageIdHex: messageIdHex);
    } on GroupSendException catch (e) {
      // Attach the used message id: the retry MUST reuse it, otherwise the
      // members already reached would see the re-send as a new message.
      throw GroupSendException(e.failedMemberIds, e.message, messageIdHex);
    }
    return messageIdHex;
  }

  /// Delivers [payload] to every other member's group OH (Decision 7:
  /// forward garlic per recipient; with [messageIdHex] an R-ACK is
  /// requested per delivery). Throws [GroupSendException] listing the
  /// members that could not be reached.
  Future<void> _fanOutToGroup(
    _GroupState group,
    Uint8List payload, {
    String? messageIdHex,
  }) async {
    final activePeer = _sendablePeers.firstOrNull;
    if (activePeer == null) {
      throw StateError('group fan-out: no active peer available');
    }

    final failed = <String>[];
    for (final member in group.members) {
      if (member.memberIdHex == group.myMemberIdHex) continue;
      try {
        await _sendToGroupMember(
          group,
          member,
          payload,
          activePeer,
          messageIdHex: messageIdHex,
        );
      } catch (e) {
        RpLog.info(
          'RedPandaLightClient: group send to member '
          '${member.memberIdHex} failed: $e',
        );
        failed.add(member.memberIdHex);
      }
    }
    if (failed.isNotEmpty) {
      throw GroupSendException(failed);
    }
  }

  /// Sends [payload] to one member's group OH: multi-hop garlic when relay
  /// hops are available (with an optional R-ACK request correlated to the
  /// member), otherwise a direct fire-and-forget deposit.
  /// Returns true when the delivery requested an R-ACK.
  Future<bool> _sendToGroupMember(
    _GroupState group,
    GroupMemberInfo member,
    Uint8List payload,
    ActivePeer submitVia, {
    String? messageIdHex,
    bool isRotation = false,
  }) async {
    final ohId = member.ohId;
    if (ohId == null || ohId.length != GarlicHop.nodeIdLength) {
      throw StateError('member ${member.memberIdHex} has no group OH yet');
    }

    final hops = _hopSelector.selectHops(
      count: defaultHopCount,
      excludeAddresses: {
        submitVia.address,
        ..._hostAddresses(member.ohEndpoint),
      },
      excludeNodeIds: {
        ?submitVia.discoveredNodeId,
        ?_hostNodeId(member.ohEndpoint),
      },
    );
    if (hops.isNotEmpty) {
      if (payload.length > GarlicBuilder.maxPayloadLength(hops.length)) {
        // Re-sending the same content can never succeed (fixed 2048 bytes).
        throw DepositException(DepositStatus.badRequest);
      }
      final returnPath = messageIdHex != null
          ? _buildReturnPath(
              group.groupId,
              submitVia,
              messageIdHex: messageIdHex,
              forwardHops: hops,
              payloadLength: payload.length,
              tagged: false,
              memberIdHex: member.memberIdHex,
              isRotation: isRotation,
            )
          : null;
      final packet = await GarlicBuilder.build(
        hops: hops,
        ohId: ohId,
        payload: payload,
        returnPath: returnPath,
      );
      submitVia.sendCommand(_cmdFlaschenpostV2, packet);
      return returnPath != null;
    }

    // Direct fallback, fire-and-forget (mirrors the channel-ACK fallback):
    // a lost deposit surfaces as a missing R-ACK and is re-sent.
    final flaschenpost = FlaschenpostPut()
      ..content = payload
      ..ohId = ohId;
    submitVia.sendCommand(
      _cmdFlaschenpostPut,
      Uint8List.fromList(flaschenpost.writeToBuffer()),
    );
    return false;
  }

  @override
  Future<void> rotateGroupKey(
    String groupId, {
    required List<GroupMemberInfo> members,
    String? label,
  }) async {
    final group = _groups[groupId];
    if (group == null) {
      throw StateError('rotateGroupKey: group $groupId is not registered');
    }
    if (!group.isAdmin) {
      throw StateError('only the group admin can rotate the key (Decision 9)');
    }
    if (members.length > maxGroupMembers) {
      throw ArgumentError.value(
        members.length,
        'members',
        'groups support at most $maxGroupMembers members (MS08, Decision 2)',
      );
    }
    if (!members.any((m) => m.memberIdHex == group.myMemberIdHex)) {
      throw ArgumentError.value(
        members,
        'members',
        'the member list must include the admin itself',
      );
    }

    final newLabel = label ?? group.label;
    final secret = CryptoUtils.randomBytes(CryptoUtils.aesKeyLength);
    final newEpoch = group.session.epoch + 1;
    final control = GroupControl.rotation(
      KeyRotation(
        groupSecret: secret,
        keyEpoch: newEpoch,
        members: members,
        groupName: newLabel,
      ),
    ).encode();
    // Rotations are admin-signed: [4 control_len BE][control][sig 64] with
    // sig = Ed25519(admin) over utf8(group_id) ‖ control. The sealed box
    // alone does not authenticate the sender — any member knows every
    // X25519 public key.
    final signature = await CryptoUtils.sign(group.mySignSeed, [
      ...utf8.encode(groupId),
      ...control,
    ]);
    final signed =
        (BytesBuilder()
              ..add(_uint32beBytes(control.length))
              ..add(control)
              ..add(signature))
            .toBytes();

    // Seal one box per other member while the secret still exists — after
    // installEpoch it is gone and undelivered boxes could not be rebuilt.
    final boxes = <String, Uint8List>{};
    for (final member in members) {
      if (member.memberIdHex == group.myMemberIdHex) continue;
      boxes[member.memberIdHex] = await GroupCryptoSession.seal(
        signed,
        memberX25519Pub: _hexDecode(member.x25519PubHex),
        groupId: groupId,
      );
    }

    await group.session.installEpoch(newEpoch, secret, [
      for (final member in members) member.memberIdHex,
    ]);
    group.members = List.of(members);
    group.label = newLabel;
    group.pendingRotations
      ..clear()
      ..addAll(boxes);
    _emitGroupState(group);

    await _deliverPendingRotations(group);
  }

  @override
  Future<void> retryPendingRotations(String groupId) async {
    final group = _groups[groupId];
    if (group == null) {
      throw StateError(
        'retryPendingRotations: group $groupId is not registered',
      );
    }
    await _deliverPendingRotations(group);
  }

  /// Delivers the pending sealed rotation boxes of [group] with an R-ACK
  /// request per box: a box stays pending until its R-ACK confirms the
  /// deposit (Decision 10 — a member without its rotation is stuck
  /// buffering, so submission alone must not count as delivered). Only
  /// when no R-ACK could be requested (no own OH / no return hops) does a
  /// submission remove the box — better than re-sending forever. Throws
  /// [GroupSendException] when boxes could not even be submitted (retry
  /// via [retryPendingRotations]; the app also retries periodically).
  Future<void> _deliverPendingRotations(_GroupState group) async {
    if (group.pendingRotations.isEmpty) return;
    final activePeer = _sendablePeers.firstOrNull;
    if (activePeer == null) {
      throw GroupSendException(
        group.pendingRotations.keys.toList(),
        'no active peer to deliver rotation boxes over',
      );
    }

    final failed = <String>[];
    var changed = false;
    for (final memberIdHex in List.of(group.pendingRotations.keys)) {
      final member = group.members
          .where((m) => m.memberIdHex == memberIdHex)
          .firstOrNull;
      if (member == null) {
        // No longer a member — the box is obsolete.
        group.pendingRotations.remove(memberIdHex);
        changed = true;
        continue;
      }
      try {
        final acked = await _sendToGroupMember(
          group,
          member,
          group.pendingRotations[memberIdHex]!,
          activePeer,
          messageIdHex: 'rotation',
          isRotation: true,
        );
        if (!acked) {
          // No R-ACK to wait for — treat the submission as delivered.
          group.pendingRotations.remove(memberIdHex);
          changed = true;
        }
      } catch (e) {
        RpLog.info(
          'RedPandaLightClient: rotation box for $memberIdHex '
          'not delivered: $e',
        );
        failed.add(memberIdHex);
      }
    }
    if (changed) {
      _emitGroupState(group);
    }
    if (failed.isNotEmpty) {
      throw GroupSendException(
        failed,
        'rotation boxes still pending for ${failed.length} member(s)',
      );
    }
  }

  /// Sends a group handshake over the existing 1:1 channel [channelId]
  /// (Decision 8), ratchet-encrypted like any other 1:1 message.
  @override
  Future<void> sendGroupHandshake(String channelId, List<int> handshake) async {
    final sessionFuture = _ratchetSessions[channelId];
    if (sessionFuture == null) {
      throw StateError(
        'sendGroupHandshake: channel $channelId has no keys registered',
      );
    }
    final counterpartOhId = _channelCounterpartOhIds[channelId];
    if (counterpartOhId == null ||
        counterpartOhId.length != GarlicHop.nodeIdLength) {
      throw StateError(
        'sendGroupHandshake: channel $channelId has no counterpart OH',
      );
    }
    final activePeer = _sendablePeers.firstOrNull;
    if (activePeer == null) {
      throw StateError('sendGroupHandshake: no active peer available');
    }

    final message = ChannelMessage(
      messageId: CryptoUtils.randomBytes(16),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      content: '',
      groupHandshake: Uint8List.fromList(handshake),
    );
    final session = await sessionFuture;
    final payload = await session.encrypt(message, channelId);
    _emitRatchetState(channelId, session);

    final hops = _selectGarlicHops(channelId, activePeer);
    if (hops.isNotEmpty &&
        payload.length <= GarlicBuilder.maxPayloadLength(hops.length)) {
      final packet = await GarlicBuilder.build(
        hops: hops,
        ohId: counterpartOhId,
        payload: payload,
      );
      activePeer.sendCommand(_cmdFlaschenpostV2, packet);
      return;
    }

    // Direct fallback with want_response for a definite result — the app
    // layer retries the handshake on failure.
    final flaschenpost = FlaschenpostPut()
      ..content = payload
      ..ohId = counterpartOhId
      ..wantResponse = true;
    final completer = _putResponses.register();
    activePeer.sendCommand(
      _cmdFlaschenpostPut,
      Uint8List.fromList(flaschenpost.writeToBuffer()),
    );
    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(depositResponseTimeout);
    } on TimeoutException {
      _putResponses.abandon(completer);
      // Legacy nodes never answer — keep fire-and-forget semantics.
      return;
    }
    final response = FlaschenpostPutResponse.fromBuffer(responseBytes);
    if (response.status != Status.OK) {
      throw DepositException(response.status.name);
    }
  }

  /// Broadcasts a rename to the group (admin only): a GroupControl info
  /// update inside a regular v5 group message.
  @override
  Future<void> sendGroupInfoUpdate(String groupId, String label) async {
    final group = _groups[groupId];
    if (group == null) {
      throw StateError('sendGroupInfoUpdate: group $groupId is not registered');
    }
    if (!group.isAdmin) {
      throw StateError('only the group admin can rename the group');
    }
    if (!group.session.hasEpoch) {
      throw StateError('group $groupId has no key epoch yet');
    }

    group.label = label;
    final control = GroupControl.info(GroupInfoUpdate(name: label)).encode();
    final message = ChannelMessage(
      messageId: CryptoUtils.randomBytes(16),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      content: '',
      groupControl: control,
    );
    final payload = await group.session.encrypt(
      message.encode(),
      myMemberIdHex: group.myMemberIdHex,
      mySignSeed: group.mySignSeed,
    );
    _emitGroupState(group);
    await _fanOutToGroup(group, payload);
  }

  /// Handles one mail item fetched from a group OH: v5 group messages
  /// (chat, channel-ACKs, control broadcasts) and v6 sealed controls
  /// (rotations). Unknown-epoch items are buffered (Decision 10) — the
  /// fetch acknowledgement deletes them server-side, so dropping would
  /// lose them.
  Future<void> _handleGroupItem(
    _GroupState group,
    MailItem item,
    List<DecryptedMessage> messages,
    List<Uint8List> ackedMessageIds,
  ) async {
    final payload = item.payload;
    if (payload.isEmpty) return;

    if (payload[0] == GroupCryptoSession.versionSealedControl) {
      await _handleSealedGroupControl(group, payload);
      return;
    }
    if (payload[0] != GroupCryptoSession.versionGroupMessage) {
      RpLog.info(
        'RedPandaLightClient: dropping group mail item with unknown '
        'version ${payload[0]}',
      );
      return;
    }

    try {
      final result = await group.session.decrypt(payload);
      final channelMessage = ChannelMessage.decode(result.plaintext);

      if (channelMessage.isChannelAck) {
        _emitState(
          ChannelAckUpdate(
            channelId: group.groupId,
            messageIdHex: _hexEncode(channelMessage.ackMessageId!),
            timestampMs: channelMessage.timestampMs,
            memberIdHex: result.senderMemberIdHex,
          ),
        );
        _emitGroupState(group);
        return;
      }
      if (channelMessage.isGroupControl) {
        _applyGroupControlMessage(
          group,
          result.senderMemberIdHex,
          channelMessage.groupControl!,
        );
        _emitGroupState(group);
        return;
      }

      messages.add(
        DecryptedMessage(
          id: _hexEncode(channelMessage.messageId),
          content: channelMessage.content,
          receivedAtMs: item.receivedAtMs.toInt(),
          senderTimestampMs: channelMessage.timestampMs,
          channelId: group.groupId,
          senderMemberIdHex: result.senderMemberIdHex,
        ),
      );
      ackedMessageIds.add(Uint8List.fromList(channelMessage.messageId));
      _emitGroupState(group);
    } on GroupUnknownEpochException catch (e) {
      if (group.pendingItems.length < maxPendingGroupItems) {
        group.pendingItems.add(Uint8List.fromList(payload));
        _emitGroupState(group);
        RpLog.info(
          'RedPandaLightClient: buffering group item for unknown '
          'epoch ${e.epoch} (${group.pendingItems.length} buffered)',
        );
      } else {
        RpLog.info(
          'RedPandaLightClient: pending-item buffer full, dropping group '
          'item for epoch ${e.epoch}',
        );
      }
    } on GroupCryptoException catch (e) {
      RpLog.info('RedPandaLightClient: dropping group item: $e');
    } on GcmAuthenticationException catch (e) {
      RpLog.info('RedPandaLightClient: dropping group item: $e');
    } on FormatException catch (e) {
      RpLog.info('RedPandaLightClient: dropping malformed group item: $e');
    }
  }

  /// Applies a GroupControl that arrived as a regular group message
  /// (currently only the rename); mutations are only accepted from the
  /// pinned admin (Decision 9).
  void _applyGroupControlMessage(
    _GroupState group,
    String senderMemberIdHex,
    Uint8List controlBytes,
  ) {
    final GroupControl control;
    try {
      control = GroupControl.decode(controlBytes);
    } on FormatException catch (e) {
      RpLog.info('RedPandaLightClient: dropping malformed group control: $e');
      return;
    }
    final info = control.infoUpdate;
    if (info == null) {
      // Rotations never travel as group messages (they need the new epoch
      // to be readable before it is installed) — sealed v6 only.
      RpLog.info(
        'RedPandaLightClient: ignoring non-info group control in a v5 message',
      );
      return;
    }
    final admin = group.members
        .where((m) => m.role == GroupMemberInfo.roleAdmin)
        .firstOrNull;
    if (admin == null || admin.memberIdHex != senderMemberIdHex) {
      RpLog.info(
        'RedPandaLightClient: rejecting group rename from non-admin '
        '$senderMemberIdHex',
      );
      return;
    }
    group.label = info.name;
  }

  /// Verifies and applies a sealed rotation (envelope v6): unseal with the
  /// own X25519 key, check the admin signature against the pinned admin,
  /// enforce the single-admin invariant, install the epoch and drain the
  /// pending-item buffer (Decision 10).
  Future<void> _handleSealedGroupControl(
    _GroupState group,
    List<int> payload,
  ) async {
    try {
      final signed = await GroupCryptoSession.unseal(
        payload,
        myX25519Priv: group.myX25519Priv,
        groupId: group.groupId,
      );
      if (signed.length < 4 + CryptoUtils.signatureLength) {
        throw const FormatException('sealed control: truncated');
      }
      final controlLength = ByteData.sublistView(signed, 0, 4).getUint32(0);
      if (4 + controlLength + CryptoUtils.signatureLength != signed.length) {
        throw const FormatException('sealed control: bad framing');
      }
      final control = Uint8List.sublistView(signed, 4, 4 + controlLength);
      final signature = Uint8List.sublistView(signed, 4 + controlLength);

      final admin = group.members
          .where((m) => m.role == GroupMemberInfo.roleAdmin)
          .firstOrNull;
      if (admin == null) {
        RpLog.info(
          'RedPandaLightClient: dropping sealed control for '
          '${group.groupId} — no pinned admin',
        );
        return;
      }
      final signatureValid = await CryptoUtils.verify(
        _hexDecode(admin.memberIdHex),
        [...utf8.encode(group.groupId), ...control],
        signature,
      );
      if (!signatureValid) {
        RpLog.info(
          'RedPandaLightClient: dropping sealed control with invalid '
          'admin signature for ${group.groupId}',
        );
        return;
      }

      final rotation = GroupControl.decode(control).keyRotation;
      if (rotation == null) return;
      final incomingAdmin = rotation.members
          .where((m) => m.role == GroupMemberInfo.roleAdmin)
          .firstOrNull;
      if (incomingAdmin == null ||
          incomingAdmin.memberIdHex != admin.memberIdHex) {
        // Single-admin invariant (Decision 9): a rotation may not move the
        // admin role.
        RpLog.info(
          'RedPandaLightClient: rejecting rotation that changes the admin '
          'of ${group.groupId}',
        );
        return;
      }

      final installed = await group.session.installEpoch(
        rotation.keyEpoch,
        rotation.groupSecret,
        [for (final member in rotation.members) member.memberIdHex],
      );
      if (!installed) {
        RpLog.info(
          'RedPandaLightClient: ignoring stale rotation to epoch '
          '${rotation.keyEpoch} (current: ${group.session.epoch})',
        );
        return;
      }
      group.members = List.of(rotation.members);
      if (rotation.groupName.isNotEmpty) {
        group.label = rotation.groupName;
      }
      RpLog.info(
        'RedPandaLightClient: installed epoch ${rotation.keyEpoch} for '
        'group ${group.groupId} (${rotation.members.length} members)',
      );
      _emitGroupState(group);
      await _drainGroupBuffer(group);
    } on GcmAuthenticationException catch (e) {
      RpLog.info('RedPandaLightClient: dropping sealed control: $e');
    } on FormatException catch (e) {
      RpLog.info('RedPandaLightClient: dropping sealed control: $e');
    }
  }

  /// Retries the buffered unknown-epoch items after a rotation installed
  /// new keys (Decision 10). Still-unknown epochs go back into the buffer.
  Future<void> _drainGroupBuffer(_GroupState group) async {
    if (group.pendingItems.isEmpty) return;
    final items = List.of(group.pendingItems);
    group.pendingItems.clear();
    final ackedMessageIds = <Uint8List>[];

    for (final payload in items) {
      try {
        final result = await group.session.decrypt(payload);
        final channelMessage = ChannelMessage.decode(result.plaintext);
        if (channelMessage.isChannelAck) {
          _emitState(
            ChannelAckUpdate(
              channelId: group.groupId,
              messageIdHex: _hexEncode(channelMessage.ackMessageId!),
              timestampMs: channelMessage.timestampMs,
              memberIdHex: result.senderMemberIdHex,
            ),
          );
          continue;
        }
        if (channelMessage.isGroupControl) {
          _applyGroupControlMessage(
            group,
            result.senderMemberIdHex,
            channelMessage.groupControl!,
          );
          continue;
        }
        if (!_incomingMessageController.isClosed) {
          // The original server receive time was not buffered; the drain
          // time is close enough (ordering uses the sender timestamp).
          _incomingMessageController.add(
            DecryptedMessage(
              id: _hexEncode(channelMessage.messageId),
              content: channelMessage.content,
              receivedAtMs: DateTime.now().millisecondsSinceEpoch,
              senderTimestampMs: channelMessage.timestampMs,
              channelId: group.groupId,
              senderMemberIdHex: result.senderMemberIdHex,
            ),
          );
        }
        ackedMessageIds.add(Uint8List.fromList(channelMessage.messageId));
      } on GroupUnknownEpochException {
        group.pendingItems.add(payload);
      } catch (e) {
        RpLog.info(
          'RedPandaLightClient: dropping buffered group item on drain: $e',
        );
      }
    }
    _emitGroupState(group);

    for (final ackedId in ackedMessageIds) {
      unawaited(
        _sendGroupAck(group, ackedId).catchError((Object e) {
          RpLog.info('RedPandaLightClient: failed to send group ack: $e');
        }),
      );
    }
  }

  /// Confirms receipt of a group message to all members (Decision 13):
  /// a regular v5 message carrying only ack_message_id, fire-and-forget
  /// and without an own R-ACK request (acks stay lightweight, as in 1:1).
  Future<void> _sendGroupAck(_GroupState group, Uint8List ackedId) async {
    if (!group.session.hasEpoch) return;
    final ackMessage = ChannelMessage(
      messageId: CryptoUtils.randomBytes(16),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      content: '',
      ackMessageId: ackedId,
    );
    final payload = await group.session.encrypt(
      ackMessage.encode(),
      myMemberIdHex: group.myMemberIdHex,
      mySignSeed: group.mySignSeed,
    );
    _emitGroupState(group);
    try {
      await _fanOutToGroup(group, payload);
    } on GroupSendException catch (e) {
      // A lost ack only leaves the sender's message at `routed`.
      RpLog.info('RedPandaLightClient: group ack fan-out incomplete: $e');
    }
  }

  /// Decodes and surfaces a group handshake fetched from a 1:1 channel.
  void _emitGroupHandshake(String channelId, Uint8List handshakeBytes) {
    final GroupHandshake handshake;
    try {
      handshake = GroupHandshake.decode(handshakeBytes);
    } on FormatException catch (e) {
      RpLog.info('RedPandaLightClient: dropping malformed group handshake: $e');
      return;
    }
    if (handshake.isProposal) {
      _emitState(
        GroupHandshakeEvent(
          channelId: channelId,
          isProposal: true,
          groupIdHex: handshake.proposalGroupIdHex!,
          groupName: handshake.proposalGroupName,
          adminMemberIdHex: handshake.proposalAdminMemberIdHex,
        ),
      );
    } else {
      _emitState(
        GroupHandshakeEvent(
          channelId: channelId,
          isProposal: false,
          groupIdHex: handshake.acceptGroupIdHex!,
          memberIdHex: handshake.acceptMemberIdHex,
          x25519PubHex: handshake.acceptX25519PubHex,
          ohId: handshake.acceptOhId,
          ohEndpoint: handshake.acceptOhEndpoint,
        ),
      );
    }
  }

  static Uint8List _uint32beBytes(int value) {
    final data = ByteData(4)..setUint32(0, value);
    return data.buffer.asUint8List();
  }

  /// Sends an AckFetchRequest for [oh] confirming receipt of all mail items
  /// up to and including [ackedSequenceId]; the Full Node deletes them.
  /// Returns true if the node confirmed the acknowledgement.
  Future<bool> ackFetch(OHRegistration oh, int ackedSequenceId) async {
    final activePeer = _peerForHandle(oh, 'ackFetch()');
    if (activePeer == null) {
      RpLog.info('RedPandaLightClient: ackFetch() no active peer available');
      return false;
    }

    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final now = DateTime.now();

    // Signing bytes (v2 Ed25519, 0x02 prefix added by OHKeypair.sign):
    // [CMD_BYTE(156) | oh_id | acked_sequence_id(8 BE) | timestamp_ms(8 BE) | nonce]
    final signingBuffer = BytesBuilder();
    signingBuffer.addByte(_cmdOutboundAckFetchReq);
    signingBuffer.add(oh.ohId);
    signingBuffer.add(_int64Bytes(ackedSequenceId));
    signingBuffer.add(_int64Bytes(now.millisecondsSinceEpoch));
    signingBuffer.add(nonce);

    final signature = await oh.keypair.sign(
      Uint8List.fromList(signingBuffer.toBytes()),
    );

    final request = AckFetchRequest()
      ..ohId = oh.ohId
      ..ackedSequenceId = fixnum.Int64(ackedSequenceId)
      ..timestampMs = _toInt64(now.millisecondsSinceEpoch)
      ..nonce = nonce
      ..signature = signature;

    // Register completer for command 157 (OUTBOUND_ACK_FETCH_RES)
    final completer = Completer<List<int>>();
    _pendingResponses[_cmdOutboundAckFetchRes] = completer;

    activePeer.sendCommand(
      _cmdOutboundAckFetchReq,
      Uint8List.fromList(request.writeToBuffer()),
    );

    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      _pendingResponses.remove(_cmdOutboundAckFetchRes);
      RpLog.info(
        'RedPandaLightClient: ackFetch() timed out waiting for response',
      );
      return false;
    }

    final response = AckFetchResponse.fromBuffer(responseBytes);
    if (response.status != Status.OK) {
      RpLog.info(
        'RedPandaLightClient: ackFetch() non-OK status: ${response.status}',
      );
      return false;
    }
    return true;
  }

  static String _hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Decodes a hex string into bytes.
  static List<int> _hexDecode(String hex) {
    if (hex.length.isOdd) {
      throw FormatException('odd-length hex string: ${hex.length}');
    }
    final out = List<int>.filled(hex.length ~/ 2, 0);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  void _startPolling() {
    if (!_pollingEnabled) {
      _pollingEnabled = true;
      // Already connected when the first handle appears (e.g. restore on
      // app start finishing after the connection is up): check the mailbox
      // right away instead of waiting a full idle interval. Not yet
      // connected: the connect edge in _updateStatus pulls the first poll
      // forward once the connection is up.
      final connected = _sendablePeers.isNotEmpty;
      _schedulePoll(connected ? const Duration(seconds: 2) : _pollInterval);
    }
    _renewalTimer ??= Timer.periodic(renewalCheckInterval, (_) {
      checkAndRenewExpiringHandles();
      _republishDueRendezvousRecords();
    });
  }

  /// T44: republishes each channel's rendezvous record every
  /// [_rendezvousRepublishInterval] (records rotate under the UTC-day key and
  /// expire after 48 h; the short interval also heals a dropped best-effort
  /// store). A change-driven publish (`_publishRendezvousIfChanged`) refreshes
  /// the timestamp too, so this covers idle channels and never-published ones.
  void _republishDueRendezvousRecords() {
    final now = DateTime.now();
    // Evict record-lookup ack tags whose answer never arrived (a lost packet).
    _recordLookupTagCreatedAt.removeWhere((tagHex, created) {
      if (now.difference(created) <= _recordLookupTtl) return false;
      _recordLookupTags.remove(tagHex);
      return true;
    });
    // No relay nodes (e.g. an isolated single-node network) → rendezvous
    // publishing is inapplicable; stay dormant so it never competes with the
    // mailbox register/fetch path.
    if (!_hasRendezvousRelays) return;
    // Self-throttle the sweep: it is driven by both the fast poll cycle and the
    // renewal timer, but rendezvous republishing must never compete with the
    // critical mailbox register/fetch path (a busy sweep during the fragile
    // pairing window delayed OH confirmation and dropped the first deposit).
    if (_lastRepublishSweep != null &&
        now.difference(_lastRepublishSweep!) < _rendezvousSweepInterval) {
      return;
    }
    _lastRepublishSweep = now;
    for (final channelId in _rendezvous.channels.toList()) {
      // Re-derive the own-OH projection first: after a respawn or an app
      // restart the handles came back through restoreOutboundHandle, which is
      // not a publish trigger, and buildSignedStore returns null for an empty
      // own-OH list — the sweep would publish nothing at all. Cheap and
      // idempotent; it does not itself trigger a publish.
      refreshRendezvousOwnOhs(channelId);
      final last = _lastRendezvousPublish[channelId];
      // Never-published channels (hops not yet ready at registration) retry
      // every call; published ones refresh at [_rendezvousRepublishInterval].
      // record_store is a cheap, best-effort single packet with no ack, so a
      // dropped store (e.g. a transient "no route" before the graph settles)
      // is only recovered by republishing — the interval is short enough to
      // heal such losses well within the 48 h record TTL.
      if (last != null && now.difference(last) < _rendezvousRepublishInterval) {
        continue;
      }
      // _publishRendezvous stamps _lastRendezvousPublish only on a real send.
      unawaited(_publishRendezvous(channelId));
    }
  }

  /// How often an unchanged rendezvous record is refreshed into the DHT.
  /// record_store is fire-and-forget AND _publishRendezvous stamps the publish
  /// on send (not on arrival), so this periodic refresh is the only heal for a
  /// store dropped in transit — the interval IS the worst-case blind window
  /// after such a loss. Stretching it to 30 min for cadence privacy (T47b) was
  /// tried 2026-07-22 and reverted: the t44 heal E2E showed a dropped first
  /// store then leaves the channel undiscoverable for the whole window. The
  /// observability trade-off (record-holding nodes see an opaque per-channel
  /// publish cadence) is documented in the spec and accepted.
  static const Duration _rendezvousRepublishInterval = Duration(minutes: 3);

  /// Minimum spacing between full republish sweeps, independent of how often
  /// the poll cycle / renewal timer call in.
  static const Duration _rendezvousSweepInterval = Duration(seconds: 30);
  DateTime? _lastRepublishSweep;

  final Map<String, DateTime> _lastRendezvousPublish = {};

  /// Current poll cadence: fast while a conversation is active, slow when
  /// idle (T27).
  Duration get _pollInterval =>
      DateTime.now().difference(_lastChatActivity) <= pollActivityWindow
      ? activePollInterval
      : idlePollInterval;

  /// (Re-)schedules the next regular poll cycle in [delay]. Cycles run at a
  /// fixed rate: each cycle's duration is subtracted from the then-current
  /// [_pollInterval] (never below [minPollGap]), so slow cycles do not
  /// stretch the effective cadence.
  void _schedulePoll(Duration delay) {
    if (!_pollingEnabled) return;
    _nextPollAt = DateTime.now().add(delay);
    _armPollTimer();
  }

  /// T167: the poll-start budget at [now] (see [_pollCreditMicros]).
  int _pollCredit(int nowMicros) {
    final at = _pollCreditAtMicros;
    final cap = pollBurst * pollStartRefill.inMicroseconds;
    if (at == null) return cap;
    return min(cap, _pollCreditMicros + (nowMicros - at));
  }

  /// T167: how long the next cycle start must wait for budget. Zero while
  /// budget is left: up to [pollBurst] cycles can run back to back, so
  /// Notifies that cluster (a message, its ACKs, a second message) are each
  /// fetched at once. Once the budget is spent, at most one cycle starts per
  /// [pollStartRefill]: whatever drives the poll (a stream of Notifies, a
  /// stream of follow-ups), it cannot spin, and over any window T at most
  /// [pollBurst] + T / [pollStartRefill] cycles start. The regular cadence
  /// (full cycles ≥ [minPollGap] apart) never runs short of budget.
  Duration _pollStartDelay(int nowMicros) {
    final missing = pollStartRefill.inMicroseconds - _pollCredit(nowMicros);
    return missing <= 0 ? Duration.zero : Duration(microseconds: missing);
  }

  void _spendPollStart() {
    final now = _pollClock.elapsedMicroseconds;
    // Never below zero: a timer that fired a hair early must not carry debt.
    _pollCreditMicros = max(
      0,
      _pollCredit(now) - pollStartRefill.inMicroseconds,
    );
    _pollCreditAtMicros = now;
  }

  /// Arms the one poll timer for whichever comes first: the regular cycle at
  /// [_nextPollAt] or, with notified OHs pending, a follow-up fetch (T167).
  /// Both respect [_pollStartDelay]. If the regular cycle is due no later
  /// than the follow-up, it runs instead (it fetches every OH anyway).
  void _armPollTimer() {
    if (!_pollingEnabled) return;
    final now = DateTime.now();
    final nowMicros = _pollClock.elapsedMicroseconds;
    final earliest = now.add(_pollStartDelay(nowMicros));
    var due = _nextPollAt ?? now;
    var followUp = false;
    if (_pollFollowUpOhs.isNotEmpty) {
      final coalesceLeft =
          _pollFollowUpSinceMicros +
          notifyCoalesceDelay.inMicroseconds -
          nowMicros;
      final coalesced = now.add(Duration(microseconds: max(0, coalesceLeft)));
      final followUpAt = coalesced.isAfter(earliest) ? coalesced : earliest;
      if (followUpAt.isBefore(due)) {
        due = followUpAt;
        followUp = true;
      }
    }
    if (due.isBefore(earliest)) due = earliest;
    _pollingTimer?.cancel();
    _pollingTimer = Timer(
      due.difference(now),
      followUp ? _runFollowUpTick : _runRegularTick,
    );
  }

  /// Timer body of a regular cycle: runs it and schedules the next one.
  Future<void> _runRegularTick() async {
    // A cycle is still running (an outside _schedulePoll re-armed the timer
    // mid-cycle); its end re-arms the timer.
    if (_pollInProgress) return;
    final started = DateTime.now();
    _spendPollStart();
    _fullCycleInProgress = true;
    try {
      await _runPollCycle();
    } catch (e) {
      // Never let one bad cycle kill the loop — without this, an
      // exception escaping the cycle would end polling until restart.
      RpLog.info('RedPandaLightClient: poll cycle failed: $e');
    } finally {
      _fullCycleInProgress = false;
      final now = DateTime.now();
      final elapsed = now.difference(started);
      final interval = _pollInterval;
      _schedulePoll(
        elapsed >= interval - minPollGap ? minPollGap : interval - elapsed,
      );
    }
  }

  /// Timer body of a follow-up fetch (T167). Leaves [_nextPollAt] alone.
  Future<void> _runFollowUpTick() async {
    if (_pollInProgress) return;
    _spendPollStart();
    try {
      await _runFollowUpFetch();
    } catch (e) {
      RpLog.info('RedPandaLightClient: poll follow-up failed: $e');
    } finally {
      _armPollTimer();
    }
  }

  /// T167: fetches only the OHs whose Notify the previous cycle missed —
  /// none of the full cycle's maintenance (republish, oh_update resends, ACK
  /// expiry), which stays on the regular cadence.
  Future<void> _runFollowUpFetch() async {
    if (_pollInProgress) return;
    _pollInProgress = true;
    final started = DateTime.now();
    final targets = _registeredOHs
        .where((oh) => _pollFollowUpOhs.contains(_hexEncode(oh.ohId)))
        .toList();
    _pollFollowUpOhs.clear();
    _startCycleFetchPhases(targets);
    var fetched = 0;
    try {
      for (final oh in targets) {
        fetched += await _fetchForCycle(oh, followUp: true);
      }
    } finally {
      _pollInProgress = false;
      _cycleFetchPhase.clear();
      RpLog.info(
        'RedPandaLightClient: poll follow-up fetched $fetched message(s) '
        'from ${targets.length} notified OH(s) in '
        '${DateTime.now().difference(started).inMilliseconds}ms',
      );
    }
  }

  void _startCycleFetchPhases(List<OHRegistration> ohs) {
    _cycleFetchPhase
      ..clear()
      ..addEntries(
        ohs.map(
          (oh) => MapEntry(_hexEncode(oh.ohId), _CycleFetchPhase.pending),
        ),
      );
  }

  /// One OH's fetch inside a cycle: tracks its [_CycleFetchPhase], hands the
  /// messages to the app and returns how many there were. Never throws.
  Future<int> _fetchForCycle(OHRegistration oh, {bool followUp = false}) async {
    final ohHex = _hexEncode(oh.ohId);
    _cycleFetchPhase[ohHex] = _CycleFetchPhase.inFlight;
    try {
      final missedAt = _missedNotifyAt.remove(ohHex);
      final messages = await fetchMessages(oh);
      if (missedAt != null) {
        RpLog.debug(
          'RedPandaLightClient: Notify wait: fetched '
          '${messages.length} item(s) '
          '${DateTime.now().difference(missedAt).inMilliseconds}ms after '
          'a Notify that arrived mid-cycle',
        );
      }
      if (messages.isNotEmpty) {
        // The partner is active — keep the fast cadence going (T27).
        _lastChatActivity = DateTime.now();
        // T167 diagnostics: ties fetched mail to its OH (and Notify).
        RpLog.debug(
          'RedPandaLightClient: Poll fetch: ${messages.length} item(s) for '
          'OH $ohHex (${followUp ? 'follow-up' : 'full cycle'})',
        );
      }
      for (final msg in messages) {
        _incomingMessageController.add(msg);
      }
      return messages.length;
    } catch (e) {
      RpLog.info('RedPandaLightClient: Polling error: $e');
      _emitFetchStatus(oh, false, 'error: $e');
      return 0;
    } finally {
      _cycleFetchPhase[ohHex] = _CycleFetchPhase.done;
    }
  }

  /// Records chat activity (own send / fresh registration) so the poll loop
  /// switches to [activePollInterval], and pulls an already-scheduled slow
  /// poll forward so the faster cadence takes effect immediately. A cycle
  /// that is currently running reschedules itself with the fresh interval
  /// when it completes.
  void _notePollActivity() {
    _lastChatActivity = DateTime.now();
    final next = _nextPollAt;
    if (_pollingEnabled &&
        !_fullCycleInProgress &&
        (next == null ||
            next.isAfter(DateTime.now().add(activePollInterval)))) {
      _schedulePoll(activePollInterval);
    }
  }

  Future<void> _runPollCycle() async {
    if (_pollInProgress) return; // previous cycle still running
    _pollInProgress = true;
    final started = DateTime.now();
    var fetched = 0;
    // T167: OHs with a missed Notify go first; this cycle covers them, so
    // the pending follow-up is dropped.
    final snapshot = [
      ..._registeredOHs.where(
        (oh) => _pollFollowUpOhs.contains(_hexEncode(oh.ohId)),
      ),
      ..._registeredOHs.where(
        (oh) => !_pollFollowUpOhs.contains(_hexEncode(oh.ohId)),
      ),
    ];
    _pollFollowUpOhs.clear();
    _startCycleFetchPhases(snapshot);
    try {
      for (final oh in snapshot) {
        fetched += await _fetchForCycle(oh);
      }
      // T44: (re)publish rendezvous records that are due or that never got a
      // publish through (e.g. no garlic hops were known at registration time).
      _republishDueRendezvousRecords();
      // T42/T111: keep every known channel topped up to [ohRedundancy] own
      // mailboxes. This used to be driven from `chat_screen.build`, so the
      // invariant only held while a chat was on screen and a retry needed a
      // widget rebuild. The worker owns its own mailbox set, and this is the
      // one place where the preconditions (verified peers with a discovered
      // node id) actually appear.
      //
      // NOT awaited, like [checkAndRenewExpiringHandles]: a top-up performs
      // real OH registrations, and the cycle's completion gates when the next
      // fetch loop may run (and `_notePollActivity`'s pull-forward). Blocking
      // delivery latency on background maintenance would work against the
      // ≤10 s goal. [sweepOhRedundancy] guards its own re-entry.
      unawaited(
        sweepOhRedundancy().catchError((Object e) {
          RpLog.info('RedPandaLightClient: OH redundancy sweep failed: $e');
        }),
      );
      // T21: re-send pending failover announcements until their send
      // budget is used up.
      for (final channelId in List.of(_pendingOhUpdates.keys)) {
        try {
          await _sendPendingOhUpdate(channelId);
        } catch (e) {
          RpLog.info(
            'RedPandaLightClient: oh_update announce retry failed: $e',
          );
        }
      }
      // MS05: prune session tags whose RGB expired long ago (48h).
      for (final channelId in _sessionTagStore.cleanup()) {
        _emitGarlicSession(channelId);
      }
      // MS06: sends whose R-ACK never arrived — score the involved hops
      // down and tell the app layer so it can re-send over fresh hops.
      _reapExpiredAcks();
    } finally {
      _pollInProgress = false;
      _cycleFetchPhase.clear();
      // Cadence telemetry (T27): counts and durations only — no handle or
      // channel identifiers, safe for field logging.
      RpLog.info(
        'RedPandaLightClient: poll cycle fetched $fetched message(s) from '
        '${_registeredOHs.length} OH(s) in '
        '${DateTime.now().difference(started).inMilliseconds}ms '
        '(interval ${_pollInterval.inSeconds}s)',
      );
      _diagMaybeFlushFetchSummary();
    }
  }

  /// MS06: sends whose R-ACK never arrived within [ackTimeout] — score the
  /// involved hops down and tell the app layer so it can re-send over fresh
  /// hops. Runs once per poll cycle; [nowMs] only for tests.
  void _reapExpiredAcks([int? nowMs]) {
    final expired = _ackTagStore.takeExpired(ackTimeout, nowMs: nowMs);
    for (final entry in expired) {
      _nodeScorer.recordFailure(entry.hopNodeIdsHex);
      RpDiag.emit(DiagEvt.ackTimeout, {
        DiagKey.msg: entry.messageIdHex,
        DiagKey.channel: entry.channelId,
        DiagKey.waitedMs:
            (nowMs ?? DateTime.now().millisecondsSinceEpoch) - entry.sentAtMs,
        DiagKey.hops: entry.hopNodeIdsHex,
      });
      // MS08: an unconfirmed rotation box simply stays pending — the
      // periodic retry re-sends it; no message status to update.
      if (entry.isRotation) continue;
      _emitState(
        RoutingAckUpdate.timeout(
          channelId: entry.channelId,
          messageIdHex: entry.messageIdHex,
          memberIdHex: entry.memberIdHex,
        ),
      );
      RpLog.info(
        'RedPandaLightClient: no R-ACK for message '
        '${entry.messageIdHex} within ${ackTimeout.inSeconds}s',
      );
    }
    if (expired.isNotEmpty) {
      _emitNodeScores();
    }
  }

  /// Runs the R-ACK expiry as of [nowMs] (tests only — the poll cycle runs
  /// it with the real clock).
  @visibleForTesting
  void reapExpiredAcksForTesting(int nowMs) => _reapExpiredAcks(nowMs);

  /// Converts an int to 8-byte big-endian representation.
  static Uint8List _int64Bytes(int value) {
    final data = ByteData(8);
    data.setInt64(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  /// Converts an int to fixnum Int64 for protobuf.
  static fixnum.Int64 _toInt64(int value) {
    return fixnum.Int64(value);
  }

  /// DEBUG ONLY: Get current peer stats
  List<PeerStats> getDebugPeerStats() {
    return _peerRepository.getBestPeers(100);
  }

  /// Asks every encrypted connection for a fresh peer list. Peers are
  /// normally requested once per connection; this speeds up garlic hop
  /// candidate discovery (MS04) when the network is still settling.
  void requestPeerLists() {
    for (final peer in _peers.values.where((p) => p.isEncryptionActive)) {
      peer.requestPeerList();
    }
  }
}

/// Mutable in-memory state of one registered group (Frontend MS08): the
/// member list, the own group identity, the crypto session and the
/// buffered/undelivered payloads. Snapshotted into [GroupStateUpdate]s for
/// on-device persistence.
class _GroupState {
  final String groupId;
  String label;
  final bool isAdmin;
  final String myMemberIdHex;
  final Uint8List mySignSeed;
  final Uint8List myX25519Priv;
  List<GroupMemberInfo> members;
  final GroupCryptoSession session;

  /// Buffered unknown-epoch items (Decision 10).
  final List<Uint8List> pendingItems;

  /// Sealed rotation boxes not yet delivered, member id hex → payload.
  final Map<String, Uint8List> pendingRotations;

  _GroupState({
    required this.groupId,
    required this.label,
    required this.isAdmin,
    required this.myMemberIdHex,
    required this.mySignSeed,
    required this.myX25519Priv,
    required this.members,
    required this.session,
    required this.pendingItems,
    required this.pendingRotations,
  });
}

/// A single counterpart OH mailbox in the deposit fan-out set (T42): the id a
/// FlaschenpostPut is addressed to, plus the host endpoint (used for garlic
/// hop exclusion and status display). The auth public key is not needed to
/// deposit, so it is intentionally not carried here.
class _CounterpartOh {
  final List<int> ohId;
  final String? endpoint;
  const _CounterpartOh({required this.ohId, this.endpoint});
}

/// T160: a rendezvous publish held until the lookup that must precede it has
/// answered, correlated by the lookups' ack tags (registered before each
/// packet leaves). Only a FOUND record for TODAY's key — the record the held
/// write replaces — releases it; otherwise it runs until
/// [RendezvousTiming.prePublishHoldMax]:
///
/// - a record found under yesterday's key is merged but is not what the
///   node keeps under today's key: releasing on it would write yesterday's
///   (older) creator entry over today's newer one (review 2/Q3);
/// - "no record" never releases. The published node answers a second lookup
///   for the same key within 30 s with an immediate, false "no record"
///   (the `KademliaSearchJob` anti-loop blacklist, fixed in redpandaj
///   `8f6268f`, not yet deployed), and the dense pairing schedule plus both
///   parties' reads produce exactly such repeats. Releasing on it let the
///   joiner write itself alone over the creator's record (lab `r1-local-1`).
///   A genuine "no record" comes only after the node's DHT search times
///   out (5–7 s), i.e. after the hold has ended anyway.
class _PrePublishHold {
  final Completer<void> done = Completer<void>();
  final Set<String> _decisive = {};
  final Set<String> _tracked = {};

  void track(String tagHex, {required bool decisive}) {
    _tracked.add(tagHex);
    if (decisive) _decisive.add(tagHex);
  }

  /// Releases the hold without an answer (disconnect).
  void release() {
    if (!done.isCompleted) done.complete();
  }

  void answered(String? tagHex, {required bool found}) {
    if (found && tagHex != null && _decisive.contains(tagHex)) release();
  }

  bool _reasked = false;

  /// True (once per hold) when [tagHex] is a NON-decisive lookup of this
  /// hold — the caller then asks today's key once more.
  bool claimTodayReask(String? tagHex) {
    if (_reasked || done.isCompleted || tagHex == null) return false;
    if (_decisive.contains(tagHex) || !_tracked.contains(tagHex)) return false;
    _reasked = true;
    return true;
  }
}

/// A queued in-band announcement of the sender's own mailbox set (T21
/// failover / T42 multi-OH). [descriptorsJson] is a JSON ARRAY of OHDescriptor
/// maps (T42, breaking — the pre-T42 single-object form is no longer sent).
/// The message id stays stable across the re-sends so the partner
/// deduplicates.
class _PendingOhUpdate {
  final Uint8List messageId;
  final String descriptorsJson;

  /// How many successful sends are left before the announce is considered
  /// delivered (best effort — a single garlic one-shot can die on a dead
  /// relay hop, see T41).
  int remainingSends = 3;

  _PendingOhUpdate({required this.messageId, required this.descriptorsJson});
}

/// FIFO matcher for response commands that can have several requests in
/// flight (the node answers in request order on one connection).
///
/// A request that gave up waiting calls [abandon]; its response, should it
/// still arrive, is then consumed and dropped instead of being misattributed
/// to the next request in the queue. Against nodes that never answer
/// (pre-MS02b), abandoning only increments a counter, so nothing accumulates.
class _ResponseQueue {
  final Queue<Completer<List<int>>> _pending = Queue();
  int _abandoned = 0;

  /// Enqueues and returns a completer for the next response.
  Completer<List<int>> register() {
    final completer = Completer<List<int>>();
    _pending.add(completer);
    return completer;
  }

  /// Marks [completer]'s response as no longer awaited (e.g. timeout). One
  /// future response will be consumed silently to keep the FIFO aligned.
  void abandon(Completer<List<int>> completer) {
    if (_pending.remove(completer)) {
      _abandoned++;
    }
  }

  /// Routes [payload] to the oldest waiting completer, honoring abandoned
  /// slots first.
  void handle(List<int> payload) {
    if (_abandoned > 0) {
      _abandoned--;
      return;
    }
    while (_pending.isNotEmpty) {
      final completer = _pending.removeFirst();
      if (!completer.isCompleted) {
        completer.complete(payload);
        return;
      }
    }
  }

  void clear() {
    _pending.clear();
    _abandoned = 0;
  }
}

/// Shape of the reply path embedded in an outgoing message (see
/// [RedPandaLightClient.lastOwnRgbShape]).
enum OwnReplyPathShape {
  /// Relays closed by our own mailbox host (T162).
  hostClosed,

  /// Relays only, ending at the last relay (pre-T162 shape).
  open,

  /// No reply path attached.
  none,
}

/// The route a [RedPandaLightClient.sendMessage] payload takes (T162 G1).
enum _RouteKind { viaRgb, forward, none }

/// T167: where a poll cycle stands with one OH (see `_cycleFetchPhase`).
enum _CycleFetchPhase { pending, inFlight, done }

/// Counters behind the per-minute `fetch.summary` diagnostics event (T180).
class _DiagFetchStats {
  static const int windowMs = 60000;
  static const int heartbeatMs = 15 * 60000;

  /// Start of the current window; null until the first check.
  int? sinceMs;
  int polls = 0;
  int ok = 0;
  int failures = 0;
  int items = 0;
  int notifies = 0;

  /// Whether a summary is due: at least a minute since the last one and
  /// something [interesting] happened, or the heartbeat period passed.
  bool due(int nowMs, {required bool interesting}) {
    final since = sinceMs;
    if (since == null || nowMs < since) {
      reset(nowMs);
      return false;
    }
    final age = nowMs - since;
    return age >= heartbeatMs || (interesting && age >= windowMs);
  }

  void reset(int nowMs) {
    sinceMs = nowMs;
    polls = 0;
    ok = 0;
    failures = 0;
    items = 0;
    notifies = 0;
  }
}

/// The verdict on one fetched mail item, for its `fetch.item` event (T180).
class _DiagItem {
  String kind = 'unknown';
  String? msg;
  String? outcome;
  String? reason;

  void accept() => outcome = 'accepted';

  void drop(String why) {
    outcome = 'dropped';
    reason = why;
  }

  /// [dropReason] null = accepted.
  void finish(String? dropReason) =>
      dropReason == null ? accept() : drop(dropReason);
}
