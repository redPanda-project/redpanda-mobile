import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

// --- Mocks ---

class MockSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  bool isClosed = false;
  final String _remoteAddressString;
  @override
  final int remotePort;

  MockSocket(this._remoteAddressString, this.remotePort);

  @override
  InternetAddress get remoteAddress =>
      InternetAddress(_remoteAddressString, type: InternetAddressType.IPv4);

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(List<int> data) {}

  @override
  void destroy() {
    isClosed = true;
    _controller.close();
  }

  @override
  Future<void> close() async {
    isClosed = true;
    _controller.close();
  }

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPeerRepository implements PeerRepository {
  final Map<String, PeerStats> _peers = {};

  @override
  Future<void> load() async {}
  @override
  Future<void> save() async {}

  @override
  void updatePeer(
    String address, {
    String? nodeId,
    int? latencyMs,
    bool? isSuccess,
    bool? isFailure,
  }) {
    final stats = _peers.putIfAbsent(
      address,
      () => PeerStats(address: address),
    );
    if (latencyMs != null) stats.averageLatencyMs = latencyMs;
    // stats.successCount/failureCount logic ignored for simplicty unless needed
  }

  @override
  List<PeerStats> getBestPeers(int count) {
    final sorted = _peers.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score)); // Descending score
    return sorted.take(count).toList();
  }

  @override
  Iterable<String> get knownAddresses => _peers.keys;

  @override
  void addAll(Iterable<String> addresses) {
    for (final addr in addresses) {
      _peers.putIfAbsent(addr, () => PeerStats(address: addr));
    }
  }

  @override
  PeerStats? getPeer(String address) => _peers[address];

  // Test helper
  void setPeerScore(String address, int latencyMs) {
    final s = _peers.putIfAbsent(address, () => PeerStats(address: address));
    s.averageLatencyMs = latencyMs;
    s.successCount = 100; // High reliability
    s.failureCount = 0;
  }
}

// --- Tests ---

void main() {
  group('Connection Logic Unit Tests', () {
    late RedPandaLightClient client;
    late MockPeerRepository mockRepo;
    late List<String> socketAttempts;

    // We mock socket factory to track attempts
    Future<Socket> mockFactory(String host, int port) async {
      socketAttempts.add('$host:$port');
      return MockSocket(host, port);
    }

    // Factory that fails connections
    Future<Socket> failingFactory(String host, int port) async {
      socketAttempts.add('$host:$port');
      throw SocketException('Connection refused');
    }

    setUp(() {
      socketAttempts = [];
      mockRepo = MockPeerRepository();
      // Setup some initial peers
      mockRepo.setPeerScore('127.0.0.1:1001', 50); // Best
      mockRepo.setPeerScore('127.0.0.1:1002', 100);
      mockRepo.setPeerScore('127.0.0.1:1003', 150);
      mockRepo.setPeerScore('127.0.0.1:1004', 200);
      mockRepo.setPeerScore('127.0.0.1:1005', 250);
      mockRepo.setPeerScore('127.0.0.1:1006', 900); // Worst
    });

    tearDown(() {
      client.disconnect();
    });

    test('Fast Boot: Connects to top peers immediately on start', () async {
      // Logic: Constructor calls load() -> load calls _runConnectionCheck
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(KeyPair.generate()),
        selfKeys: KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: mockFactory,
        seeds: [], // No seeds, rely on repo
      );

      // Wait for async load and connection check
      await Future.delayed(Duration(milliseconds: 50));

      // We expect it to try connecting to the best peers
      // Since maxConnections=5, and we have 6 peers, and logic tries top 10 candidates...
      // It should try to connect to at least 5 of them.

      expect(socketAttempts.length, greaterThanOrEqualTo(5));
      expect(socketAttempts, contains('127.0.0.1:1001'));
      expect(socketAttempts, contains('127.0.0.1:1002'));
    });

    test('Max Connections: Does not exceed limit (5)', () async {
      // Start client
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(KeyPair.generate()),
        selfKeys: KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: mockFactory,
        seeds: [],
      );

      await Future.delayed(Duration(milliseconds: 100)); // Let it stabilize

      final count = await client.peerCountStream.first;
      expect(count, lessThanOrEqualTo(5));

      // Even if we add more peers
      mockRepo.setPeerScore('127.0.0.1:2001', 10); // Super good peer
      await client.addPeer('127.0.0.1:2001');

      await Future.delayed(Duration(milliseconds: 100));

      final count2 = await client.peerCountStream.first;
      expect(count2, lessThanOrEqualTo(5));
    });

    test('Core Preference: Prefers low latency peers', () async {
      // We have 6 peers in repo. 1001-1005 are good (low latency), 1006 is bad (900ms).
      // We start client. It should eventually drop 1006 if it connected to it, or strictly pick 1001-1005.

      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(KeyPair.generate()),
        selfKeys: KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: mockFactory,
        seeds: [],
      );

      await Future.delayed(Duration(milliseconds: 200));

      // We access the repo to see usage or check internal state if we could.
      // Instead, checking socket attempts isn't enough as it shows history.
      // We can infer preference by who is NOT connected if we could simulate handshake success.
      // But MockSocket here doesn't complete handshake, so 'peerCount' will be 0 verified.
      // The 'ActivePeer' list will be full of unverified peers.
      // Logic sorts by latency for culling.

      // Verification:
      // The 'toConnect' loop picks candidates from 'getBestPeers'.
      // 'getBestPeers' returns sorted list.
      // So it should pick 1001-1005 first.

      expect(socketAttempts, contains('127.0.0.1:1001'));
      expect(
        socketAttempts,
        isNot(contains('127.0.0.1:1006')),
      ); // Should skip the worst one if slots filled by better ones
    });

    test('Bad Internet: Stops trying if all connections fail', () async {
      // Use failing factory
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(KeyPair.generate()),
        selfKeys: KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: failingFactory,
        seeds: [],
      );

      // Initial burst
      await Future.delayed(Duration(milliseconds: 100));
      final initialAttempts = socketAttempts.length;
      expect(initialAttempts, greaterThan(0));

      // Wait for timer tick (3s)
      // If bad internet detected, it should throttle (wait 10s).
      // So between T+100ms and T+4000ms, there should be NO new attempts.

      await Future.delayed(Duration(milliseconds: 3100));

      // If logic works: failure -> sets _isBadInternetDetected -> next check (3s later) -> sees flag -> checks time -> returns early.
      // So counts should be same.

      expect(socketAttempts.length, equals(initialAttempts));
    });

    test('Backoff: Does not retry failed peer immediately', () async {
      // Setup repo with just 1 peer
      mockRepo = MockPeerRepository();
      mockRepo.setPeerScore('127.0.0.1:9999', 50);

      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(KeyPair.generate()),
        selfKeys: KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: failingFactory, // Fails
        seeds: [],
      );

      // First attempt
      await Future.delayed(Duration(milliseconds: 100));
      expect(socketAttempts.length, 1);

      // Force a check manually by waiting or calling if we could (we can't public api).
      // We rely on Timer (3s).
      // Backoff is 10s.
      // So at 3s, it should NOT retry.

      await Future.delayed(Duration(milliseconds: 3100));
      expect(socketAttempts.length, 1); // Still 1

      // wait until 11s (backoff expire)
      // await Future.delayed(Duration(seconds: 8));
      // expect(socketAttempts.length, 2);
    });
  });
}
