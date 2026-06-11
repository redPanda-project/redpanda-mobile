import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:pointycastle/export.dart' as pc;

import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
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

  static const List<String> defaultSeeds = [
    '65.109.130.115:59558',
    'localhost:59558',
    // 'localhost:59559',
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

  RedPandaLightClient({
    required this.selfNodeId,
    required this.selfKeys,
    List<String> seeds = defaultSeeds,
    SocketFactory? socketFactory,
    // Injectable repository for testing? For now we create it.
    PeerRepository? peerRepository,
  }) : _socketFactory = socketFactory ?? ((h, p) => Socket.connect(h, p)),
       _peerRepository = peerRepository ?? InMemoryPeerRepository() {
    _peerRepository.load().then((_) {
      _peerRepository.addAll(seeds);
      // Fast boot: Trigger immediate check after load
      _runConnectionCheck();
    });
  }

  /// Called when app goes to background
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
  void onResume() {
    // _isBackgrounded = false;
    _isBadInternetDetected = false; // transform optimism
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _runConnectionCheck(),
    );
    _runConnectionCheck(); // Immediate
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
    print('RedPandaLightClient: Starting connection routine...');

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

    print(
      'RedPandaLightClient: Running connection check. Known peers: ${_peerRepository.knownAddresses.length}',
    );

    // 1. Cleanup disconnected
    _peers.removeWhere((address, peer) {
      if (peer.isDisconnected) {
        print('RedPandaLightClient: Removing disconnected peer $address');
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
        print(
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

        print(
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
        print('RedPandaLightClient: No peers to connect to. Bad Internet?');
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
          onNodeIdDiscovered: (nodeId) {
            _peerRepository.updatePeer(address, nodeId: nodeId);
          },
          onDisconnect: () {
            if (_intentionalDisconnects.contains(address)) {
              print(
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
            print(
              'RedPandaLightClient: Received ${peers.length} peers from $address',
            );
            _peerRepository.addAll(peers);
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
        print('RedPandaLightClient: Failed to initiate peer $address: $e');
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
    if (seconds > 300) seconds = 300; // Cap at 5 mins

    _nextRetryTime[address] = DateTime.now().add(Duration(seconds: seconds));
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
    await _incomingMessageController.close();
    await _ohMailboxUpdateController.close();
    _updateStatus(ConnectionStatus.disconnected);
  }

  // --- OH Registration & Message state ---
  final List<OHRegistration> _registeredOHs = [];
  final _incomingMessageController =
      StreamController<DecryptedMessage>.broadcast();
  final _ohMailboxUpdateController =
      StreamController<OhMailboxUpdate>.broadcast();
  Timer? _pollingTimer;
  Timer? _renewalTimer;

  // Guards against overlapping timer ticks: fetch/renew share
  // _pendingResponses (keyed by command byte), so cycles must not race.
  bool _pollInProgress = false;
  bool _renewalInProgress = false;

  /// OHs are renewed when they expire within this window.
  static const Duration renewalThreshold = Duration(days: 1);

  /// Interval for the renewal check timer.
  static const Duration renewalCheckInterval = Duration(minutes: 5);

  /// Pending response completers keyed by command byte.
  final Map<int, Completer<List<int>>> _pendingResponses = {};

  void _handleCommandResponse(int command, List<int> payload) {
    final completer = _pendingResponses.remove(command);
    if (completer != null && !completer.isCompleted) {
      completer.complete(payload);
    }
  }

  /// Channel encryption keys indexed by channel ID.
  /// Populated externally or via addChannelKeys().
  final Map<String, List<int>> _channelEncryptionKeys = {};
  final Map<String, List<int>> _channelPeerOhIds = {};

  /// Register channel encryption info so sendMessage/fetchMessages can use it.
  @override
  void addChannelKeys(
    String channelId,
    List<int> encryptionKey, {
    List<int>? peerOhId,
  }) {
    _channelEncryptionKeys[channelId] = encryptionKey;
    if (peerOhId != null) {
      _channelPeerOhIds[channelId] = peerOhId;
    }
  }

  @override
  Stream<DecryptedMessage> get incomingMessages =>
      _incomingMessageController.stream;

  @override
  Stream<OhMailboxUpdate> get ohMailboxUpdates =>
      _ohMailboxUpdateController.stream;

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
  Future<String> sendMessage(String channelId, String content) async {
    final random = Random.secure();
    final messageId =
        '${DateTime.now().millisecondsSinceEpoch}-${random.nextInt(999999)}';

    final encKey = _channelEncryptionKeys[channelId];
    if (encKey == null) {
      // Channel keys not yet registered in the network layer. The message
      // stays pending in the app database; the retry queue re-sends it once
      // the keys have been registered.
      throw StateError(
        'sendMessage: channel $channelId has no encryption keys registered',
      );
    }

    // 1. Generate random IV (16 bytes)
    final iv = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );

    // 2. Encrypt with AES-256-CTR
    final plaintext = Uint8List.fromList(utf8.encode(content));
    final cipher = pc.CTRStreamCipher(pc.AESEngine());
    cipher.init(
      true,
      pc.ParametersWithIV(pc.KeyParameter(Uint8List.fromList(encKey)), iv),
    );
    final ciphertext = cipher.process(plaintext);

    // 3. Compute HMAC-SHA256 over [IV || ciphertext] for authenticated encryption
    final macInput = Uint8List(iv.length + ciphertext.length);
    macInput.setRange(0, iv.length, iv);
    macInput.setRange(iv.length, macInput.length, ciphertext);

    final hmac = pc.HMac(pc.SHA256Digest(), 64)
      ..init(pc.KeyParameter(Uint8List.fromList(encKey)));
    final mac = hmac.process(macInput);

    // 4. Build payload: [IV (16 bytes)][ciphertext][HMAC-SHA256 (32 bytes)]
    final payload = Uint8List(iv.length + ciphertext.length + mac.length);
    payload.setRange(0, iv.length, iv);
    payload.setRange(iv.length, iv.length + ciphertext.length, ciphertext);
    payload.setRange(iv.length + ciphertext.length, payload.length, mac);

    // 5. Build FlaschenpostPut with target OH mailbox id for direct routing
    final peerOhId = _channelPeerOhIds[channelId];
    final flaschenpost = FlaschenpostPut()
      ..content = payload
      ..ohId = peerOhId ?? Uint8List(0);

    // 6. Send to a connected peer (best available)
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;

    if (activePeer == null) {
      // No connected Full Node — the retry queue will try again later.
      throw StateError('sendMessage: no active peer available');
    }

    final buffer = flaschenpost.writeToBuffer();
    print(
      'RedPandaLightClient: sendMessage() serialized ${buffer.length} bytes for channel $channelId',
    );
    activePeer.sendCommand(141, Uint8List.fromList(buffer));

    return messageId;
  }

  @override
  Future<OHRegistration> registerOutboundHandle({String? channelId}) async {
    final keypair = OHKeypair.generate();
    final random = Random.secure();
    final ohId = Uint8List.fromList(
      List<int>.generate(20, (_) => random.nextInt(256)),
    );

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 7));
    final request = _buildRegisterRequest(ohId, keypair, now, expiresAt);

    // Send to best active peer
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;

    if (activePeer != null) {
      final buffer = request.writeToBuffer();
      print(
        'RedPandaLightClient: registerOutboundHandle() serialized ${buffer.length} bytes',
      );
      activePeer.sendCommand(150, Uint8List.fromList(buffer));
    } else {
      print(
        'RedPandaLightClient: registerOutboundHandle() no active peer available',
      );
    }

    final registration = OHRegistration(
      ohId: ohId.toList(),
      keypair: keypair,
      expiresAtMs: expiresAt.millisecondsSinceEpoch,
      channelId: channelId,
      serverEndpoint: activePeer?.address,
    );

    _registeredOHs.add(registration);
    _startPolling();

    return registration;
  }

  /// Builds a signed RegisterOhRequest. Signing bytes:
  /// [CMD_BYTE(150) | oh_id | requested_expires_at(8 BE) | timestamp_ms(8 BE) | nonce]
  RegisterOhRequest _buildRegisterRequest(
    List<int> ohId,
    OHKeypair keypair,
    DateTime now,
    DateTime expiresAt,
  ) {
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

    final signature = keypair.sign(Uint8List.fromList(signingBuffer.toBytes()));

    return RegisterOhRequest()
      ..ohId = ohId
      ..ohAuthPublicKey = keypair.publicKeyBytes
      ..requestedExpiresAt = _toInt64(expiresAt.millisecondsSinceEpoch)
      ..timestampMs = _toInt64(now.millisecondsSinceEpoch)
      ..nonce = nonce
      ..signature = signature;
  }

  /// Re-registers [oh] with the same id and keypair to extend its TTL.
  /// On success, updates [OHRegistration.expiresAtMs] and emits an
  /// [OhMailboxUpdate] so the app layer can persist the new expiry.
  /// Returns true if the Full Node confirmed the renewal.
  Future<bool> renewOutboundHandle(OHRegistration oh) async {
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
    if (activePeer == null) {
      print('RedPandaLightClient: renewOutboundHandle() no active peer');
      return false;
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 7));
    final request = _buildRegisterRequest(oh.ohId, oh.keypair, now, expiresAt);

    // Register completer for command 151 (OUTBOUND_REGISTER_OH_RES)
    final completer = Completer<List<int>>();
    _pendingResponses[151] = completer;

    activePeer.sendCommand(150, Uint8List.fromList(request.writeToBuffer()));

    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      _pendingResponses.remove(151);
      print('RedPandaLightClient: renewOutboundHandle() timed out');
      return false;
    }

    final response = RegisterOhResponse.fromBuffer(responseBytes);
    if (response.status != Status.OK) {
      print(
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
            print('RedPandaLightClient: OH renewal error: $e');
          }
        }
      }
    } finally {
      _renewalInProgress = false;
    }
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async {
    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final now = DateTime.now();

    // Build signing bytes: [CMD_BYTE(152) | oh_id | timestamp_ms(8 BE) | nonce | limit(4 BE) | cursor(8 BE)]
    final signingBuffer = BytesBuilder();
    signingBuffer.addByte(152); // OUTBOUND_FETCH_REQ
    signingBuffer.add(oh.ohId);
    signingBuffer.add(_int64Bytes(now.millisecondsSinceEpoch));
    signingBuffer.add(nonce);
    final limitData = ByteData(4);
    limitData.setInt32(0, 50, Endian.big);
    signingBuffer.add(limitData.buffer.asUint8List());
    signingBuffer.add(_int64Bytes(oh.lastCursor));

    final signature = oh.keypair.sign(
      Uint8List.fromList(signingBuffer.toBytes()),
    );

    final request = FetchRequest()
      ..ohId = oh.ohId
      ..limit = 50
      ..timestampMs = _toInt64(now.millisecondsSinceEpoch)
      ..nonce = nonce
      ..signature = signature;

    if (oh.lastCursor != 0) {
      request.cursor = fixnum.Int64(oh.lastCursor);
    }

    // Send to best active peer
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;

    if (activePeer == null) {
      print('RedPandaLightClient: fetchMessages() no active peer available');
      return [];
    }

    // Register completer for command 153 (OUTBOUND_FETCH_RES) before sending
    final completer = Completer<List<int>>();
    _pendingResponses[153] = completer;

    final buffer = request.writeToBuffer();
    print(
      'RedPandaLightClient: fetchMessages() serialized ${buffer.length} bytes',
    );
    activePeer.sendCommand(152, Uint8List.fromList(buffer));

    // Await the response
    final List<int> responseBytes;
    try {
      responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
      );
    } on TimeoutException {
      _pendingResponses.remove(153);
      print(
        'RedPandaLightClient: fetchMessages() timed out waiting for response',
      );
      return [];
    }

    // Parse FetchResponse protobuf
    final response = FetchResponse.fromBuffer(responseBytes);
    print(
      'RedPandaLightClient: fetchMessages() status=${response.status} items=${response.items.length}',
    );

    if (response.status != Status.OK) {
      print(
        'RedPandaLightClient: fetchMessages() non-OK status: ${response.status}',
      );
      return [];
    }

    if (response.mailboxOverflow) {
      print(
        'RedPandaLightClient: mailbox overflow detected for OH '
        '${_hexEncode(oh.ohId)} — older messages may have been lost',
      );
    }

    // Update cursor for next fetch
    final previousCursor = oh.lastCursor;
    oh.lastCursor = response.nextCursor.toInt();

    // Look up the channel encryption key for this OH
    final encKey = oh.channelId != null
        ? _channelEncryptionKeys[oh.channelId]
        : null;

    if (encKey == null) {
      print(
        'RedPandaLightClient: fetchMessages() no encryption key for channelId=${oh.channelId}',
      );
      return [];
    }

    // Decrypt each MailItem
    final messages = <DecryptedMessage>[];
    for (final item in response.items) {
      try {
        final content = _decryptPayload(item.payload, encKey);
        messages.add(
          DecryptedMessage(
            id: item.messageId
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
            content: content,
            receivedAtMs: item.receivedAtMs.toInt(),
            channelId: oh.channelId,
          ),
        );
      } catch (e) {
        print('RedPandaLightClient: failed to decrypt mail item: $e');
      }
    }

    // Acknowledge the fetched batch so the Full Node can delete it.
    // Failures are tolerated: items are re-delivered on the next fetch and
    // deduplicated by message_id in the app layer.
    if (response.items.isNotEmpty) {
      await ackFetch(oh, response.nextCursor.toInt());
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

  /// Sends an AckFetchRequest for [oh] confirming receipt of all mail items
  /// up to and including [ackedSequenceId]; the Full Node deletes them.
  /// Returns true if the node confirmed the acknowledgement.
  Future<bool> ackFetch(OHRegistration oh, int ackedSequenceId) async {
    final activePeer = _peers.values
        .where((p) => p.isHandshakeVerified)
        .firstOrNull;
    if (activePeer == null) {
      print('RedPandaLightClient: ackFetch() no active peer available');
      return false;
    }

    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final now = DateTime.now();

    // Signing bytes: [CMD_BYTE(156) | oh_id | acked_sequence_id(8 BE) | timestamp_ms(8 BE) | nonce]
    final signingBuffer = BytesBuilder();
    signingBuffer.addByte(156); // OUTBOUND_ACK_FETCH_REQ
    signingBuffer.add(oh.ohId);
    signingBuffer.add(_int64Bytes(ackedSequenceId));
    signingBuffer.add(_int64Bytes(now.millisecondsSinceEpoch));
    signingBuffer.add(nonce);

    final signature = oh.keypair.sign(
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
      print('RedPandaLightClient: ackFetch() timed out waiting for response');
      return false;
    }

    final response = AckFetchResponse.fromBuffer(responseBytes);
    if (response.status != Status.OK) {
      print(
        'RedPandaLightClient: ackFetch() non-OK status: ${response.status}',
      );
      return false;
    }
    return true;
  }

  static String _hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Decrypts an encrypted payload: [IV(16)][ciphertext][HMAC-SHA256(32)]
  String _decryptPayload(List<int> payload, List<int> encKey) {
    if (payload.length < 49) {
      throw ArgumentError('Payload too short: ${payload.length} bytes');
    }

    final iv = Uint8List.fromList(payload.sublist(0, 16));
    final ciphertext = Uint8List.fromList(
      payload.sublist(16, payload.length - 32),
    );
    final mac = Uint8List.fromList(payload.sublist(payload.length - 32));

    // Verify HMAC-SHA256 over [IV || ciphertext]
    final macInput = Uint8List(iv.length + ciphertext.length);
    macInput.setRange(0, iv.length, iv);
    macInput.setRange(iv.length, macInput.length, ciphertext);

    final hmac = pc.HMac(pc.SHA256Digest(), 64)
      ..init(pc.KeyParameter(Uint8List.fromList(encKey)));
    final expectedMac = hmac.process(macInput);

    bool macValid = mac.length == expectedMac.length;
    for (int i = 0; macValid && i < mac.length; i++) {
      macValid = mac[i] == expectedMac[i];
    }
    if (!macValid) {
      throw StateError('HMAC verification failed');
    }

    // AES-256-CTR decrypt
    final cipher = pc.CTRStreamCipher(pc.AESEngine());
    cipher.init(
      false,
      pc.ParametersWithIV(pc.KeyParameter(Uint8List.fromList(encKey)), iv),
    );
    final plaintext = cipher.process(ciphertext);

    return utf8.decode(plaintext);
  }

  void _startPolling() {
    _pollingTimer ??= Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_pollInProgress) return; // previous cycle still running
      _pollInProgress = true;
      try {
        for (final oh in List.of(_registeredOHs)) {
          try {
            final messages = await fetchMessages(oh);
            for (final msg in messages) {
              _incomingMessageController.add(msg);
            }
          } catch (e) {
            print('RedPandaLightClient: Polling error: $e');
          }
        }
      } finally {
        _pollInProgress = false;
      }
    });
    _renewalTimer ??= Timer.periodic(
      renewalCheckInterval,
      (_) => checkAndRenewExpiringHandles(),
    );
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
}
