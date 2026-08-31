import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/wait_for.dart';

// --- Mocks ---

class MockSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

  @override
  Future<void> get done => Completer<void>().future;
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

  /// Addresses reported with `isFailure: true`, in call order.
  ///
  /// This is the client's own "the dial failed" signal (it runs through
  /// `ActivePeer._shutdown` -> `onDisconnect`), and it is armed in the same
  /// step as the retry backoff. Tests use it to wait for the failure to have
  /// landed instead of guessing a delay.
  final List<String> failures = [];

  @override
  void updatePeer(
    String address, {
    String? nodeId,
    String? encryptionPublicKey,
    int? latencyMs,
    bool? isSuccess,
    bool? isFailure,
  }) {
    final stats = _peers.putIfAbsent(
      address,
      () => PeerStats(address: address),
    );
    if (latencyMs != null) stats.averageLatencyMs = latencyMs;
    if (isFailure == true) failures.add(address);
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

/// Builds a socket factory that appends every dial to [attempts]; with
/// [failing] set it also throws, so the client sees a refused connection.
///
/// Deliberately built per test instead of sharing one group-level list: a
/// client's dial loop keeps running after the test body returned (nothing
/// awaits it), so a shared list receives the *previous* test's late dials and
/// the next test reads them as its own - that leak surfaced in #105 as
/// `Expected: <1>, Actual: <5>`. A closure over a list that only one test can
/// see makes the leak structurally impossible.
Future<Socket> Function(String host, int port) recordingFactory(
  List<String> attempts, {
  bool failing = false,
}) {
  return (String host, int port) async {
    attempts.add('$host:$port');
    if (failing) throw SocketException('Connection refused');
    return MockSocket(host, port);
  };
}

void main() {
  group('Connection Logic Unit Tests', () {
    late RedPandaLightClient client;
    late MockPeerRepository mockRepo;

    setUp(() {
      mockRepo = MockPeerRepository();
      // Setup some initial peers
      mockRepo.setPeerScore('127.0.0.1:1001', 50); // Best
      mockRepo.setPeerScore('127.0.0.1:1002', 100);
      mockRepo.setPeerScore('127.0.0.1:1003', 150);
      mockRepo.setPeerScore('127.0.0.1:1004', 200);
      mockRepo.setPeerScore('127.0.0.1:1005', 250);
      mockRepo.setPeerScore('127.0.0.1:1006', 900); // Worst
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('Fast Boot: Connects to top peers immediately on start', () async {
      final socketAttempts = <String>[];
      // Logic: Constructor calls load() -> load calls _runConnectionCheck
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
        selfKeys: await KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: recordingFactory(socketAttempts),
        seeds: [], // No seeds, rely on repo
      );

      // Wait for the async load -> _runConnectionCheck to have dialled its
      // slots. The dial loop awaits a DNS lookup per address, so the attempts
      // trickle in; a fixed sleep here was the TD052 flake (host under load
      // => 0-4 attempts after 50 ms).
      await waitFor(
        () => socketAttempts.length >= 5,
        description: 'fast-boot burst (5 dials)',
      );

      // We expect it to try connecting to the best peers
      // Since maxConnections=5, and we have 6 peers, and logic tries top 10 candidates...
      // It should try to connect to at least 5 of them.

      expect(socketAttempts.length, greaterThanOrEqualTo(5));
      expect(socketAttempts, contains('127.0.0.1:1001'));
      expect(socketAttempts, contains('127.0.0.1:1002'));
    });

    test('Max Connections: Does not exceed limit (5)', () async {
      final socketAttempts = <String>[];
      // Start client
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
        selfKeys: await KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: recordingFactory(socketAttempts),
        seeds: [],
      );

      await waitFor(
        () => socketAttempts.length >= 5,
        description: 'initial burst (5 dials)',
      );

      final count = await client.peerCountStream.first;
      expect(count, lessThanOrEqualTo(5));

      // Even if we add more peers
      mockRepo.setPeerScore('127.0.0.1:2001', 10); // Super good peer
      await client.addPeer('127.0.0.1:2001');

      // Negative check: give the addPeer-triggered connection check time to
      // NOT dial. A fixed delay is correct here - too short only weakens the
      // assertion, it can never make it red.
      await Future.delayed(Duration(milliseconds: 100));

      final count2 = await client.peerCountStream.first;
      expect(count2, lessThanOrEqualTo(5));
      // All 5 slots are taken, so the new (better) peer must not be dialled.
      expect(
        socketAttempts.length,
        5,
        reason: 'no extra dial once maxConnections slots are filled',
      );
    });

    test('Core Preference: Prefers low latency peers', () async {
      // We have 6 peers in repo. 1001-1005 are good (low latency), 1006 is bad (900ms).
      // We start client. It should eventually drop 1006 if it connected to it, or strictly pick 1001-1005.

      final socketAttempts = <String>[];
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
        selfKeys: await KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: recordingFactory(socketAttempts),
        seeds: [],
      );

      // Wait for the burst to finish before judging it - otherwise the
      // 'isNot(contains 1006)' assertion can pass simply because nothing has
      // been dialled yet.
      await waitFor(
        () => socketAttempts.length >= 5,
        description: 'initial burst (5 dials)',
      );

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

    test('Failed dials are reported to the peer repository', () async {
      final socketAttempts = <String>[];
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
        selfKeys: await KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: recordingFactory(socketAttempts, failing: true),
        seeds: [],
      );

      // Fast-boot burst: the constructor's single connection check fills all
      // maxConnections slots. Every dial throws.
      await waitFor(
        () => socketAttempts.length >= 5,
        description: 'initial burst (5 dials)',
      );

      // The failure travels ActivePeer._shutdown -> onDisconnect -> repository
      // (and arms the retry backoff on the way), so it lands a moment after
      // the dial itself.
      await waitFor(
        () => mockRepo.failures.length >= socketAttempts.length,
        description: 'a failure recorded for every dial',
      );

      expect(mockRepo.failures.toSet(), socketAttempts.toSet());
    });

    test(
      'Backoff: a failed peer is not re-dialled while its backoff runs',
      () async {
        final socketAttempts = <String>[];
        client = RedPandaLightClient(
          selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
          selfKeys: await KeyPair.generate(),
          peerRepository: mockRepo,
          socketFactory: recordingFactory(socketAttempts, failing: true),
          seeds: [],
        );

        // The fast-boot check takes the top five of the six known peers; the
        // worst one (1006) is left untried and is therefore NOT in backoff.
        await waitFor(
          () => socketAttempts.length >= 5,
          description: 'initial burst (5 dials)',
        );
        await waitFor(
          () => mockRepo.failures.length >= 5,
          description: '5 failures recorded (backoff armed)',
        );

        // Drive the periodic path for real - connect() runs a check immediately
        // (and then every 3 s, which this test no longer waits for). The five
        // just-failed addresses sit in their 2 s backoff, so the only address
        // this check may dial is the untried 1006. That dial is the positive
        // edge we wait for: it proves the check ran to the end of its dial loop,
        // which a blind sleep never proves.
        await client.connect();
        await waitFor(
          () => socketAttempts.contains('127.0.0.1:1006'),
          description: 'second check dials the untried peer',
        );

        expect(
          socketAttempts.length,
          6,
          reason: 'the second check may only add the untried peer',
        );
        expect(
          socketAttempts.toSet().length,
          socketAttempts.length,
          reason:
              'no address may be dialled twice while its backoff is running',
        );
      },
    );
  });
}
