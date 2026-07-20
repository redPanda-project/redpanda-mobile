import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;

import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/rendezvous_manager.dart';
import 'package:redpanda_light_client/src/crypto/group_control.dart';
import 'package:redpanda_light_client/src/crypto/group_crypto.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v3.dart';
import 'package:redpanda_light_client/src/crypto/message_crypto_v4.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/domain/channel_doctor_report.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/loopback_result.dart';
import 'package:redpanda_light_client/src/domain/oh_fetch_status.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/domain/reverse_garlic_block.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/garlic/ack_tag_store.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/hop_selector.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:redpanda_light_client/src/garlic/return_path.dart';
import 'package:redpanda_light_client/src/garlic/rgb_builder.dart';
import 'package:redpanda_light_client/src/garlic/session_tag_store.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

import 'package:redpanda_light_client/src/peer_repository.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';
import 'package:redpanda_light_client/src/models/peer_stats_snapshot.dart';

import 'package:redpanda_light_client/src/network/active_peer.dart';

/// The implementation of the RedPanda Light Client.
/// Manages network connections, encryption, and routing.

/// The implementation of the RedPanda Light Client.
/// Manages network connections, encryption, and routing.
class RedPandaLightClient implements RedPandaClient {
  final NodeId selfNodeId;
  final KeyPair selfKeys;

  // TODO: Inject NetworkManager/ConnectionManager
  // final NetworkManager _networkManager;

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  /// Bootstrap nodes of the first real v23 network (live since 2026-07-11).
  /// Tests and local setups inject their own list via the `seeds` parameter.
  static const List<String> defaultSeeds = [
    '5.75.137.166:59558',
    '46.224.156.238:59558',
  ];

  final SocketFactory _socketFactory;
  // final Set<String> _knownAddresses = {}; // Replaced by PeerRepository
  final PeerRepository _peerRepository;
  final Map<String, ActivePeer> _peers = {};
  Timer? _connectionTimer;
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  // Configuration
  static const int maxConnections = 5;
  static const int coreSlots = 3;
  static const int roamingSlots = 2;
  static const Duration backoffDuration = Duration(seconds: 10);

  /// TCP dial timeout for the default socket factory (see constructor).
  static const Duration connectTimeout = Duration(seconds: 10);

  // State for mobile Optimization
  // bool _isBackgrounded = false; // To be set by flutter lifecycle
  bool _isBadInternetDetected = false;
  DateTime _lastGlobalConnectionAttempt = DateTime.fromMillisecondsSinceEpoch(
    0,
  );

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

  /// Channels whose persisted garlic session state was already restored;
  /// re-registrations via addChannelKeys never overwrite live state.
  final Set<String> _restoredGarlicSessions = {};

  final _garlicSessionController =
      StreamController<GarlicSessionUpdate>.broadcast();

  /// Hop count of the most recent sendMessage (0 = direct MS02b deposit).
  /// Diagnostic only — used by tests to assert the garlic path was taken.
  int lastSendHopCount = 0;

  /// True when the most recent sendMessage traveled a reverse-garlic reply
  /// path (CMD_DELIVER_TAGGED over the partner's RGB hops). Diagnostic only.
  bool lastSendViaRgb = false;

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

  final _routingAckController = StreamController<RoutingAckUpdate>.broadcast();
  final _channelAckController = StreamController<ChannelAckUpdate>.broadcast();
  final _nodeScoreController = StreamController<List<NodeScore>>.broadcast();

  /// Registered groups by group id (MS08).
  final Map<String, _GroupState> _groups = {};

  final _groupStateController = StreamController<GroupStateUpdate>.broadcast();
  final _groupHandshakeController =
      StreamController<GroupHandshakeEvent>.broadcast();

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
    // Extra predicate for garlic hop candidates (tests pin local nodes).
    bool Function(PeerStats peer)? hopCandidateFilter,
  }) : _socketFactory =
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
    _isBadInternetDetected = false; // transform optimism
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
  Stream<ConnectionStatus> get connectionStatus async* {
    yield _currentStatus;
    yield* _connectionStatusController.stream;
  }

  @override
  Stream<int> get peerCountStream async* {
    yield _peers.values.where((p) => p.isHandshakeVerified).length;
    yield* _peerCountController.stream;
  }

  /// PROVISIONAL: Stream of currently connected peer addresses.
  Stream<List<String>> get activePeersStream async* {
    yield _peers.values
        .where((p) => p.isHandshakeVerified)
        .map((p) => p.address)
        .toList();
    // We reuse the peerCount controller to signal updates for now?
    // Or we need a new controller.
    // Let's create a new controller or just reuse peerCount logic as a trigger.
    await for (final _ in _peerCountController.stream) {
      yield _peers.values
          .where((p) => p.isHandshakeVerified)
          .map((p) => p.address)
          .toList();
    }
  }

  Stream<List<String>> get connectingPeersStream async* {
    yield _peers.values
        .where((p) => !p.isHandshakeVerified)
        .map((p) => p.address)
        .toList();
    await for (final _ in _peerCountController.stream) {
      yield _peers.values
          .where((p) => !p.isHandshakeVerified)
          .map((p) => p.address)
          .toList();
    }
  }

  /// Currently active (handshake-verified) peer addresses.
  Set<String> get activePeerAddresses => _peers.values
      .where((p) => p.isHandshakeVerified)
      .map((p) => p.address)
      .toSet();

  /// Currently connecting (not yet verified) peer addresses.
  Set<String> get connectingPeerAddresses => _peers.values
      .where((p) => !p.isHandshakeVerified && !p.isDisconnected)
      .map((p) => p.address)
      .toSet();

  @override
  Stream<PeerStatsSnapshot> get peerStatsStream async* {
    yield PeerStatsSnapshot(
      allPeers: getDebugPeerStats(),
      activePeerAddresses: activePeerAddresses,
      connectingPeerAddresses: connectingPeerAddresses,
    );
    await for (final _ in _peerCountController.stream) {
      yield PeerStatsSnapshot(
        allPeers: getDebugPeerStats(),
        activePeerAddresses: activePeerAddresses,
        connectingPeerAddresses: connectingPeerAddresses,
      );
    }
  }

  void _updateStatus(ConnectionStatus status) {
    // Recalculate connected peers
    int connectedCount = _peers.values
        .where((p) => p.isHandshakeVerified)
        .length;
    _peerCountController.add(connectedCount);

    // Simple aggregation: If ANY connected -> Connected.
    // If ALL disconnected -> Disconnected.
    // Logic:
    // If incoming status is connected -> set global connected.
    // If incoming is disconnected -> Check if others are connected.

    if (status == ConnectionStatus.connected) {
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
          if (entry.value.isHandshakeVerified) {
            _nextRetryTime.remove(entry.key);
            _retryCounts.remove(entry.key);
          }
        }

        // T27: (re-)connected — run a catch-up poll right away instead of
        // waiting for the next scheduled tick (up to 30 s). Deliberately
        // does NOT start the fast-cadence window; a non-empty fetch does.
        if (_pollingEnabled && !_pollInProgress) {
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
      bool anyConnected = _peers.values.any((p) => p.isHandshakeVerified);
      if (!anyConnected && _currentStatus != ConnectionStatus.disconnected) {
        _currentStatus = ConnectionStatus.disconnected;
        _connectionStatusController.add(ConnectionStatus.disconnected);
      }
    }
  }

  @override
  Future<void> connect() async {
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

  Future<void> _runConnectionCheck() async {
    // 0. If bad internet detected, throttle
    if (_isBadInternetDetected) {
      if (DateTime.now().difference(_lastGlobalConnectionAttempt).inSeconds <
          10) {
        return; // Wait 10s before trying again if we think logic is bad
      }
      _isBadInternetDetected = false; // Reset and try again
    }
    _lastGlobalConnectionAttempt = DateTime.now();

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
      if (peer.isHandshakeVerified) {
        // If hasn't pinged in 10s, ping
        // We can do this based on timer or here
        peer.ping();
      }
      return false;
    });

    // 2. Classify Current Peers
    // A. Verify Capacity
    if (_peers.length > maxConnections) {
      // Disconnect worst performing extra peers
      final sortedParams = _peers.values.toList()
        ..sort(
          (a, b) => a.averageLatencyMs.compareTo(b.averageLatencyMs),
        ); // Lower latency first

      // Remove active peers that are worst
      for (var i = maxConnections; i < sortedParams.length; i++) {
        RpLog.debug(
          'RedPandaLightClient: Over capacity. Disconnecting ${sortedParams[i].address}',
        );
        sortedParams[i].disconnect();
      }
    }

    // B. Rotate Roaming Peers
    // B. Rotate Roaming Peers
    final best3 = _peerRepository.getBestPeers(3).map((p) => p.address).toSet();
    final connectedRoaming = _peers.values
        .where((p) => p.isHandshakeVerified && !best3.contains(p.address))
        .toList();

    if (connectedRoaming.length >= 2) {
      // Find candidates for rotation (Age > 10s)
      final candidates = connectedRoaming.where((p) {
        final age = DateTime.now().difference(p.connectedSince).inSeconds;
        // print('DEBUG: Rotation Candidate: ${p.address} Age=${age}s');
        return age >= 10;
      }).toList();

      // Disconnect ONLY ONE (the oldest)
      if (candidates.isNotEmpty) {
        candidates.sort(
          (a, b) => a.connectedSince.compareTo(b.connectedSince),
        ); // Oldest first
        final victim = candidates.first;
        final age = DateTime.now().difference(victim.connectedSince).inSeconds;

        RpLog.debug(
          'RedPandaLightClient: Rotating ONE roaming peer ${victim.address} (Connected ${age}s). Keeping others.',
        );
        _intentionalDisconnects.add(victim.address);
        victim.disconnect();
      }
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
      if (connectedCount >= maxConnections) break; // Hard limit
      if (connectedCount >= targetCore && _peers.length >= targetCore) {
        // If we already have enough core-like connections, stop filling from top list
        // Note: _peers.length includes current connections. We need to be careful not to count roaming as core?
        // Actually, we just want to ensure we don't fill ALL slots with candidates.
        // We break if we have reached the "Core" saturation for this loop.
        break;
      }

      if (!_peers.containsKey(candidate.address)) {
        // Check backoff
        if (_nextRetryTime.containsKey(candidate.address)) {
          if (DateTime.now().isBefore(_nextRetryTime[candidate.address]!)) {
            continue;
          }
        }
        toConnect.add(candidate.address);
        connectedCount++;
      }
    }

    // Random filling if we still have space (Roaming)
    int backoffSkipped = 0;
    if (connectedCount < maxConnections) {
      final all = _peerRepository.knownAddresses.toList()..shuffle();
      for (final addr in all) {
        if (connectedCount >= maxConnections) break;
        if (!_peers.containsKey(addr) && !toConnect.contains(addr)) {
          // Check backoff
          if (_waitInBackoff(addr)) {
            backoffSkipped++;
            continue;
          }
          toConnect.add(addr);
          connectedCount++;
        }
      }
    }

    if (toConnect.isEmpty && _peers.isEmpty) {
      if (_peerRepository.knownAddresses.isNotEmpty && backoffSkipped == 0) {
        RpLog.debug(
          'RedPandaLightClient: No peers to connect to. Bad Internet?',
        );
        _isBadInternetDetected = true;
      }
      return;
    }

    // 4. Connect
    // Resolve Deduplication done in ActivePeer or before connect?
    // We do simplified resolve check here
    final connectedIps = await _resolveConnectedIps();

    for (final address in toConnect) {
      try {
        if (await _isAliasOfConnected(address, connectedIps)) {
          continue;
        }

        final peer = ActivePeer(
          address: address,
          selfNodeId: selfNodeId,
          selfKeys: selfKeys,
          socketFactory: _socketFactory,
          onStatusChange: _updateStatus,
          onNodeIdDiscovered: (nodeId, encryptionPublicKey) {
            _peerRepository.updatePeer(
              address,
              nodeId: nodeId,
              encryptionPublicKey: encryptionPublicKey,
            );
          },
          onDisconnect: () {
            if (_intentionalDisconnects.contains(address)) {
              RpLog.debug(
                'RedPandaLightClient: Peer $address disconnected intentionally (Rotation). No failure recorded.',
              );
              _intentionalDisconnects.remove(address);
              _handleBackoff(address); // Still backoff to ensure we rotate
            } else {
              _peerRepository.updatePeer(address, isFailure: true);
              _handleBackoff(address);
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
            // Return top 20 best peers to share
            return _peerRepository
                .getBestPeers(20)
                .map((p) => p.address)
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
        _peerRepository.updatePeer(address, isFailure: true);
      }
    }
  }

  // --- Helper Methods ---

  bool _waitInBackoff(String address) {
    if (_nextRetryTime.containsKey(address)) {
      if (DateTime.now().isBefore(_nextRetryTime[address]!)) {
        return true;
      }
    }
    return false;
  }

  void _handleBackoff(String address) {
    int count = (_retryCounts[address] ?? 0) + 1;
    _retryCounts[address] = count;

    // Exponential backoff: 2s, 4s, 8s...
    // 2 * (2^(count-1))
    int seconds = 2 * (1 << (count - 1));
    // Cap at 30 s (was 5 min): after a ~1 min outage the old cap made the
    // next reconnect attempt wait up to several minutes — the dominant part
    // of post-airplane-mode delivery delay (T27). A capped attempt is one
    // TCP dial per address per 30 s, negligible traffic/battery.
    if (seconds > 30) seconds = 30;

    _nextRetryTime[address] = DateTime.now().add(Duration(seconds: seconds));
  }

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

  Future<Set<String>> _resolveConnectedIps() async {
    final connectedIps = <String>{};
    // Copy: _peers may be mutated by peer callbacks while we await lookups.
    for (final peer in List.of(_peers.values)) {
      if (!peer.isDisconnected) {
        try {
          final parts = peer.address.split(':');
          final host = parts[0];
          final lookup = await InternetAddress.lookup(host);
          for (final addr in lookup) {
            connectedIps.add('${addr.address}:${parts[1]}');
          }
        } catch (e) {
          // Ignore lookup errors
        }
      }
    }
    return connectedIps;
  }

  Future<bool> _isAliasOfConnected(
    String address,
    Set<String> connectedIps,
  ) async {
    try {
      final parts = address.split(':');
      final host = parts[0];
      final port = parts[1];
      final lookup = await InternetAddress.lookup(host);

      for (final addr in lookup) {
        if (connectedIps.contains('${addr.address}:$port')) {
          return true;
        }
      }
    } catch (e) {
      // resolution failed
    }
    return false;
  }

  @override
  Future<void> addPeer(String address) async {
    _peerRepository.updatePeer(address);
    _runConnectionCheck();
  }

  @override
  Future<void> disconnect() async {
    _connectionTimer?.cancel();
    _pollingEnabled = false; // stop the self-rescheduling poll loop (T27)
    _nextPollAt = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    for (final peer in _peers.values) {
      await peer.disconnect();
    }
    _peers.clear();
    _registeredOHs.clear();
    _pendingResponses.clear();
    _putResponses.clear();
    _registerResponses.clear();
    _subscribeResponses.clear();
    _ratchetSessions.clear();
    _pendingRgbs.clear();
    _restoredGarlicSessions.clear();
    _fetchFailureCounts.clear();
    _failoversInProgress.clear();
    _pendingOhUpdates.clear();
    await _incomingMessageController.close();
    await _ohMailboxUpdateController.close();
    await _ohFetchStatusController.close();
    await _ohRegistrationController.close();
    await _peerOhUpdateController.close();
    await _ratchetStateController.close();
    await _garlicSessionController.close();
    _updateStatus(ConnectionStatus.disconnected);
  }

  // --- OH Registration & Message state ---
  final List<OHRegistration> _registeredOHs = [];
  final _incomingMessageController =
      StreamController<DecryptedMessage>.broadcast();
  final _ohMailboxUpdateController =
      StreamController<OhMailboxUpdate>.broadcast();
  final _ohFetchStatusController = StreamController<OhFetchStatus>.broadcast();
  final _ohRegistrationController =
      StreamController<List<OHRegistration>>.broadcast();
  final _peerOhUpdateController = StreamController<PeerOhUpdate>.broadcast();

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

  /// When the currently scheduled poll fires — lets fresh activity pull an
  /// already-scheduled (slow) poll forward.
  DateTime? _nextPollAt;

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
    if (command == 158) {
      _putResponses.handle(payload);
      return;
    }
    if (command == 151) {
      _registerResponses.handle(payload);
      return;
    }
    if (command == 160) {
      // Connection-Notify (T38): SubscribeResponse, FIFO-matched.
      _subscribeResponses.handle(payload);
      return;
    }
    if (command == 161) {
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
  void _handleNotify(List<int> payload) {
    final Notify notify;
    try {
      notify = Notify.fromBuffer(payload);
    } catch (e) {
      RpLog.info('RedPandaLightClient: dropping malformed Notify: $e');
      return;
    }
    final known = _registeredOHs.any((oh) => _sameOhId(oh.ohId, notify.ohId));
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
    // Keep the fast cadence going: a Notify means the conversation is live.
    _lastChatActivity = DateTime.now();
    // A cycle currently in flight will fetch this OH (it iterates all OHs);
    // otherwise pull the next cycle forward to right now.
    if (_pollingEnabled && !_pollInProgress) {
      _schedulePoll(Duration.zero);
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
    final activePeer = _peerForHandle(oh, 'subscribe()');
    if (activePeer == null) {
      // _peerForHandle already logged/kicked off the host connection.
      return;
    }

    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final now = DateTime.now();

    final signingBuffer = BytesBuilder();
    signingBuffer.addByte(159); // OUTBOUND_SUBSCRIBE_REQ
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
    activePeer.sendCommand(159, Uint8List.fromList(request.writeToBuffer()));

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
      return;
    }

    final SubscribeResponse response;
    try {
      response = SubscribeResponse.fromBuffer(responseBytes);
    } catch (e) {
      RpLog.info(
        'RedPandaLightClient: dropping malformed SubscribeResponse: $e',
      );
      return;
    }
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

  /// The PRIMARY peer OH id per channel (== [_channelPeerOhSet].first). Kept
  /// as a plain map so the single-target senders (garlic, RGB reply,
  /// direct-deposit fallback, ack routing) stay unchanged — they always aim
  /// at the primary. The multi-deposit fan-out (T42) uses the full set below.
  final Map<String, List<int>> _channelPeerOhIds = {};

  /// host:port of the node hosting the peer's PRIMARY OH (from the
  /// OHDescriptor), excluded from garlic hop candidates (MS04: no hop ==
  /// destination node).
  final Map<String, String> _channelPeerOhEndpoints = {};

  /// T42: the FULL set of the partner's known OH mailboxes per channel.
  /// A send deposits into EVERY entry in parallel (the receiver deduplicates
  /// by message_id), so one dead OH-host node no longer stalls delivery — the
  /// copy on the surviving node arrives without waiting for a failover. The
  /// set is seeded from the QR/primary OH and grown/replaced by the in-band
  /// `oh_update` announce (a JSON array of descriptors, T42). The first entry
  /// mirrors [_channelPeerOhIds]/[_channelPeerOhEndpoints].
  final Map<String, List<_PeerOh>> _channelPeerOhSet = {};

  /// Sets the primary peer OH (id + endpoint) for [channelId] and seeds the
  /// peer OH set with it when no richer set is known yet — a set already
  /// grown via `oh_update` (or restored) is always at least as complete, so
  /// it is never clobbered by a re-registration (chat-screen re-open).
  void _seedPrimaryPeerOh(String channelId, List<int> ohId, String? endpoint) {
    _channelPeerOhIds[channelId] = ohId;
    if (endpoint != null) {
      _channelPeerOhEndpoints[channelId] = endpoint;
    }
    final existing = _channelPeerOhSet[channelId];
    if (existing == null || existing.isEmpty) {
      _channelPeerOhSet[channelId] = [_PeerOh(ohId: ohId, endpoint: endpoint)];
    }
  }

  /// Replaces the peer OH set for [channelId] with [descriptors] (deduplicated
  /// by OH id, order preserved) and re-points the primary at the first entry.
  /// Returns true when the set actually changed.
  bool _replacePeerOhSet(String channelId, List<OHDescriptor> descriptors) {
    final deduped = <_PeerOh>[];
    for (final d in descriptors) {
      if (d.handleId.length != GarlicHop.nodeIdLength) continue;
      if (deduped.any((e) => _sameOhId(e.ohId, d.handleId))) continue;
      deduped.add(_PeerOh(ohId: d.handleId, endpoint: d.serverEndpoint));
    }
    if (deduped.isEmpty) return false;
    final previous = _channelPeerOhSet[channelId];
    if (previous != null &&
        previous.length == deduped.length &&
        List.generate(
          previous.length,
          (i) =>
              _sameOhId(previous[i].ohId, deduped[i].ohId) &&
              previous[i].endpoint == deduped[i].endpoint,
        ).every((x) => x)) {
      return false; // identical — a duplicate announce
    }
    _channelPeerOhSet[channelId] = deduped;
    _channelPeerOhIds[channelId] = deduped.first.ohId;
    final primaryEndpoint = deduped.first.endpoint;
    if (primaryEndpoint != null) {
      _channelPeerOhEndpoints[channelId] = primaryEndpoint;
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
      if (out.any((d) => _sameOhId(d.handleId, oh.ohId))) continue;
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

  final _ratchetStateController =
      StreamController<RatchetStateUpdate>.broadcast();

  @override
  Stream<RatchetStateUpdate> get ratchetStateUpdates =>
      _ratchetStateController.stream;

  /// Register channel encryption info so sendMessage/fetchMessages can use it.
  @override
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? channelSecret,
    String? ownDisplayName,
    List<int>? peerOhId,
    String? peerOhEndpoint,
    List<OHDescriptor>? peerOhSet,
    required bool isChannelCreator,
    String? ratchetState,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
  }) {
    _channelEncryptionKeys[channelId] = encryptionKey;
    // T44: register the rendezvous state (QR v4). Without the channel secret
    // (legacy caller) the rendezvous DHT layer stays dormant for this channel.
    if (channelSecret != null && channelSecret.length == 32) {
      _rendezvous.register(
        channelId,
        channelSecret: channelSecret,
        isCreator: isChannelCreator,
        ownName: ownDisplayName ?? '',
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
    // T42: restore the full persisted peer OH set first (multi-OH), then seed
    // the primary. Both are applied only when nothing richer is live yet —
    // an `oh_update` learned this session always wins.
    if (peerOhSet != null && peerOhSet.isNotEmpty) {
      if (_channelPeerOhSet[channelId] == null) {
        _replacePeerOhSet(channelId, peerOhSet);
      }
    }
    if (peerOhId != null) {
      _seedPrimaryPeerOh(channelId, peerOhId, peerOhEndpoint);
    }
    _restoreGarlicSession(channelId, sessionTags, pendingRgbHex);
    // A live session is always at least as advanced as any persisted state,
    // so re-registrations (e.g. on every chat-screen open) never replace it.
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

  /// Restores persisted reverse-garlic session state (MS05). Applied once
  /// per channel; live state is always at least as advanced as anything
  /// persisted, so re-registrations never overwrite it.
  void _restoreGarlicSession(
    String channelId,
    Map<String, int>? sessionTags,
    String? pendingRgbHex,
  ) {
    if (!_restoredGarlicSessions.add(channelId)) return;
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
    if (_garlicSessionController.isClosed) return;
    final rgb = _pendingRgbs[channelId];
    _garlicSessionController.add(
      GarlicSessionUpdate(
        channelId: channelId,
        sessionTags: _sessionTagStore.tagsForChannel(channelId),
        pendingRgbHex: rgb != null ? _hexEncode(rgb.serialize()) : null,
      ),
    );
  }

  /// Routing-layer delivery feedback (R-ACK received / timed out, MS06).
  @override
  Stream<RoutingAckUpdate> get routingAckUpdates =>
      _routingAckController.stream;

  /// Application-layer delivery confirmations (Channel-ACK, MS06).
  @override
  Stream<ChannelAckUpdate> get channelAckUpdates =>
      _channelAckController.stream;

  /// Node score snapshots for on-device persistence (MS06). Emitted after
  /// every score change; the app layer upserts them into `node_scores`.
  @override
  Stream<List<NodeScore>> get nodeScoreUpdates => _nodeScoreController.stream;

  /// Restores persisted node scores (startup). Live in-memory scores win.
  @override
  void restoreNodeScores(List<NodeScore> scores) {
    _nodeScorer.restore(scores);
  }

  void _emitNodeScores() {
    if (!_nodeScoreController.isClosed) {
      _nodeScoreController.add(_nodeScorer.snapshot());
    }
  }

  @override
  Stream<GarlicSessionUpdate> get garlicSessionUpdates =>
      _garlicSessionController.stream;

  /// Publishes the advanced ratchet state of [channelId] so the app layer
  /// can persist it (on-device only).
  void _emitRatchetState(String channelId, RatchetSession session) {
    if (_ratchetStateController.isClosed) return;
    _ratchetStateController.add(
      RatchetStateUpdate(channelId: channelId, stateJson: session.toJson()),
    );
  }

  @override
  Stream<DecryptedMessage> get incomingMessages =>
      _incomingMessageController.stream;

  @override
  Stream<OhMailboxUpdate> get ohMailboxUpdates =>
      _ohMailboxUpdateController.stream;

  @override
  Stream<OhFetchStatus> get ohFetchStatus => _ohFetchStatusController.stream;

  @override
  Stream<List<OHRegistration>> get ohRegistrationUpdates =>
      _ohRegistrationController.stream;

  @override
  Stream<PeerOhUpdate> get peerOhUpdates => _peerOhUpdateController.stream;

  /// Timestamp (ms since epoch) of the last successful mailbox fetch per
  /// channel id. Fed by [_emitFetchStatus]; read by [runChannelDoctor] to
  /// judge how fresh the receiving pipeline is. Purely diagnostic.
  final Map<String, int> _lastFetchOkAtMs = {};

  /// Reports the outcome of one fetch attempt (success AND failure — unlike
  /// [ohMailboxUpdates], which only fires on state changes).
  void _emitFetchStatus(OHRegistration oh, bool success, [String? detail]) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final channelId = oh.channelId;
    if (success && channelId != null) {
      _lastFetchOkAtMs[channelId] = nowMs;
    }
    if (_ohFetchStatusController.isClosed) return;
    _ohFetchStatusController.add(
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
      (oh) => _sameOhId(oh.ohId, registration.ohId),
    );
    if (alreadyKnown) return;

    _registeredOHs.add(registration);
    _startPolling();
  }

  static bool _sameOhId(List<int> a, List<int> b) {
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
    final rgb = _buildOwnRgb(channelId);

    // Build the inner ChannelMessage (message_id + timestamp + content +
    // optional reply path) and encrypt it into a v4 payload with the channel
    // ratchet (MS03b): the AES-GCM key is the per-message key MK_n, not the
    // static K_enc.
    final channelMessage = ChannelMessage(
      messageId: messageIdBytes,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      content: content,
      replyPath: rgb?.serialize(),
    );
    final session = await _ratchetSessions[channelId]!;
    final payload = await session.encrypt(channelMessage, channelId);
    // Persist immediately: the sending chain has advanced even if the
    // deposit below fails — a retry re-encrypts with the next message key.
    _emitRatchetState(channelId, session);

    // Send to a connected peer (best available). The node routes garlic
    // packets toward their first hop / deposits direct puts locally or
    // forwards them (MS02b), so any connected Full Node works.
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;

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
      } else if (payload.length <=
          GarlicBuilder.maxPayloadLength(
            pendingRgb.hops.length,
            tagged: true,
          )) {
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
          'bytes exceeds the tagged reply budget, using the forward path',
        );
      }
    }

    // T45: garlic-only deposit into the peer's mailbox set. A deposit is NEVER
    // sent as a direct FlaschenpostPut anymore — the connected node must not be
    // able to observe every deposit pattern (MS04 privacy; binding user
    // decision 2026-07-20: Garlic ALWAYS, one hop-disjoint route per peer OH).
    // Each known peer OH gets its own garlic route with forward hops kept
    // disjoint across routes (best-effort anti-correlation); a degenerate net
    // with no relay candidates routes the packet through the connected node
    // itself (uniform garlic — still command 142, never a direct 141 deposit).
    final targets =
        _channelPeerOhSet[channelId]
            ?.where((t) => t.ohId.length == GarlicHop.nodeIdLength)
            .toList(growable: false) ??
        const <_PeerOh>[];
    if (targets.isEmpty) {
      // No known peer OH — no route can be built. Keep the message pending
      // (the app retries it) and kick off a rendezvous DHT recovery so a later
      // retry finds the peer's current mailboxes (T44).
      RpLog.info(
        'RedPandaLightClient: sendMessage() channel $channelId has no known '
        'peer OH — message stays pending for retry',
      );
      unawaited(_recoverViaRendezvous(channelId));
      throw UnknownPeerException(channelId);
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
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
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
    final verifiedCount = _peers.values
        .where((p) => p.isHandshakeVerified)
        .length;
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
          final hostPeer = _peers[endpoint];
          if (hostPeer != null && hostPeer.isHandshakeVerified) {
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

    // Stage 3: peer OH mailboxes known (required for sending). Reports how
    // many of the partner's mailboxes we can deposit into (T42 fan-out).
    sw
      ..reset()
      ..start();
    final peerSet = _channelPeerOhSet[channelId] ?? const <_PeerOh>[];
    if (peerSet.isEmpty) {
      stages.add(
        _stage(
          'Peer mailbox known',
          DoctorStatus.warn,
          sw,
          'Peer mailbox unknown — scan the peer\'s QR code to enable '
              'sending. Receiving still works.',
        ),
      );
    } else {
      final endpoints = peerSet
          .map((p) => p.endpoint)
          .whereType<String>()
          .toList(growable: false);
      stages.add(
        _stage(
          'Peer mailbox known',
          DoctorStatus.ok,
          sw,
          peerSet.length == 1
              ? (endpoints.isNotEmpty
                    ? 'Peer mailbox on ${endpoints.first}.'
                    : 'Peer mailbox id known.')
              : '${peerSet.length} peer mailboxes known'
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
    final keyHex = _peerRepository
        .getPeer(submitVia.address)
        ?.encryptionPublicKey;
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
  /// be formed. A self-hop route carries no privacy and must not request an
  /// R-ACK (it has no return relay path).
  ({List<GarlicHop> hops, bool selfHop})? _garlicRoute(
    ActivePeer submitVia, {
    String? ohEndpoint,
    Set<String> excludeNodeIds = const {},
  }) {
    var hops = _hopSelector.selectHops(
      count: defaultHopCount,
      excludeAddresses: {submitVia.address, ?ohEndpoint},
      excludeNodeIds: {?submitVia.discoveredNodeId, ...excludeNodeIds},
    );
    if (hops.isEmpty && excludeNodeIds.isNotEmpty) {
      // Not enough DISJOINT candidates left for this extra route — reuse relay
      // hops rather than degrade to a privacy-less self-hop. Disjointness
      // across routes is best-effort under hop scarcity (fewer than
      // routeCount × hopCount relay candidates).
      hops = _hopSelector.selectHops(
        count: defaultHopCount,
        excludeAddresses: {submitVia.address, ?ohEndpoint},
        excludeNodeIds: {?submitVia.discoveredNodeId},
      );
    }
    if (hops.isNotEmpty) return (hops: hops, selfHop: false);
    final self = _selfHop(submitVia);
    if (self == null) return null;
    return (hops: [self], selfHop: true);
  }

  /// T45: deposits [payload] into EVERY known peer OH in [targets], each over
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
    List<_PeerOh> targets,
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
        );
      } on DepositException catch (e) {
        // A payload that exceeds the garlic budget is permanently
        // undeliverable — re-sending the SAME content over any route can
        // never succeed, so surface it instead of retrying forever.
        if (e.isBadRequest) rethrow;
        RpLog.info(
          'RedPandaLightClient: garlic deposit to one peer OH for channel '
          '$channelId failed: $e',
        );
        continue;
      } catch (e) {
        RpLog.info(
          'RedPandaLightClient: garlic deposit to one peer OH for channel '
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
  ReverseGarlicBlock? _buildOwnRgb(String channelId) {
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .firstOrNull;
    if (ownOh == null) return null;

    // The mailbox host never becomes a return relay (mirrors the MS04
    // peerOhEndpoint exclusion on the forward path).
    final rgb = _rgbBuilder.build(
      ohId: ownOh.ohId,
      hopCount: defaultHopCount,
      excludeAddresses: {?ownOh.serverEndpoint},
    );
    if (rgb == null) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() no eligible return hops known, '
        'sending without a reply path',
      );
      return null;
    }
    if (rgb.hops.length < defaultHopCount) {
      RpLog.info(
        'RedPandaLightClient: sendMessage() reply path has only '
        '${rgb.hops.length} of $defaultHopCount hops — reduced privacy',
      );
    }
    _sessionTagStore.store(rgb.sessionTagHex, channelId);
    _emitGarlicSession(channelId);
    return rgb;
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
    submitVia.sendCommand(142, packet);
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
    // never relays its own acks; the submit node sees us directly).
    final returnHops = _hopSelector.selectHops(
      count: defaultHopCount,
      excludeAddresses: {?ownOh.serverEndpoint, submitVia.address},
      excludeNodeIds: {?submitVia.discoveredNodeId},
    );
    final withinBudget =
        payloadLength <=
        GarlicBuilder.maxAckedPayloadLength(
          forwardHops.length,
          tagged: tagged,
          returnHopCount: returnHops.length,
        );
    if (!withinBudget) {
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
        for (final hop in forwardHops) _hexEncode(hop.nodeId),
        for (final hop in returnHops) _hexEncode(hop.nodeId),
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
  List<GarlicHop> _selectGarlicHops(String channelId, ActivePeer submitVia) {
    final ohEndpoint = _channelPeerOhEndpoints[channelId];
    return _hopSelector.selectHops(
      count: defaultHopCount,
      excludeAddresses: {submitVia.address, ?ohEndpoint},
      excludeNodeIds: {
        // The submission node may be known in the peer list under a
        // different address (e.g. seed alias) — exclude it by identity too.
        ?submitVia.discoveredNodeId,
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
  Future<void> _sendViaGarlic(
    ActivePeer submitVia,
    List<GarlicHop> hops,
    List<int> peerOhId,
    Uint8List payload,
    String channelId, {
    String? messageIdHex,
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
      ohId: peerOhId,
      payload: payload,
      returnPath: returnPath,
    );
    submitVia.sendCommand(142, packet);
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
    final activePeer = _peers.values
        .where(
          (p) => p.isHandshakeVerified && !excludeEndpoints.contains(p.address),
        )
        .firstOrNull;

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
      activePeer.sendCommand(150, Uint8List.fromList(buffer));

      List<int>? responseBytes;
      try {
        responseBytes = await completer.future.timeout(
          const Duration(seconds: 10),
        );
      } on TimeoutException {
        _registerResponses.abandon(completer);
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
          throw RateLimitException();
        }
        if (response.status == Status.OK) {
          // The server may clamp the requested TTL.
          expiresAtMs = response.expiresAtMs.toInt();
        } else {
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
      unawaited(_publishRendezvousIfChanged(channelId));
    }
    // T27: a freshly registered handle means a brand-new channel — the
    // partner's first message is expected shortly, so poll fast right away
    // (fixes the ~30 s first-message latency after a channel join).
    _notePollActivity();
    // T38: subscribe the new handle for real-time Notify.
    _enqueueSubscribe(registration);

    return registration;
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
    signingBuffer.addByte(150); // OUTBOUND_REGISTER_OH_REQ
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

  /// The connected peer hosting [oh]'s mailbox.
  ///
  /// OH state (mailbox, cursor, expiry) lives ONLY on the node the handle
  /// was registered with — fetch/ack/renew against any other node returns
  /// NOT_FOUND (observed in the field: after a reconnect the peer map
  /// order changed and every mailbox check silently asked the wrong node).
  /// When the host is currently not connected, a connection attempt is
  /// kicked off and null is returned — the caller skips this cycle and the
  /// next one reaches the host. Registrations without a recorded endpoint
  /// (never talked to a node) fall back to the first verified peer.
  ActivePeer? _peerForHandle(OHRegistration oh, String what) {
    final endpoint = oh.serverEndpoint;
    final verified = _peers.values.where((p) => p.isHandshakeVerified);
    if (endpoint == null) return verified.firstOrNull;
    final host = verified.where((p) => p.address == endpoint).firstOrNull;
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
      if (!_ohMailboxUpdateController.isClosed) {
        _ohMailboxUpdateController.add(
          OhMailboxUpdate(
            ohId: oh.ohId,
            channelId: oh.channelId,
            lastCursor: 0,
            expiresAtMs: oh.expiresAtMs,
          ),
        );
      }
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
  void _noteHostUnreachable(OHRegistration oh) {
    final hasAlternative = _peers.values.any(
      (p) => p.isHandshakeVerified && p.address != oh.serverEndpoint,
    );
    if (!hasAlternative) return;
    final key = _hexEncode(oh.ohId);
    final count = (_fetchFailureCounts[key] ?? 0) + 1;
    _fetchFailureCounts[key] = count;
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
    final peerOhId = _channelPeerOhIds[channelId];
    if (peerOhId == null || peerOhId.length != GarlicHop.nodeIdLength) return;
    if (_ratchetSessions[channelId] == null) return;

    unawaited(
      _failoverOwnHandle(oh).catchError((Object e) {
        RpLog.info(
          'RedPandaLightClient: OH failover for channel $channelId failed: $e',
        );
      }),
    );
  }

  /// Moves the channel of [oldOh] to a fresh mailbox on a reachable node
  /// (T21): registers a NEW handle (new id + keypair) on a node other than
  /// the dead host, retires the old handle, publishes the replacement via
  /// [ohRegistrationUpdates] and queues the in-band `oh_update` announce.
  ///
  /// Messages already deposited in the dead mailbox are not lost silently:
  /// the partner's unacknowledged sends re-queue on R-ACK timeout and are
  /// re-sent — to the new mailbox once the announce arrived.
  Future<void> _failoverOwnHandle(OHRegistration oldOh) async {
    final channelId = oldOh.channelId;
    if (channelId == null) return;
    if (!_failoversInProgress.add(channelId)) return;
    try {
      final OHRegistration replacement;
      try {
        replacement = await registerOutboundHandle(
          channelId: channelId,
          excludeEndpoints: {?oldOh.serverEndpoint},
        );
      } on RateLimitException {
        RpLog.info(
          'RedPandaLightClient: OH failover for channel $channelId '
          'rate-limited — retrying on a later cycle',
        );
        return;
      }
      if (replacement.serverEndpoint == null) {
        // Never reached a node — roll back; the failure counter stays at
        // the threshold, so the next failing fetch retries the failover.
        _registeredOHs.remove(replacement);
        return;
      }

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
    }
  }

  /// Emits the current own-OH set of [channelId] (T42) so the app layer syncs
  /// its persisted rows to exactly this set — additions (redundancy top-up)
  /// and failover replacements both flow through here, replacing the old
  /// per-channel handle rows.
  void _emitOwnOhSet(String channelId) {
    if (_ohRegistrationController.isClosed) return;
    final set = _registeredOHs
        .where((oh) => oh.channelId == channelId)
        .toList(growable: false);
    _ohRegistrationController.add(set);
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

  Future<void> _publishRendezvousIfChanged(String channelId) async {
    if (!_hasRendezvousRelays) return;
    if (!_rendezvous.knows(channelId)) return;
    final descriptors = _ownDescriptorsFor(channelId);
    if (descriptors.isEmpty) return;
    if (!_rendezvous.setOwnOhs(channelId, descriptors)) return;
    // Force a republish of the changed set (drop any prior publish stamp so
    // the poll-cycle retry also kicks in should this attempt find no hops).
    _lastRendezvousPublish.remove(channelId);
    await _publishRendezvous(channelId);
  }

  /// T44: builds the signed rendezvous record and stores it in the DHT via a
  /// `record_store` garlic packet routed to a REMOTE node (the connected node
  /// never sees the query interest). Best-effort, no response.
  Future<void> _publishRendezvous(String channelId) async {
    try {
      final submitVia = _peers.values
          .where((p) => p.isHandshakeVerified)
          .firstOrNull;
      if (submitVia == null) return;
      // Select hops BEFORE building the record so the per-poll-cycle retry does
      // no signing/AEAD work while no relay path exists (e.g. a single-node
      // network) — it just no-ops until hops appear.
      final hops = _selectGarlicHops(channelId, submitVia);
      if (hops.isEmpty) {
        RpLog.debug(
          'RedPandaLightClient: rendezvous publish for $channelId skipped — '
          'no relay hops known',
        );
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final store = await _rendezvous.buildSignedStore(channelId, now);
      if (store == null) return;
      final packet = await GarlicBuilder.buildRecordStore(
        hops: hops,
        kademliaStore: store,
      );
      submitVia.sendCommand(142, packet);
      // Mark as published only on an actual send with hops — otherwise the
      // poll cycle keeps retrying until garlic hops become available (the
      // publish-on-registration can race ahead of hop discovery).
      _lastRendezvousPublish[channelId] = DateTime.now();
      RpLog.debug(
        'RedPandaLightClient: published rendezvous record for $channelId over '
        '${hops.length} hops',
      );
    } catch (e) {
      RpLog.info('RedPandaLightClient: rendezvous publish failed: $e');
    }
  }

  /// T44: recovery — all of a peer's OHs are unreachable, so look the channel's
  /// rendezvous record up over the DHT (today's key, then yesterday's) and
  /// adopt the peer's current OH list. The lookups travel garlic-wrapped to a
  /// remote node; the answer returns via a reverse-garlic return path into our
  /// own OH mailbox and is correlated in the fetch loop by its ack tag.
  Future<void> _recoverViaRendezvous(String channelId) async {
    if (!_hasRendezvousRelays) return;
    if (!_rendezvous.knows(channelId)) return;
    // Throttle first (before any peer scan / key derivation): recovery fires
    // on every failing send/deposit, so a retry burst must be cheaply rejected.
    final nowThrottle = DateTime.now();
    final lastAttempt = _lastRecoveryAttempt[channelId];
    if (lastAttempt != null &&
        nowThrottle.difference(lastAttempt) < _recoveryMinInterval) {
      return;
    }
    final submitVia = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
    if (submitVia == null) return;
    final ownOh = _registeredOHs
        .where((oh) => oh.channelId == channelId && oh.serverEndpoint != null)
        .firstOrNull;
    if (ownOh == null) return; // need an own mailbox to receive the answer

    // Select the relay path FIRST. A record_lookup can only travel
    // garlic-wrapped to a remote node, so with no eligible hops (e.g. a
    // single-node network) recovery is impossible — bail out BEFORE the
    // key-derivation work. This is critical: the derivations below run pure-
    // Dart Ed25519/X25519 keygen on the single-threaded network isolate, and
    // recovery is triggered on every send failure — doing that keygen when we
    // could never send would stall the isolate (fetch/register timeouts).
    final hops = _selectGarlicHops(channelId, submitVia);
    if (hops.isEmpty) return;

    // Commit to an attempt only now that we know it can actually be sent.
    _lastRecoveryAttempt[channelId] = nowThrottle;

    final returnHops = _hopSelector.selectHops(
      count: defaultHopCount,
      excludeAddresses: {?ownOh.serverEndpoint, submitVia.address},
      excludeNodeIds: {?submitVia.discoveredNodeId},
    );
    final now = nowThrottle.millisecondsSinceEpoch;
    final keys = await _rendezvous.lookupKeys(channelId, now);
    for (final recordKey in keys) {
      try {
        final ackTag = CryptoUtils.randomBytes(GarlicBuilder.sessionTagLength);
        final ackTagHex = _hexEncode(ackTag);
        _recordLookupTags[ackTagHex] = channelId;
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
        submitVia.sendCommand(142, packet);
        RpLog.debug(
          'RedPandaLightClient: rendezvous lookup for $channelId sent over '
          '${hops.length} hops',
        );
      } catch (e) {
        RpLog.info('RedPandaLightClient: rendezvous lookup failed: $e');
      }
    }
  }

  /// Minimum spacing between rendezvous recovery attempts per channel.
  static const Duration _recoveryMinInterval = Duration(seconds: 30);
  final Map<String, DateTime> _lastRecoveryAttempt = {};

  /// T44: handles a `record_lookup` reverse-garlic answer
  /// (`[1 status][KademliaStore]`). On a found + valid + newer record, adopts
  /// the peer's OH list into the deposit fan-out set.
  Future<void> _handleRecordLookupAnswer(
    String channelId,
    List<int> payload,
  ) async {
    try {
      if (payload.isEmpty) return;
      final status = payload[0];
      if (status == 0 || payload.length < 2) {
        RpLog.debug(
          'RedPandaLightClient: rendezvous lookup for $channelId — no record',
        );
        return;
      }
      final record = RendezvousManager.recordFromStoreBytes(payload.sublist(1));
      final now = DateTime.now().millisecondsSinceEpoch;
      final peerOhs = await _rendezvous.applyResolvedRecord(
        channelId,
        record,
        now,
      );
      if (peerOhs == null || peerOhs.isEmpty) return;
      final changed = _replacePeerOhSet(channelId, peerOhs);
      if (changed) {
        _emitPeerOhUpdate(channelId, peerOhs);
        RpLog.info(
          'RedPandaLightClient: rendezvous recovery for $channelId adopted '
          '${peerOhs.length} peer OH(s) from the DHT record',
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

  /// Redundancy fixed at k=2 own mailboxes on disjoint nodes (T42). Not a
  /// configuration knob — hard-coded per the plan.
  static const int ohRedundancy = 2;

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
      for (final oh in own)
        if (oh.serverEndpoint != null) oh.serverEndpoint!,
    };
    final usedNodeIds = <String>{
      for (final oh in own)
        if (oh.serverEndpoint != null &&
            _peers[oh.serverEndpoint]?.discoveredNodeId != null)
          _peers[oh.serverEndpoint]!.discoveredNodeId!,
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
      final hasDisjoint = _peers.values.any(
        (p) =>
            p.isHandshakeVerified &&
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
  /// user decision 2026-07-20). It is deposited into EVERY known peer OH (one
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
    final pending = _pendingOhUpdates[channelId];
    if (pending == null) return;
    final sessionFuture = _ratchetSessions[channelId];
    final targets = _channelPeerOhSet[channelId];
    if (sessionFuture == null || targets == null || targets.isEmpty) {
      // No path to announce over — checked before the failover started, so
      // this only happens after a disconnect/reset; drop the stale entry.
      _pendingOhUpdates.remove(channelId);
      return;
    }
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
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

    // T45/T47d: deposit the announce into EVERY known peer OH over garlic (one
    // hop-disjoint route each), with the primary route requesting an R-ACK.
    // The stable message id lets the partner deduplicate the copies.
    final validTargets = targets
        .where((t) => t.ohId.length == GarlicHop.nodeIdLength)
        .toList(growable: false);
    if (validTargets.isEmpty) {
      _pendingOhUpdates.remove(channelId);
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
    if (pending.remainingSends <= 0) {
      _pendingOhUpdates.remove(channelId);
    }
  }

  /// Applies a fetched in-band `oh_update` (T21): the partner moved their
  /// mailbox. Authenticity is the ratchet decryption that already happened —
  /// only the partner holds the message keys. Duplicates (the announce is
  /// sent multiple times) are ignored.
  void _handlePeerOhUpdate(String channelId, Uint8List ohUpdateBytes) {
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
      return;
    }
    if (descriptors.isEmpty) return;
    final changed = _replacePeerOhSet(channelId, descriptors);
    if (!changed) return; // duplicate announce
    RpLog.info(
      'RedPandaLightClient: channel $channelId peer mailbox set updated to '
      '${descriptors.length} OH(s) (in-band oh_update)',
    );
    _emitPeerOhUpdate(channelId, descriptors);
  }

  /// Publishes a peer-OH-set change to the app layer (persists the new deposit
  /// fan-out set). Shared by the in-band `oh_update` path and T44 rendezvous
  /// recovery.
  void _emitPeerOhUpdate(String channelId, List<OHDescriptor> descriptors) {
    if (!_peerOhUpdateController.isClosed) {
      _peerOhUpdateController.add(
        PeerOhUpdate(channelId: channelId, descriptors: descriptors),
      );
    }
  }

  /// Re-registers [oh] with the same id and keypair to extend its TTL.
  /// On success, updates [OHRegistration.expiresAtMs] and emits an
  /// [OhMailboxUpdate] so the app layer can persist the new expiry.
  /// Returns true if the Full Node confirmed the renewal.
  Future<bool> renewOutboundHandle(OHRegistration oh) async {
    final activePeer = _peerForHandle(oh, 'renewOutboundHandle()');
    if (activePeer == null) {
      // _peerForHandle already logged the disconnected-host case.
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

    activePeer.sendCommand(150, Uint8List.fromList(request.writeToBuffer()));

    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      _registerResponses.abandon(completer);
      RpLog.info('RedPandaLightClient: renewOutboundHandle() timed out');
      return false;
    }

    final response = RegisterOhResponse.fromBuffer(responseBytes);
    if (response.status == Status.RATE_LIMIT) {
      // MS02b: max 5 registrations/min per connection. The renewal timer
      // fires every 5 minutes, so simply failing this cycle is backoff enough.
      RpLog.info('RedPandaLightClient: renewOutboundHandle() rate-limited');
      return false;
    }
    if (response.status != Status.OK) {
      RpLog.info(
        'RedPandaLightClient: renewOutboundHandle() non-OK status: ${response.status}',
      );
      return false;
    }

    oh.expiresAtMs = response.expiresAtMs.toInt();
    _ohMailboxUpdateController.add(
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
    signingBuffer.addByte(152); // OUTBOUND_FETCH_REQ
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
        _noteHostUnreachable(oh);
      }
      return [];
    }

    // Register completer for command 153 (OUTBOUND_FETCH_RES) before sending
    final completer = Completer<List<int>>();
    _pendingResponses[153] = completer;

    final buffer = request.writeToBuffer();
    RpLog.debug(
      'RedPandaLightClient: fetchMessages() serialized ${buffer.length} bytes',
    );
    activePeer.sendCommand(152, Uint8List.fromList(buffer));

    // Await the response
    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(fetchResponseTimeout);
      activePeer.consecutiveFetchTimeouts = 0;
    } on TimeoutException {
      _pendingResponses.remove(153);
      RpLog.info(
        'RedPandaLightClient: fetchMessages() timed out waiting for response',
      );
      _emitFetchStatus(oh, false, 'timeout');
      if (oh.serverEndpoint != null) {
        _noteHostUnreachable(oh);
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
    for (final item in response.items) {
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
          await _handleRecordLookupAnswer(recordLookupChannel, item.payload);
          continue;
        }
        // MS06: an outstanding ack tag marks this item as an R-ACK for one
        // of our sends — a plaintext RoutingAck, never channel-encrypted
        // (master spec MS06, Decision 3: correlation via ack_session_tag).
        final ackEntry = _ackTagStore.consume(tagHex);
        if (ackEntry != null) {
          _handleRoutingAck(ackEntry, item.payload);
          continue;
        }
        if (group != null) {
          // Groups issue no reply session tags (MS08, Decision 7) — a
          // tagged item that is not an outstanding R-ACK is foreign.
          RpLog.info(
            'RedPandaLightClient: dropping tagged mail item on group OH — '
            'not an outstanding R-ACK',
          );
          continue;
        }
        final tagChannel = _sessionTagStore.lookup(tagHex);
        if (tagChannel == null || tagChannel != oh.channelId) {
          RpLog.info(
            'RedPandaLightClient: dropping tagged mail item — session tag '
            '${tagChannel == null ? 'unknown or already consumed' : 'belongs to another channel'}',
          );
          continue;
        }
      } else {
        tagHex = null;
      }
      if (group != null) {
        await _handleGroupItem(group, item, messages, ackedGroupMessageIds);
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
          if (loopback != null && !loopback.isCompleted) loopback.complete();
          continue;
        }
        // T21: an in-band mailbox failover announcement — apply the new
        // peer OH and swallow the item (never a chat message).
        if (channelMessage.isOhUpdate) {
          _handlePeerOhUpdate(oh.channelId!, channelMessage.ohUpdate!);
          continue;
        }
        // MS08: a group handshake rides the 1:1 channel — surface it as an
        // event, never as a chat message.
        if (channelMessage.isGroupHandshake) {
          _emitGroupHandshake(oh.channelId!, channelMessage.groupHandshake!);
          continue;
        }
        // MS06: a Channel-ACK confirms the partner received our message —
        // surface it as a status update, never as a chat message.
        if (channelMessage.isChannelAck) {
          if (!_channelAckController.isClosed) {
            _channelAckController.add(
              ChannelAckUpdate(
                channelId: oh.channelId!,
                messageIdHex: _hexEncode(channelMessage.ackMessageId!),
                timestampMs: channelMessage.timestampMs,
              ),
            );
          }
          continue;
        }
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
      } catch (e) {
        RpLog.info('RedPandaLightClient: failed to decrypt mail item: $e');
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
      _ohMailboxUpdateController.add(
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
  void _handleRoutingAck(AckTagEntry entry, List<int> payload) {
    final RoutingAck ack;
    try {
      ack = RoutingAck.decode(payload);
    } on FormatException catch (e) {
      RpLog.info('RedPandaLightClient: dropping malformed R-ACK: $e');
      return;
    }
    final latencyMs = (DateTime.now().millisecondsSinceEpoch - entry.sentAtMs)
        .clamp(0, 1 << 31);
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
      return;
    }
    if (!_routingAckController.isClosed) {
      _routingAckController.add(
        RoutingAckUpdate.ack(
          channelId: entry.channelId,
          messageIdHex: entry.messageIdHex,
          status: ack.status,
          latencyMs: latencyMs,
          memberIdHex: entry.memberIdHex,
        ),
      );
    }
    RpLog.debug(
      'RedPandaLightClient: R-ACK for message ${entry.messageIdHex} '
      '(status ${ack.status}, ${latencyMs}ms)',
    );
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
    final peerOhId = _channelPeerOhIds[channelId];
    if (peerOhId == null || peerOhId.length != GarlicHop.nodeIdLength) {
      return;
    }
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
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
      ohEndpoint: _channelPeerOhEndpoints[channelId],
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
      ohId: peerOhId,
      payload: payload,
    );
    activePeer.sendCommand(142, packet);
  }

  // =========================================================================
  // Groups (Frontend MS08)
  // =========================================================================

  @override
  Stream<GroupStateUpdate> get groupStateUpdates =>
      _groupStateController.stream;

  @override
  Stream<GroupHandshakeEvent> get groupHandshakeEvents =>
      _groupHandshakeController.stream;

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
    if (_groupStateController.isClosed) return;
    _groupStateController.add(
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
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
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
      excludeAddresses: {submitVia.address, ?member.ohEndpoint},
      excludeNodeIds: {?submitVia.discoveredNodeId},
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
      submitVia.sendCommand(142, packet);
      return returnPath != null;
    }

    // Direct fallback, fire-and-forget (mirrors the channel-ACK fallback):
    // a lost deposit surfaces as a missing R-ACK and is re-sent.
    final flaschenpost = FlaschenpostPut()
      ..content = payload
      ..ohId = ohId;
    submitVia.sendCommand(
      141,
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
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
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
    final peerOhId = _channelPeerOhIds[channelId];
    if (peerOhId == null || peerOhId.length != GarlicHop.nodeIdLength) {
      throw StateError('sendGroupHandshake: channel $channelId has no peer OH');
    }
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
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
        ohId: peerOhId,
        payload: payload,
      );
      activePeer.sendCommand(142, packet);
      return;
    }

    // Direct fallback with want_response for a definite result — the app
    // layer retries the handshake on failure.
    final flaschenpost = FlaschenpostPut()
      ..content = payload
      ..ohId = peerOhId
      ..wantResponse = true;
    final completer = _putResponses.register();
    activePeer.sendCommand(
      141,
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
        if (!_channelAckController.isClosed) {
          _channelAckController.add(
            ChannelAckUpdate(
              channelId: group.groupId,
              messageIdHex: _hexEncode(channelMessage.ackMessageId!),
              timestampMs: channelMessage.timestampMs,
              memberIdHex: result.senderMemberIdHex,
            ),
          );
        }
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
          if (!_channelAckController.isClosed) {
            _channelAckController.add(
              ChannelAckUpdate(
                channelId: group.groupId,
                messageIdHex: _hexEncode(channelMessage.ackMessageId!),
                timestampMs: channelMessage.timestampMs,
                memberIdHex: result.senderMemberIdHex,
              ),
            );
          }
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
    if (_groupHandshakeController.isClosed) return;
    if (handshake.isProposal) {
      _groupHandshakeController.add(
        GroupHandshakeEvent(
          channelId: channelId,
          isProposal: true,
          groupIdHex: handshake.proposalGroupIdHex!,
          groupName: handshake.proposalGroupName,
          adminMemberIdHex: handshake.proposalAdminMemberIdHex,
        ),
      );
    } else {
      _groupHandshakeController.add(
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
    signingBuffer.addByte(156); // OUTBOUND_ACK_FETCH_REQ
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
    _pendingResponses[157] = completer;

    activePeer.sendCommand(156, Uint8List.fromList(request.writeToBuffer()));

    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      _pendingResponses.remove(157);
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
      final connected = _peers.values.any((p) => p.isHandshakeVerified);
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

  /// (Re-)schedules the next poll cycle in [delay]. Cycles run at a fixed
  /// rate: each cycle's duration is subtracted from the then-current
  /// [_pollInterval] (never below [minPollGap]), so slow cycles do not
  /// stretch the effective cadence.
  void _schedulePoll(Duration delay) {
    if (!_pollingEnabled) return;
    _pollingTimer?.cancel();
    _nextPollAt = DateTime.now().add(delay);
    _pollingTimer = Timer(delay, () async {
      final cycleStarted = DateTime.now();
      try {
        await _runPollCycle();
      } catch (e) {
        // Never let one bad cycle kill the loop — without this, an
        // exception escaping the cycle would end polling until restart.
        RpLog.info('RedPandaLightClient: poll cycle failed: $e');
      } finally {
        final elapsed = DateTime.now().difference(cycleStarted);
        final interval = _pollInterval;
        _schedulePoll(
          elapsed >= interval - minPollGap ? minPollGap : interval - elapsed,
        );
      }
    });
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
        !_pollInProgress &&
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
    try {
      for (final oh in List.of(_registeredOHs)) {
        try {
          final messages = await fetchMessages(oh);
          if (messages.isNotEmpty) {
            // The partner is active — keep the fast cadence going (T27).
            _lastChatActivity = DateTime.now();
            fetched += messages.length;
          }
          for (final msg in messages) {
            _incomingMessageController.add(msg);
          }
        } catch (e) {
          RpLog.info('RedPandaLightClient: Polling error: $e');
          _emitFetchStatus(oh, false, 'error: $e');
        }
      }
      // T44: (re)publish rendezvous records that are due or that never got a
      // publish through (e.g. no garlic hops were known at registration time).
      _republishDueRendezvousRecords();
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
      final expired = _ackTagStore.takeExpired(ackTimeout);
      for (final entry in expired) {
        _nodeScorer.recordFailure(entry.hopNodeIdsHex);
        // MS08: an unconfirmed rotation box simply stays pending — the
        // periodic retry re-sends it; no message status to update.
        if (entry.isRotation) continue;
        if (!_routingAckController.isClosed) {
          _routingAckController.add(
            RoutingAckUpdate.timeout(
              channelId: entry.channelId,
              messageIdHex: entry.messageIdHex,
              memberIdHex: entry.memberIdHex,
            ),
          );
        }
        RpLog.info(
          'RedPandaLightClient: no R-ACK for message '
          '${entry.messageIdHex} within ${ackTimeout.inSeconds}s',
        );
      }
      if (expired.isNotEmpty) {
        _emitNodeScores();
      }
    } finally {
      _pollInProgress = false;
      // Cadence telemetry (T27): counts and durations only — no handle or
      // channel identifiers, safe for field logging.
      RpLog.info(
        'RedPandaLightClient: poll cycle fetched $fetched message(s) from '
        '${_registeredOHs.length} OH(s) in '
        '${DateTime.now().difference(started).inMilliseconds}ms '
        '(interval ${_pollInterval.inSeconds}s)',
      );
    }
  }

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

/// A single peer OH mailbox in the deposit fan-out set (T42): the id a
/// FlaschenpostPut is addressed to, plus the host endpoint (used for garlic
/// hop exclusion and status display). The auth public key is not needed to
/// deposit, so it is intentionally not carried here.
class _PeerOh {
  final List<int> ohId;
  final String? endpoint;
  const _PeerOh({required this.ohId, this.endpoint});
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
