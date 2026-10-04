import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/wait_for.dart';

/// Socket that never answers: the dial is registered, the handshake never
/// completes, the peer stays "connecting" in the client's peer map.
class _SilentSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

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

/// T154: hostname seeds (`seedN.redpanda.im`) next to an IP fallback seed.
///
/// The DNS lookup is injected, so these tests never touch a real resolver.
void main() {
  const hostSeed = 'seed2.test:59558';
  const ipSeed = '5.75.137.166:59558';

  RedPandaLightClient? client;

  tearDown(() async {
    await client?.disconnect();
    client = null;
  });

  Future<RedPandaLightClient> build({
    required List<String> seeds,
    required Future<List<InternetAddress>> Function(String host) lookup,
    required List<String> dials,
    PeerRepository? repo,
  }) async {
    final keys = await KeyPair.generate();
    return RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: seeds,
      peerRepository: repo,
      lookup: lookup,
      socketFactory: (host, port) async {
        dials.add('$host:$port');
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
        if (host == 'seed2.test') return [InternetAddress('5.75.137.166')];
        throw SocketException('unexpected lookup $host');
      },
    );

    await waitFor(() => dials.isNotEmpty, description: 'first dial');
    // Nothing else may follow: the second seed is an alias of the first dial.
    await Future.delayed(const Duration(milliseconds: 200));
    expect(dials, hasLength(1));

    // A later check (the connected peer is still in the map) skips it too.
    await client!.addPeer(ipSeed);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(dials, hasLength(1));

    // TD260: IP literals are never sent to the resolver.
    expect(lookups, everyElement('seed2.test'));
  });

  test('peer repository keeps hostname and IP as separate entries', () async {
    final repo = InMemoryPeerRepository();
    client = await build(
      seeds: [hostSeed, ipSeed],
      dials: [],
      repo: repo,
      lookup: (host) async => [InternetAddress('5.75.137.166')],
    );
    await waitFor(() => repo.knownAddresses.length == 2, description: 'seeds');
    // Documented behavior: addresses are keyed by their literal string, the
    // dedup happens at dial time (and HopSelector dedups by node id).
    expect(repo.knownAddresses, containsAll([hostSeed, ipSeed]));
  });

  test('an unresolvable hostname is skipped into backoff and the fallback IP '
      'is dialled', () async {
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
    final watch = Stopwatch()..start();
    client = await build(
      seeds: [ipSeed],
      dials: dials,
      repo: repo,
      lookup: (host) => Completer<List<InternetAddress>>().future,
    );

    await waitFor(
      () => dials.contains(ipSeed),
      timeout: RedPandaLightClient.lookupTimeout * 3,
      description: 'fallback dial behind a hanging lookup',
    );
    watch.stop();
    // The hostname was still dialled (the socket resolves on its own).
    expect(dials.first, 'seed1.hang:59558');
    expect(watch.elapsed, lessThan(RedPandaLightClient.lookupTimeout * 3));
  });
}
