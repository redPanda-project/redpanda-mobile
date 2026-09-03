import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/client/worker_replay_state.dart';
import 'package:redpanda_light_client/src/client_facade.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/channel_doctor_report.dart';
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/loopback_result.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/models/peer_stats_snapshot.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/streams/seeded_stream.dart';

/// A facade that implements [RedPandaClient] but proxies all operations
/// to a background [Isolate] to prevent UI jank.
class RedPandaIsolateClient implements RedPandaClient {
  final NodeId? _explicitNodeId;
  final KeyPair? _explicitKeys;
  final List<String> seeds;

  // Isolate? _isolate; // Kept only if we need to kill it explicitly
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Completer<void> _isolateReady = Completer<void>();

  // Supervision: an unhandled error in the worker isolate is fatal for the
  // isolate (errorsAreFatal default) and would otherwise silently kill all
  // networking — timers, reconnects, polling — until the app restarts.
  // We watch onExit/onError and respawn the worker with backoff.
  ReceivePort? _exitPort;
  ReceivePort? _errorPort;
  Isolate? _isolate;
  bool _disposed = false;
  int _spawnGeneration = 0;
  int _respawnAttempts = 0;
  bool _respawnScheduled = false;
  bool _connectRequested = false;
  bool _lifecyclePaused = false;

  // Identity for CmdInit; resolved once on the main isolate so a respawned
  // worker keeps the same node identity instead of generating a fresh one.
  NodeId? _initNodeId;
  KeyPair? _initKeys;

  // Replay projection: the last state-establishing command per key, kept
  // current from the state channel, so a respawned worker is transparently
  // re-initialized without stale crypto state.
  final WorkerReplayState _replay = WorkerReplayState();

  /// Worker entry point override — exists only so tests can inject a fake
  /// worker; must be a top-level or static function.
  final void Function(SendPort)? _workerEntryPointOverride;

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  final _peerStatsController = StreamController<PeerStatsSnapshot>.broadcast();
  PeerStatsSnapshot? _lastSnapshot;

  final _incomingMessageController =
      StreamController<DecryptedMessage>.broadcast();

  /// The single state channel: everything the worker publishes about changed
  /// state arrives as one [EventStateUpdate] and is forwarded here unchanged.
  final _stateController = StreamController<StateUpdate>.broadcast();

  // Pending OH registrations awaiting their isolate response, by requestId.
  final Map<int, Completer<OHRegistration>> _pendingOhRegistrations = {};

  // Pending sends awaiting their isolate response, by requestId.
  final Map<int, Completer<String>> _pendingSends = {};

  // Pending group operations (rotate/retry/handshake/rename), by requestId.
  final Map<int, Completer<void>> _pendingGroupOps = {};

  // Pending loopback self-tests (T20), by requestId.
  final Map<int, Completer<LoopbackResult>> _pendingLoopbackTests = {};

  // Pending connection-doctor runs (T25), by requestId.
  final Map<int, Completer<ChannelDoctorReport>> _pendingChannelDoctors = {};
  int _nextRequestId = 0;

  // Cache last known status
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  int _currentPeerCount = 0;

  RedPandaIsolateClient({
    NodeId? selfNodeId,
    KeyPair? selfKeys,
    this.seeds = const [],
    void Function(SendPort)? workerEntryPoint,
  }) : _explicitNodeId = selfNodeId,
       _explicitKeys = selfKeys,
       _workerEntryPointOverride = workerEntryPoint {
    _startIsolate();
  }

  Future<void> _startIsolate() async {
    _receivePort.listen((message) {
      if (message is SendPort) {
        _onWorkerReady(message);
      } else if (message is IsolateEvent) {
        _handleEvent(message);
      }
    });
    await _spawnWorker();
  }

  Future<void> _spawnWorker() async {
    if (_disposed) return;
    _exitPort?.close();
    _errorPort?.close();
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    _exitPort = exitPort;
    _errorPort = errorPort;
    final generation = ++_spawnGeneration;

    errorPort.listen((message) {
      // [errorDescription, stackTrace] from the dying worker.
      RpLog.info('RedPandaIsolateClient: worker error: $message');
    });
    exitPort.listen((_) {
      if (generation != _spawnGeneration) return; // event from an old worker
      RpLog.info('RedPandaIsolateClient: worker isolate died.');
      _onWorkerDied();
    });

    try {
      _isolate = await Isolate.spawn(
        _workerEntryPointOverride ?? _isolateEntryPoint,
        _receivePort.sendPort,
        debugName: 'RedPandaNetworkWorker',
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
      );
      if (_disposed) {
        _isolate?.kill(priority: Isolate.immediate);
      }
    } catch (e) {
      RpLog.info('RedPandaIsolateClient: Failed to spawn isolate: $e');
      _onWorkerDied();
    }
  }

  /// Permanently shuts down the worker isolate and the supervision (no
  /// further respawns). Used by tests; the app keeps the client alive for
  /// its whole lifetime.
  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _exitPort?.close();
    _errorPort?.close();
    _receivePort.close();
    _sendPort = null;
    _failPendingRequests();
  }

  Future<void> _onWorkerReady(SendPort port) async {
    _respawnAttempts = 0;
    _initKeys ??= _explicitKeys ?? await KeyPair.generate();
    _initNodeId ??= _explicitNodeId ?? NodeId.fromPublicKey(_initKeys!);
    _sendPort = port;
    port.send(CmdInit(nodeId: _initNodeId, keyPair: _initKeys, seeds: seeds));
    _replayState(port);
    if (!_isolateReady.isCompleted) {
      _isolateReady.complete();
    }
  }

  void _onWorkerDied() {
    if (_disposed) return;
    _sendPort = null;
    _failPendingRequests();
    if (_respawnScheduled) return;
    _respawnScheduled = true;
    final delayMs = math.min(
      30000,
      500 * math.pow(2, _respawnAttempts).toInt(),
    );
    _respawnAttempts++;
    RpLog.info('RedPandaIsolateClient: respawning worker in ${delayMs}ms');
    Timer(Duration(milliseconds: delayMs), () {
      _respawnScheduled = false;
      if (_sendPort != null) return; // already alive again
      _spawnWorker();
    });
  }

  /// Fails every request still waiting on the dead worker so callers (UI,
  /// retry queue) get an error now instead of hanging into their timeout.
  void _failPendingRequests() {
    StateError error() => StateError('network worker restarted; request lost');
    for (final completer in _pendingSends.values) {
      if (!completer.isCompleted) completer.completeError(error());
    }
    _pendingSends.clear();
    for (final completer in _pendingGroupOps.values) {
      if (!completer.isCompleted) completer.completeError(error());
    }
    _pendingGroupOps.clear();
    for (final completer in _pendingOhRegistrations.values) {
      if (!completer.isCompleted) completer.completeError(error());
    }
    _pendingOhRegistrations.clear();
    for (final completer in _pendingLoopbackTests.values) {
      if (!completer.isCompleted) {
        completer.complete(
          const LoopbackResult.failed('network worker restarted'),
        );
      }
    }
    _pendingLoopbackTests.clear();
    for (final completer in _pendingChannelDoctors.values) {
      if (!completer.isCompleted) {
        completer.complete(_doctorErrorReport('network worker restarted'));
      }
    }
    _pendingChannelDoctors.clear();
  }

  /// Single-stage failure report used when the worker never answers a doctor
  /// run (respawn, lost response).
  static ChannelDoctorReport _doctorErrorReport(String detail) =>
      ChannelDoctorReport([
        DoctorStage(
          name: 'Connection doctor',
          status: DoctorStatus.fail,
          durationMs: 0,
          detail: detail,
        ),
      ]);

  /// Re-establishes the worker state after a respawn: known peers, channel
  /// keys (with the latest ratchet/garlic state), OH registrations, groups,
  /// node scores and the connect/lifecycle flags.
  void _replayState(SendPort port) {
    for (final cmd in _replay.replayCommands()) {
      port.send(cmd);
    }
    if (_connectRequested) {
      port.send(CmdConnect());
    }
    if (_lifecyclePaused) {
      port.send(CmdLifecyclePause());
    }
  }

  void _handleEvent(IsolateEvent event) {
    if (event is EventConnectionStatus) {
      _currentStatus = event.status;
      _connectionStatusController.add(event.status);
    } else if (event is EventPeerCount) {
      _currentPeerCount = event.count;
      _peerCountController.add(event.count);
    } else if (event is EventPeerStatsSnapshot) {
      final snapshot = PeerStatsSnapshot(
        allPeers: event.allPeers,
        activePeerAddresses: event.activePeerAddresses.toSet(),
        connectingPeerAddresses: event.connectingPeerAddresses.toSet(),
      );
      _lastSnapshot = snapshot;
      _peerStatsController.add(snapshot);
    } else if (event is EventIncomingMessage) {
      _incomingMessageController.add(event.message);
    } else if (event is EventOhRegistered) {
      // Keep the registration replayable for a respawned worker.
      _replay.recordOutboundHandle(
        CmdRestoreOutboundHandle(
          ohId: event.ohId,
          privateKeyBytes: event.privateKeyBytes,
          expiresAtMs: event.expiresAtMs,
          channelId: event.channelId,
          serverEndpoint: event.serverEndpoint,
        ),
      );
      final completer = _pendingOhRegistrations.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        try {
          // Completing with a future is fine: errors from the async keypair
          // restore propagate into the completer's future.
          completer.complete(
            OHKeypair.fromPrivateKeyBytes(
              Uint8List.fromList(event.privateKeyBytes),
            ).then(
              (keypair) => OHRegistration(
                ohId: event.ohId,
                keypair: keypair,
                expiresAtMs: event.expiresAtMs,
                channelId: event.channelId,
                serverEndpoint: event.serverEndpoint,
              ),
            ),
          );
        } catch (e) {
          completer.completeError(e);
        }
      }
    } else if (event is EventOhRegisterFailed) {
      final completer = _pendingOhRegistrations.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          event.rateLimited ? RateLimitException() : StateError(event.error),
        );
      }
    } else if (event is EventMessageSent) {
      final completer = _pendingSends.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(event.messageId);
      }
    } else if (event is EventLoopbackResult) {
      final completer = _pendingLoopbackTests.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(
          event.success
              ? LoopbackResult.ok(
                  roundtripMs: event.roundtripMs!,
                  hopCount: event.hopCount,
                )
              : LoopbackResult.failed(
                  event.error ?? 'unknown error',
                  hopCount: event.hopCount,
                ),
        );
      }
    } else if (event is EventChannelDoctorResult) {
      final completer = _pendingChannelDoctors.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(event.report);
      }
    } else if (event is EventMessageSendFailed) {
      final completer = _pendingSends.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(_rebuildSendError(event));
      }
    } else if (event is EventGroupOpDone) {
      final completer = _pendingGroupOps.remove(event.requestId);
      if (completer != null && !completer.isCompleted) {
        if (event.error == null) {
          completer.complete();
        } else {
          final failedMemberIds = event.failedMemberIds;
          final statusCode = event.statusCode;
          completer.completeError(
            failedMemberIds != null
                ? GroupSendException(failedMemberIds, event.error)
                : statusCode != null
                ? DepositException(statusCode)
                : StateError(event.error!),
          );
        }
      }
    } else if (event is EventStateUpdate) {
      // ONE branch for every state change: keep the worker-restore projection
      // current, then republish unchanged. Adding a state event costs nothing
      // here.
      _replay.apply(event.update);
      if (!_stateController.isClosed) {
        _stateController.add(event.update);
      }
    } else if (event is EventLog) {
      // The worker forwards only LogLevel.info lines (privacy-sensitive
      // debug details never leave the worker), so re-emit at info here —
      // the app's sink decides whether they become visible (T17).
      RpLog.info('[worker] ${event.message}');
    }
  }

  void _send(IsolateCommand cmd) {
    if (_sendPort != null) {
      _sendPort!.send(cmd);
    } else {
      // If isolate isn't ready, maybe queue? For now just log.
      RpLog.debug(
        'RedPandaIsolateClient: Warning - Isolate not ready. Dropping command $cmd',
      );
    }
  }

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      seededStream(() => [_currentStatus], _connectionStatusController.stream);

  @override
  Stream<int> get peerCountStream =>
      seededStream(() => [_currentPeerCount], _peerCountController.stream);

  @override
  Stream<PeerStatsSnapshot> get peerStatsStream => seededStream(
    () => _lastSnapshot == null ? const [] : [_lastSnapshot!],
    _peerStatsController.stream,
  );

  @override
  Stream<DecryptedMessage> get incomingMessages =>
      _incomingMessageController.stream;

  @override
  Future<void> connect() async {
    _connectRequested = true;
    await _isolateReady.future;
    _send(CmdConnect());
  }

  @override
  Future<void> disconnect() async {
    _connectRequested = false;
    _send(CmdDisconnect());
  }

  @override
  Future<void> addPeer(String address) async {
    _replay.recordPeer(address);
    _send(CmdAddPeer(address));
  }

  @override
  Future<String> sendMessage(
    String channelId,
    String content, {
    String? messageId,
  }) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<String>();
    _pendingSends[requestId] = completer;
    _send(CmdSendMessage(requestId, channelId, content, messageId: messageId));
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingSends.remove(requestId);
        throw TimeoutException(
          'sendMessage timed out',
          const Duration(seconds: 15),
        );
      },
    );
  }

  @override
  Future<LoopbackResult> runLoopbackTest(String channelId) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<LoopbackResult>();
    _pendingLoopbackTests[requestId] = completer;
    _send(CmdRunLoopbackTest(requestId, channelId));
    // The worker-side test times out after RedPandaLightClient.loopbackTimeout
    // (60 s); this outer guard only covers a lost worker response.
    return completer.future.timeout(
      const Duration(seconds: 75),
      onTimeout: () {
        _pendingLoopbackTests.remove(requestId);
        return const LoopbackResult.failed('no response from network worker');
      },
    );
  }

  @override
  Future<ChannelDoctorReport> runChannelDoctor(String channelId) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<ChannelDoctorReport>();
    _pendingChannelDoctors[requestId] = completer;
    _send(CmdRunChannelDoctor(requestId, channelId));
    // The doctor's loopback stage is bounded by loopbackTimeout (60 s); this
    // outer guard only covers a lost worker response.
    return completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _pendingChannelDoctors.remove(requestId);
        return _doctorErrorReport('no response from network worker');
      },
    );
  }

  @override
  Future<OHRegistration> registerOutboundHandle({String? channelId}) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<OHRegistration>();
    _pendingOhRegistrations[requestId] = completer;
    _send(CmdRegisterOutboundHandle(requestId, channelId: channelId));
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingOhRegistrations.remove(requestId);
        throw TimeoutException(
          'OH registration timed out',
          const Duration(seconds: 15),
        );
      },
    );
  }

  @override
  Future<List<DecryptedMessage>> fetchMessages(OHRegistration oh) async {
    // Polling is handled internally by the client in the isolate; fetched
    // messages are delivered via [incomingMessages]. This facade method
    // therefore has nothing to return directly.
    return [];
  }

  @override
  Future<void> restoreOutboundHandle(OHRegistration registration) async {
    await _isolateReady.future;
    final cmd = CmdRestoreOutboundHandle(
      ohId: registration.ohId,
      privateKeyBytes: registration.keypair.privateKeyBytes.toList(),
      expiresAtMs: registration.expiresAtMs,
      channelId: registration.channelId,
      serverEndpoint: registration.serverEndpoint,
      lastCursor: registration.lastCursor,
    );
    _replay.recordOutboundHandle(cmd);
    _send(cmd);
  }

  @override
  Stream<StateUpdate> get stateUpdates => _stateController.stream;

  @override
  Future<void> ensureOhRedundancy(String channelId) async {
    _send(CmdEnsureOhRedundancy(channelId));
  }

  /// Register channel encryption keys in the isolate client.
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
    final cmd = CmdAddChannelKeys(
      channelId,
      encryptionKey,
      channelSecret: channelSecret,
      ownDisplayName: ownDisplayName,
      peerOhId: peerOhId,
      peerOhEndpoint: peerOhEndpoint,
      peerOhSet: peerOhSet
          ?.map(
            (d) => OhDescriptorData(
              endpoint: d.serverEndpoint,
              ohId: d.handleId,
              authPublicKey: d.authPublicKey,
            ),
          )
          .toList(),
      isChannelCreator: isChannelCreator,
      ratchetState: ratchetState,
      sessionTags: sessionTags,
      pendingRgbHex: pendingRgbHex,
    );
    _replay.recordChannelKeys(cmd);
    _send(cmd);
  }

  @override
  void restoreNodeScores(List<NodeScore> scores) {
    _replay.recordNodeScores(scores);
    _send(CmdRestoreNodeScores(scores));
  }

  /// Rebuilds the typed error a failed send carried across the isolate
  /// boundary.
  static Object _rebuildSendError(EventMessageSendFailed event) {
    final failedMemberIds = event.failedMemberIds;
    if (failedMemberIds != null) {
      return GroupSendException(
        failedMemberIds,
        event.error,
        event.messageIdHex,
      );
    }
    final statusCode = event.statusCode;
    if (statusCode != null) {
      return DepositException(statusCode);
    }
    return StateError(event.error);
  }

  // -----------------------------------------------------------------------
  // Groups (Frontend MS08)
  // -----------------------------------------------------------------------

  @override
  void registerGroup(GroupRegistration registration) {
    final cmd = CmdRegisterGroup(registration);
    _replay.recordGroup(cmd);
    _send(cmd);
  }

  @override
  Future<String> sendGroupMessage(
    String groupId,
    String content, {
    String? messageId,
  }) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<String>();
    _pendingSends[requestId] = completer;
    _send(
      CmdSendGroupMessage(requestId, groupId, content, messageId: messageId),
    );
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pendingSends.remove(requestId);
        throw TimeoutException(
          'sendGroupMessage timed out',
          const Duration(seconds: 60),
        );
      },
    );
  }

  Future<void> _groupOp(IsolateCommand Function(int requestId) build) async {
    await _isolateReady.future;
    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pendingGroupOps[requestId] = completer;
    _send(build(requestId));
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pendingGroupOps.remove(requestId);
        throw TimeoutException(
          'group operation timed out',
          const Duration(seconds: 60),
        );
      },
    );
  }

  @override
  Future<void> rotateGroupKey(
    String groupId, {
    required List<GroupMemberInfo> members,
    String? label,
  }) {
    return _groupOp(
      (requestId) =>
          CmdRotateGroupKey(requestId, groupId, members, label: label),
    );
  }

  @override
  Future<void> retryPendingRotations(String groupId) {
    return _groupOp(
      (requestId) => CmdRetryPendingRotations(requestId, groupId),
    );
  }

  @override
  Future<void> sendGroupHandshake(String channelId, List<int> handshake) {
    return _groupOp(
      (requestId) => CmdSendGroupHandshake(requestId, channelId, handshake),
    );
  }

  @override
  Future<void> sendGroupInfoUpdate(String groupId, String label) {
    return _groupOp(
      (requestId) => CmdSendGroupInfoUpdate(requestId, groupId, label),
    );
  }

  // Lifecycle hooks proxied
  @override
  void onPause() {
    _lifecyclePaused = true;
    _send(CmdLifecyclePause());
  }

  @override
  void onResume() {
    _lifecyclePaused = false;
    _send(CmdLifecycleResume());
  }
}

/// The entry point for the background isolate.
void _isolateEntryPoint(SendPort mainSendPort) {
  // RpLog state is per-isolate: without a sink the worker's operational
  // logs end in `dart:developer.log` inside this isolate — a no-op in
  // release AOT and invisible to field tests (T17). Forward info lines to
  // the main isolate instead, where the app's sink decides their fate.
  // LogLevel.debug (OH ids, peer addresses, payload sizes) is NOT
  // forwarded and stays suppressed inside the worker.
  RpLog.sink = (message, level) {
    if (level == LogLevel.info) {
      mainSendPort.send(EventLog(message));
    }
  };

  // Catch every uncaught async error (e.g. a socket write failing with
  // "connection reset by peer") so a single bad connection can never take
  // down the whole network worker. The supervision in
  // [RedPandaIsolateClient] remains as the last line of defense.
  runZonedGuarded(() => _runWorker(mainSendPort), (error, stack) {
    mainSendPort.send(EventLog('RedPandaWorker: uncaught error: $error'));
  });
}

void _runWorker(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  RedPandaLightClient? client;

  receivePort.listen((message) async {
    if (message is CmdInit) {
      RpLog.debug('RedPandaWorker: Initializing client...');

      final KeyPair keyPair = message.keyPair ?? await KeyPair.generate();
      final NodeId nodeId = message.nodeId ?? NodeId.fromPublicKey(keyPair);

      client = RedPandaLightClient(
        selfNodeId: nodeId,
        selfKeys: keyPair,
        seeds: message.seeds,
      );

      // Listen to client streams and forward to main isolate
      client!.connectionStatus.listen((status) {
        mainSendPort.send(EventConnectionStatus(status));
      });

      client!.peerCountStream.listen((count) {
        mainSendPort.send(EventPeerCount(count));
      });

      // Forward incoming messages to main isolate
      client!.incomingMessages.listen((msg) {
        mainSendPort.send(EventIncomingMessage(msg));
      });

      // ONE forwarder for every state change (ratchet, garlic, OH mailbox/
      // fetch/own-set/peer-set, ACKs, node scores, group state + handshakes).
      // A new state event needs no new listener here.
      client!.stateUpdates.listen((update) {
        mainSendPort.send(EventStateUpdate(update));
      });

      // Send periodic peer stats snapshots to main thread
      Timer.periodic(const Duration(seconds: 3), (_) {
        if (client != null) {
          mainSendPort.send(
            EventPeerStatsSnapshot(
              client!.getDebugPeerStats(),
              client!.activePeerAddresses.toList(),
              client!.connectingPeerAddresses.toList(),
            ),
          );
        }
      });

      RpLog.info('RedPandaWorker: Client initialized.');
    } else if (client == null) {
      RpLog.info('RedPandaWorker: Error - Client not initialized yet.');
      return;
    }

    // Handle other commands
    try {
      if (message is CmdConnect) {
        await client!.connect();
      } else if (message is CmdDisconnect) {
        await client!.disconnect();
      } else if (message is CmdAddPeer) {
        await client!.addPeer(message.address);
      } else if (message is CmdLifecyclePause) {
        client!.onPause();
      } else if (message is CmdLifecycleResume) {
        client!.onResume();
      } else if (message is CmdSendMessage) {
        try {
          final messageId = await client!.sendMessage(
            message.channelId,
            message.content,
            messageId: message.messageId,
          );
          mainSendPort.send(EventMessageSent(message.requestId, messageId));
        } on DepositException catch (e) {
          mainSendPort.send(
            EventMessageSendFailed(
              message.requestId,
              e.toString(),
              statusCode: e.statusName,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            EventMessageSendFailed(message.requestId, e.toString()),
          );
        }
      } else if (message is CmdRunLoopbackTest) {
        // Never throws — failures travel inside the result.
        final result = await client!.runLoopbackTest(message.channelId);
        mainSendPort.send(
          EventLoopbackResult(
            requestId: message.requestId,
            success: result.success,
            roundtripMs: result.roundtripMs,
            hopCount: result.hopCount,
            error: result.error,
          ),
        );
      } else if (message is CmdRunChannelDoctor) {
        // Never throws — failures travel inside the report's stages.
        final report = await client!.runChannelDoctor(message.channelId);
        mainSendPort.send(
          EventChannelDoctorResult(
            requestId: message.requestId,
            report: report,
          ),
        );
      } else if (message is CmdRegisterOutboundHandle) {
        try {
          final registration = await client!.registerOutboundHandle(
            channelId: message.channelId,
          );
          mainSendPort.send(
            EventOhRegistered(
              requestId: message.requestId,
              ohId: registration.ohId,
              privateKeyBytes: registration.keypair.privateKeyBytes.toList(),
              expiresAtMs: registration.expiresAtMs,
              channelId: registration.channelId,
              serverEndpoint: registration.serverEndpoint,
            ),
          );
        } on RateLimitException catch (e) {
          mainSendPort.send(
            EventOhRegisterFailed(
              message.requestId,
              e.toString(),
              rateLimited: true,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            EventOhRegisterFailed(message.requestId, e.toString()),
          );
        }
      } else if (message is CmdAddChannelKeys) {
        client!.addChannelKeys(
          message.channelId,
          message.encryptionKey,
          channelSecret: message.channelSecret,
          ownDisplayName: message.ownDisplayName,
          peerOhId: message.peerOhId,
          peerOhEndpoint: message.peerOhEndpoint,
          peerOhSet: message.peerOhSet
              ?.map(
                (d) => OHDescriptor(
                  serverEndpoint: d.endpoint,
                  handleId: d.ohId,
                  authPublicKey: d.authPublicKey,
                ),
              )
              .toList(),
          isChannelCreator: message.isChannelCreator,
          ratchetState: message.ratchetState,
          sessionTags: message.sessionTags,
          pendingRgbHex: message.pendingRgbHex,
        );
      } else if (message is CmdEnsureOhRedundancy) {
        unawaited(
          client!.ensureOhRedundancy(message.channelId).catchError((Object e) {
            RpLog.info('RedPandaIsolateClient: ensureOhRedundancy failed: $e');
          }),
        );
      } else if (message is CmdRestoreNodeScores) {
        client!.restoreNodeScores(message.scores);
      } else if (message is CmdRegisterGroup) {
        client!.registerGroup(message.registration);
      } else if (message is CmdSendGroupMessage) {
        try {
          final messageId = await client!.sendGroupMessage(
            message.groupId,
            message.content,
            messageId: message.messageId,
          );
          mainSendPort.send(EventMessageSent(message.requestId, messageId));
        } on GroupSendException catch (e) {
          mainSendPort.send(
            EventMessageSendFailed(
              message.requestId,
              e.message,
              failedMemberIds: e.failedMemberIds,
              messageIdHex: e.messageIdHex,
            ),
          );
        } on DepositException catch (e) {
          mainSendPort.send(
            EventMessageSendFailed(
              message.requestId,
              e.toString(),
              statusCode: e.statusName,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            EventMessageSendFailed(message.requestId, e.toString()),
          );
        }
      } else if (message is CmdRotateGroupKey) {
        await _runGroupOp(
          mainSendPort,
          message.requestId,
          () => client!.rotateGroupKey(
            message.groupId,
            members: message.members,
            label: message.label,
          ),
        );
      } else if (message is CmdRetryPendingRotations) {
        await _runGroupOp(
          mainSendPort,
          message.requestId,
          () => client!.retryPendingRotations(message.groupId),
        );
      } else if (message is CmdSendGroupHandshake) {
        await _runGroupOp(
          mainSendPort,
          message.requestId,
          () =>
              client!.sendGroupHandshake(message.channelId, message.handshake),
        );
      } else if (message is CmdSendGroupInfoUpdate) {
        await _runGroupOp(
          mainSendPort,
          message.requestId,
          () => client!.sendGroupInfoUpdate(message.groupId, message.label),
        );
      } else if (message is CmdRestoreOutboundHandle) {
        await client!.restoreOutboundHandle(
          OHRegistration(
            ohId: message.ohId,
            keypair: await OHKeypair.fromPrivateKeyBytes(
              Uint8List.fromList(message.privateKeyBytes),
            ),
            expiresAtMs: message.expiresAtMs,
            channelId: message.channelId,
            serverEndpoint: message.serverEndpoint,
            lastCursor: message.lastCursor,
          ),
        );
      }
    } catch (e, stack) {
      RpLog.debug('RedPandaWorker: Error handling command $message: $e');
      RpLog.debug(stack.toString());
    }
  });
}

/// Runs a group operation and reports its outcome as [EventGroupOpDone],
/// preserving the typed failure across the isolate boundary.
Future<void> _runGroupOp(
  SendPort mainSendPort,
  int requestId,
  Future<void> Function() op,
) async {
  try {
    await op();
    mainSendPort.send(EventGroupOpDone(requestId));
  } on GroupSendException catch (e) {
    mainSendPort.send(
      EventGroupOpDone(
        requestId,
        error: e.message,
        failedMemberIds: e.failedMemberIds,
      ),
    );
  } on DepositException catch (e) {
    mainSendPort.send(
      EventGroupOpDone(
        requestId,
        error: e.toString(),
        statusCode: e.statusName,
      ),
    );
  } catch (e) {
    mainSendPort.send(EventGroupOpDone(requestId, error: e.toString()));
  }
}
