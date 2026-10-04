import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/wait_for.dart';

/// Socket that never answers: the dial is registered, the handshake never
/// completes, the peer stays "connecting" in the client's peer map. [drop]
/// simulates the node going away.
class _SilentSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

  void drop() => _controller.close();

  @override
  Future<void> get done => Completer<void>().future;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  void add(List<int> data) {}

  @override
  void destroy() => _controller.close();

  @override
  Future<void> close() async => _controller.close();

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Plaintext node stand-in: answers the 30-byte handshake (enough for
/// `isHandshakeVerified`) and records the command byte of every frame after.
class _HandshakingSocket implements Socket {
  final _incoming = StreamController<Uint8List>();
  final List<int> sent = [];
  bool _answered = false;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void add(List<int> data) {
    sent.addAll(data);
    if (!_answered && sent.length >= 30) {
      _answered = true;
      sent.removeRange(0, 30);
      final b = BytesBuilder()
        ..add('k3gV'.codeUnits)
        ..addByte(22)
        ..addByte(0)
        ..add(Uint8List(20))
        ..add(Uint8List(4));
      _incoming.add(b.toBytes());
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  void destroy() => _incoming.close();

  @override
  Future<void> close() async => _incoming.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// T154: hostname seeds (`seedN.redpanda.im`) next to an IP fallback seed.
///
/// The DNS lookup is injected, so these tests never touch a real resolver.
/// None of them calls `connect()`: without its 3 s timer, the constructor's
/// check and explicit `addPeer` calls are the only connection checks.
void main() {
  const hostSeed = 'seed2.test:59558';
  const ipSeed = '5.75.137.166:59558';
  final seed2Ip = [InternetAddress('5.75.137.166')];

  RedPandaLightClient? client;
  late DateTime fakeNow;

  setUp(() => fakeNow = DateTime.utc(2026, 10, 4, 12));

  tearDown(() async {
    await client?.disconnect();
    client = null;
  });

  Future<RedPandaLightClient> build({
    required List<String> seeds,
    required Future<List<InternetAddress>> Function(String host) lookup,
    List<String>? dials,
    PeerRepository? repo,
    Future<Socket> Function(String host, int port)? socketFactory,
  }) async {
    final keys = await KeyPair.generate();
    return RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: seeds,
      peerRepository: repo,
      lookup: lookup,
      now: () => fakeNow,
      socketFactory:
          socketFactory ??
          (host, port) async {
            dials?.add('$host:$port');
            if (host.endsWith('.invalid')) {
              throw SocketException('Failed host lookup: $host');
            }
            return _SilentSocket();
          },
    );
  }

  test('defaultSeeds: DNS names plus seed2 IP as fallback', () {
    expect(RedPandaLightClient.defaultSeeds, [
      'seed1.redpanda.im:59558',
      'seed2.redpanda.im:59558',
      '5.75.137.166:59558',
    ]);
  });

  test('a hostname seed and its own IP are dialled once, not twice — '
      'on the cold start and in later checks', () async {
    final dials = <String>[];
    final lookups = <String>[];
    client = await build(
      seeds: [hostSeed, ipSeed],
      dials: dials,
      lookup: (host) async {
        lookups.add(host);
        if (host == 'seed2.test') return seed2Ip;
        throw SocketException('unexpected lookup $host');
      },
    );

    await waitFor(() => dials.isNotEmpty, description: 'first dial');
    // Nothing else may follow: the second seed is an alias of the first dial.
    await Future.delayed(const Duration(milliseconds: 200));
    expect(dials, hasLength(1));

    // A later check, after the alias' retry delay: the alias is looked at
    // again (not merely parked in backoff) and skipped again.
    fakeNow = fakeNow.add(RedPandaLightClient.aliasRetryDelay * 2);
    final lookupsBefore = lookups.length;
    await client!.addPeer(ipSeed);
    await client!.addPeer(hostSeed);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(dials, hasLength(1));
    // At most the skipped alias is resolved again; the connected peer costs
    // no DNS query per check. TD260: IP literals never reach the resolver.
    expect(lookups.length - lookupsBefore, lessThanOrEqualTo(1));
    expect(lookups, everyElement('seed2.test'));
  });

  test('two overlapping checks: the IP dialled while the hostname lookup is '
      'still pending makes the hostname an alias', () async {
    final dials = <String>[];
    final started = Completer<void>();
    final pending = Completer<List<InternetAddress>>();
    client = await build(
      seeds: [hostSeed],
      dials: dials,
      lookup: (host) {
        if (!started.isCompleted) started.complete();
        return pending.future;
      },
    );
    // Check A sits in the hostname lookup; check B dials the IP meanwhile.
    await started.future;
    await client!.addPeer(ipSeed);
    await waitFor(() => dials.contains(ipSeed), description: 'IP dial');
    pending.complete(seed2Ip);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(dials, [ipSeed]);
  });

  test('the fallback IP is dialled once the hostname connection it aliases '
      'is lost', () async {
    final dials = <String>[];
    final sockets = <String, _SilentSocket>{};
    client = await build(
      seeds: [hostSeed, ipSeed],
      lookup: (host) async => seed2Ip,
      socketFactory: (host, port) async {
        final address = '$host:$port';
        dials.add(address);
        return sockets[address] = _SilentSocket();
      },
    );
    await waitFor(() => dials.isNotEmpty, description: 'first dial');
    await Future.delayed(const Duration(milliseconds: 200));
    expect(dials, hasLength(1));
    final first = dials.single;
    final other = first == hostSeed ? ipSeed : hostSeed;

    sockets[first]!.drop(); // node gone (failure -> 2 s backoff for it)
    await Future.delayed(const Duration(milliseconds: 100));
    fakeNow = fakeNow.add(RedPandaLightClient.aliasRetryDelay);
    await client!.addPeer(other);
    await waitFor(
      () => dials.contains(other),
      description: 'the other name of the node is dialled',
    );
  });

  test('an OH registered under the IP is served by the connection under '
      'the hostname', () async {
    final socket = _HandshakingSocket();
    client = await build(
      seeds: [hostSeed, ipSeed],
      lookup: (host) async => seed2Ip,
      socketFactory: (host, port) async {
        if (host == 'seed2.test') return socket;
        // The IP must never be needed: it is an alias of seed2.test.
        throw const SocketException('test: IP dialled');
      },
      repo: InMemoryPeerRepository()
        ..updatePeer(hostSeed, latencyMs: 10, isSuccess: true),
    );
    await waitFor(
      () => client!.activePeerAddresses.contains(hostSeed),
      description: 'hostname peer verified',
    );
    final oh = OHRegistration(
      ohId: List.generate(20, (i) => i),
      keypair: await OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      channelId: 'alias-channel',
      serverEndpoint: ipSeed,
    );
    unawaited(client!.renewOutboundHandle(oh).catchError((_) => false));
    await waitFor(
      () => socket.sent.contains(150),
      description: 'renewal (command 150) sent over the hostname connection',
    );
  });

  test('peer repository keeps hostname and IP as separate entries', () async {
    final repo = InMemoryPeerRepository();
    client = await build(
      seeds: [hostSeed, ipSeed],
      repo: repo,
      lookup: (host) async => seed2Ip,
    );
    await waitFor(() => repo.knownAddresses.length == 2, description: 'seeds');
    // Documented behavior: addresses are keyed by their literal string, the
    // dedup happens at dial time (and HopSelector dedups by node id).
    expect(repo.knownAddresses, containsAll([hostSeed, ipSeed]));
  });

  test('an unresolvable hostname is dialled, fails into backoff, and the '
      'fallback IP is dialled', () async {
    final dials = <String>[];
    final repo = InMemoryPeerRepository();
    client = await build(
      seeds: ['seed1.invalid:59558', ipSeed],
      dials: dials,
      repo: repo,
      lookup: (host) async =>
          throw SocketException('Failed host lookup: $host'),
    );

    await waitFor(
      () =>
          dials.contains(ipSeed) &&
          dials.contains('seed1.invalid:59558') &&
          (repo.getPeer('seed1.invalid:59558')?.failureCount ?? 0) > 0,
      description: 'fallback dial + failure recorded for the bad name',
    );
    // The failed name is in backoff, not redialled in a tight loop.
    await client!.addPeer(ipSeed);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(dials.where((d) => d == 'seed1.invalid:59558'), hasLength(1));
  });

  test('a hanging lookup does not hold up the next candidate for longer than '
      'lookupTimeout', () async {
    final dials = <String>[];
    final repo = InMemoryPeerRepository()
      // Best score: the hanging hostname is the first candidate of the loop.
      ..updatePeer('seed1.hang:59558', latencyMs: 10, isSuccess: true);
    final lookups = <String>[];
    final watch = Stopwatch()..start();
    client = await build(
      seeds: [ipSeed],
      dials: dials,
      repo: repo,
      lookup: (host) {
        lookups.add(host);
        return Completer<List<InternetAddress>>().future;
      },
    );

    await waitFor(
      () => dials.contains(ipSeed),
      timeout: RedPandaLightClient.lookupTimeout * 3,
      description: 'fallback dial behind a hanging lookup',
    );
    watch.stop();
    // The hostname was still dialled (the socket resolves on its own).
    expect(dials.first, 'seed1.hang:59558');
    expect(lookups, ['seed1.hang']);
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(RedPandaLightClient.lookupTimeout),
    );
  });

  test(
    'disconnect() during a pending lookup dials nothing afterwards',
    () async {
      final dials = <String>[];
      final started = Completer<void>();
      final pending = Completer<List<InternetAddress>>();
      client = await build(
        seeds: [hostSeed],
        dials: dials,
        lookup: (host) {
          if (!started.isCompleted) started.complete();
          return pending.future;
        },
      );
      await started.future;
      await client!.disconnect();
      pending.complete(seed2Ip);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(dials, isEmpty);
    },
  );
}
