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
  /// `ActivePeer._shutdown` -> `onDisconnect` -> `_recordConnectionFailure`),
  /// and the retry backoff is armed in the same synchronous step, just before
  /// it. Tests use it to wait for the failure to have landed instead of
  /// guessing a delay.
  final List<String> failures = [];

  /// Invoked synchronously from inside `updatePeer(isFailure: true)`, i.e.
  /// from inside the client's failure report. Lets a test observe the state
  /// the client is in at exactly that instant (TD080).
  void Function(String address)? onFailure;

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
    if (isFailure == true) {
      failures.add(address);
      onFailure?.call(address);
    }
    // stats.successCount/failureCount logic ignored for simplicity unless needed
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
    // Nullable, not `late`: a test that throws before the assignment (a key
    // pair that fails to generate) would otherwise die a second time in
    // tearDown with a LateInitializationError, hiding the real failure.
    RedPandaLightClient? client;
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
      await client?.disconnect();
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

      final count = await client!.peerCountStream.first;
      expect(count, lessThanOrEqualTo(5));

      // Even if we add more peers
      mockRepo.setPeerScore('127.0.0.1:2001', 10); // Super good peer
      await client!.addPeer('127.0.0.1:2001');

      // Negative check: give the addPeer-triggered connection check time to
      // NOT dial. A fixed delay is correct here - too short only weakens the
      // assertion, it can never make it red.
      await Future.delayed(Duration(milliseconds: 100));

      final count2 = await client!.peerCountStream.first;
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

      // Sorted lists, not sets: a bug that reports one address twice while
      // dialling it once keeps the *set* equal.
      expect(mockRepo.failures..sort(), socketAttempts.toList()..sort());
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

        // Drive a second, real connection check - the same work a periodic
        // tick does. addPeer() runs exactly one check; connect()/onResume()
        // would additionally arm Timer.periodic(3 s), and that tick is a
        // second, unsynchronised dial source *after* the 2 s backoff has
        // expired - i.e. exactly the kind of race this file is cleaning up.
        // Re-adding a known address is a no-op on the repository.
        //
        // The five just-failed addresses sit in their 2 s backoff, so the only
        // address this check may dial is the untried 1006. That dial is the
        // positive edge we wait for: it proves the check ran to the end of its
        // dial loop, which a blind sleep never proves.
        await client!.addPeer('127.0.0.1:1001');
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

    test(
      'Backoff: the only known peer stays in backoff (no candidate left)',
      () async {
        // Single-peer repository: once its dial fails there is nothing left to
        // connect to, which is the branch the 6-peer test above cannot reach.
        final socketAttempts = <String>[];
        mockRepo = MockPeerRepository();
        mockRepo.setPeerScore('127.0.0.1:9999', 50);

        client = RedPandaLightClient(
          selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
          selfKeys: await KeyPair.generate(),
          peerRepository: mockRepo,
          socketFactory: recordingFactory(socketAttempts, failing: true),
          seeds: [],
        );

        await waitFor(
          () => socketAttempts.isNotEmpty,
          description: 'first dial',
        );
        await waitFor(
          () => mockRepo.failures.isNotEmpty,
          description: 'failure recorded (backoff armed)',
        );

        // Second check, again without arming a periodic timer. No positive edge
        // exists here - there is no second address to dial - so this is the one
        // place a fixed window is the right tool: it is the only dial source in
        // flight, so a too-short window can only weaken the assertion, never
        // redden it (see helpers/wait_for.dart).
        await client!.addPeer('127.0.0.1:9999');
        await Future.delayed(const Duration(milliseconds: 100));

        expect(socketAttempts.length, 1);
      },
    );
  });

  // TD078/TD079/TD080: what the client really does across a full outage.
  //
  // These tests hand the client an injected clock (`now:`) instead of waiting
  // on the wall clock. `fake_async` is not an option here: the dial loop
  // awaits real `InternetAddress.lookup` calls, so the zone's fake timers
  // never advance past them (TD079).
  group('Outage cycle', () {
    RedPandaLightClient? client;
    late MockPeerRepository mockRepo;
    // Reassigned by the tests to move the client's clock forward.
    late DateTime fakeNow;

    setUp(() {
      fakeNow = DateTime.utc(2026, 1, 1, 12);
      mockRepo = MockPeerRepository();
      for (var i = 1; i <= 6; i++) {
        mockRepo.setPeerScore('127.0.0.1:100$i', i * 50);
      }
    });

    tearDown(() async {
      await client?.disconnect();
    });

    test('total outage: backoff alone stops the dials, and the first redial '
        'happens as soon as it expires', () async {
      final socketAttempts = <String>[];
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
        selfKeys: await KeyPair.generate(),
        peerRepository: mockRepo,
        socketFactory: recordingFactory(socketAttempts, failing: true),
        seeds: [],
        now: () => fakeNow,
      );

      // Outage, phase 1: the fast-boot check fills all five slots, every
      // dial is refused. The sixth (worst) address is left untried.
      await waitFor(
        () => socketAttempts.length >= 5,
        description: 'fast-boot burst (5 dials)',
      );
      await waitFor(
        () => mockRepo.failures.length >= 5,
        description: '5 failures recorded',
      );

      // Outage, phase 2: one more check picks up the last untried address —
      // now every known address has failed once and sits in its 2 s backoff.
      await client!.addPeer('127.0.0.1:1001');
      await waitFor(
        () => mockRepo.failures.length >= 6,
        description: 'the sixth address failed too (total outage)',
      );
      expect(socketAttempts.toSet().length, 6);

      // Outage, phase 3: this is the state TD078 is about — nothing
      // connected, nothing dialable, every candidate in backoff. Three
      // further checks must produce no dial at all. A fixed window is the
      // right tool for a "nothing happens" assertion: too short only
      // weakens it, it can never redden it.
      for (var i = 0; i < 3; i++) {
        await client!.addPeer('127.0.0.1:1001');
      }
      await Future.delayed(const Duration(milliseconds: 100));
      expect(
        socketAttempts.length,
        6,
        reason:
            'during the outage the backoff map alone suppresses every dial '
            '— no extra global throttle is involved',
      );

      // Recovery: the 2 s backoff expires. The very next check must dial
      // again immediately. A 10 s "bad internet" throttle keyed on this
      // state (TD078) would swallow this redial for another ~8 s.
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      await client!.addPeer('127.0.0.1:1001');
      await waitFor(
        () => socketAttempts.length > 6,
        description: 'redial in the first check after backoff expiry',
      );
    });

    test(
      'TD080: the retry backoff is armed before the failure is reported',
      () async {
        // One address only, so the sole thing a re-entrant check could do is
        // re-dial the address that just failed.
        final socketAttempts = <String>[];
        mockRepo = MockPeerRepository();
        mockRepo.setPeerScore('127.0.0.1:9001', 50);

        var reentered = false;
        mockRepo.onFailure = (address) {
          if (reentered) return; // a re-dial loop would otherwise not end
          reentered = true;
          // This runs INSIDE the client's failure report
          // (`updatePeer(isFailure: true)`), and `addPeer` picks the next
          // cycle's dial candidates synchronously, before its first await.
          // So this is the exact instant TD080 is about: if the backoff were
          // armed *after* the report, this check would see an address that
          // failed but is not in backoff, and dial it again.
          unawaited(client!.addPeer(address));
        };

        client = RedPandaLightClient(
          selfNodeId: NodeId.fromPublicKey(await KeyPair.generate()),
          selfKeys: await KeyPair.generate(),
          peerRepository: mockRepo,
          socketFactory: recordingFactory(socketAttempts, failing: true),
          seeds: [],
          now: () => fakeNow,
        );

        await waitFor(
          () => mockRepo.failures.isNotEmpty,
          description: 'the single dial failed',
        );
        await Future.delayed(const Duration(milliseconds: 100));

        expect(
          reentered,
          isTrue,
          reason: 'the re-entrant connection check must really have run',
        );
        expect(
          socketAttempts.length,
          1,
          reason:
              'a check re-entered from the failure report must already see '
              'the backoff (_recordConnectionFailure arms it first)',
        );
      },
    );
  });
}
