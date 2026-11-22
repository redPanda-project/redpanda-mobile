import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

/// T167: a Notify that arrives while a poll cycle runs, after that cycle has
/// already fetched the notified mailbox, is followed by a fetch right after
/// the cycle ends — not by the next regular tick (up to
/// [RedPandaLightClient.activePollInterval] later). The follow-up is
/// bounded by a token bucket: up to [RedPandaLightClient.pollBurst] cycles
/// back to back, then at most one per [RedPandaLightClient.pollStartRefill]; and
/// the full cycle keeps its own cadence. Same plaintext ScriptedSocket harness as the T38 suite.
class ScriptedSocket implements Socket {
  @override
  Future<void> get done => Completer<void>().future;

  final _incoming = StreamController<Uint8List>();
  final List<int> _outBuffer = [];
  bool _handshakeAnswered = false;

  /// Called for every complete [cmd][len][payload] frame the client sends.
  void Function(int command, Uint8List payload)? onCommandFrame;

  /// Node handshake: MAGIC(4) + VER(1) + TYPE(1) + NODEID(20) + PORT(4).
  static Uint8List nodeHandshake() {
    final b = BytesBuilder();
    b.add('k3gV'.codeUnits);
    b.addByte(22);
    b.addByte(0);
    b.add(Uint8List(20));
    b.add(Uint8List(4));
    return b.toBytes();
  }

  /// Injects node → client bytes.
  void reply(List<int> data) {
    if (!_incoming.isClosed) {
      _incoming.add(Uint8List.fromList(data));
    }
  }

  /// Injects a [cmd][len][protobuf] frame.
  void replyCommand(int command, List<int> protobufBytes) {
    final b = BytesBuilder();
    b.addByte(command);
    final len = ByteData(4)..setInt32(0, protobufBytes.length, Endian.big);
    b.add(len.buffer.asUint8List());
    b.add(protobufBytes);
    reply(b.toBytes());
  }

  @override
  void add(List<int> data) {
    _outBuffer.addAll(data);
    _drainOutBuffer();
  }

  void _drainOutBuffer() {
    // First the 30-byte client handshake, answered with the node handshake.
    if (!_handshakeAnswered) {
      if (_outBuffer.length < 30) return;
      _outBuffer.removeRange(0, 30);
      _handshakeAnswered = true;
      reply(nodeHandshake());
    }
    // Then a plaintext command stream: 1-byte commands (requestPublicKey,
    // ping, ...) are skipped, framed commands are reported to the test.
    while (_outBuffer.isNotEmpty) {
      final command = _outBuffer[0];
      if (command == 141 ||
          command == 142 ||
          command == 150 ||
          command == 152 ||
          command == 156 ||
          command == 159) {
        if (_outBuffer.length < 5) return;
        final len = ByteData.sublistView(
          Uint8List.fromList(_outBuffer.sublist(1, 5)),
        ).getInt32(0, Endian.big);
        if (_outBuffer.length < 5 + len) return;
        final payload = Uint8List.fromList(_outBuffer.sublist(5, 5 + len));
        _outBuffer.removeRange(0, 5 + len);
        onCommandFrame?.call(command, payload);
      } else {
        _outBuffer.removeAt(0);
      }
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _incoming.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  void destroy() {
    _incoming.close();
  }

  @override
  Future<void> close() async {
    _incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Client wired to a [ScriptedSocket]; waits until the peer is verified.
Future<(RedPandaLightClient, ScriptedSocket)> connectedClient() async {
  final socket = ScriptedSocket();
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: ['scripted:1'],
    socketFactory: (h, p) async => socket,
  );
  await client.connect();
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (client.activePeerAddresses.isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('peer never became handshake-verified');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return (client, socket);
}

/// Polls [predicate] until true or the timeout elapses.
Future<void> pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('pumpUntil timed out${reason != null ? ': $reason' : ''}');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Scripted node: answers registrations and subscribes, records every fetch
/// (OH + time) and answers it — unless [holdFetch] says to keep the response
/// back, so a test can pin a cycle in the middle of its fetch loop.
class _Node {
  _Node(this.socket) {
    socket.onCommandFrame = (command, payload) {
      if (command == 150) {
        socket.replyCommand(
          151,
          (RegisterOhResponse()..status = Status.OK).writeToBuffer(),
        );
      } else if (command == 159) {
        socket.replyCommand(
          160,
          (SubscribeResponse()..status = Status.OK).writeToBuffer(),
        );
      } else if (command == 152) {
        final ohId = FetchRequest.fromBuffer(payload).ohId;
        fetches.add((ohId, DateTime.now()));
        if (holdFetch != null && holdFetch!(ohId)) {
          held.add(ohId);
          return;
        }
        answerFetch();
        afterFetchAnswered?.call(ohId);
      }
    };
  }

  final ScriptedSocket socket;
  final List<(List<int>, DateTime)> fetches = [];
  final List<List<int>> held = [];
  bool Function(List<int> ohId)? holdFetch;
  void Function(List<int> ohId)? afterFetchAnswered;

  void answerFetch() => socket.replyCommand(
    153,
    (FetchResponse()..status = Status.OK).writeToBuffer(),
  );

  void notify(List<int> ohId) =>
      socket.replyCommand(161, (Notify()..ohId = ohId).writeToBuffer());

  List<DateTime> fetchTimesOf(List<int> ohId, {DateTime? after}) => [
    for (final (id, at) in fetches)
      if (_sameBytes(id, ohId) && (after == null || at.isAfter(after))) at,
  ];
}

/// Scripted mailbox host for the reconnect tests (several nodes, each with
/// its own mailbox — the T163 harness plus fetch control and Notify).
class _HostSocket implements Socket {
  _HostSocket(this.nodeIdByte);

  final int nodeIdByte;
  final _incoming = StreamController<Uint8List>();
  final List<int> _out = [];
  bool _handshakeAnswered = false;

  /// OH ids of every FetchRequest this socket received, in order.
  final List<List<int>> fetchOhIds = [];

  /// While it returns true for a fetched OH, the fetch is not answered.
  bool Function(List<int> ohId)? holdFetch;
  int heldFetches = 0;

  @override
  Future<void> get done => Completer<void>().future;

  void _reply(List<int> data) {
    if (!_incoming.isClosed) _incoming.add(Uint8List.fromList(data));
  }

  void _replyCommand(int command, List<int> body) {
    final b = BytesBuilder()
      ..addByte(command)
      ..add(
        (ByteData(
          4,
        )..setInt32(0, body.length, Endian.big)).buffer.asUint8List(),
      )
      ..add(body);
    _reply(b.toBytes());
  }

  void notify(List<int> ohId) =>
      _replyCommand(161, (Notify()..ohId = ohId).writeToBuffer());

  /// Answers every held fetch (empty mailbox).
  void releaseFetches() {
    holdFetch = null;
    for (; heldFetches > 0; heldFetches--) {
      _replyCommand(153, (FetchResponse()..status = Status.OK).writeToBuffer());
    }
  }

  /// The node drops the connection (not the client).
  void dropFromNodeSide() => _incoming.close();

  bool fetched(List<int> ohId) => fetchOhIds.any((id) => _sameBytes(id, ohId));

  @override
  void add(List<int> data) {
    _out.addAll(data);
    if (!_handshakeAnswered) {
      if (_out.length < 30) return;
      _out.removeRange(0, 30);
      _handshakeAnswered = true;
      final hs = BytesBuilder()
        ..add('k3gV'.codeUnits)
        ..addByte(22)
        ..addByte(0)
        ..add(Uint8List(20)..[0] = nodeIdByte)
        ..add(Uint8List(4));
      _reply(hs.toBytes());
    }
    while (_out.isNotEmpty) {
      final command = _out[0];
      const framed = {141, 142, 150, 152, 156, 159};
      if (!framed.contains(command)) {
        _out.removeAt(0);
        continue;
      }
      if (_out.length < 5) return;
      final len = ByteData.sublistView(
        Uint8List.fromList(_out.sublist(1, 5)),
      ).getInt32(0, Endian.big);
      if (_out.length < 5 + len) return;
      final payload = Uint8List.fromList(_out.sublist(5, 5 + len));
      _out.removeRange(0, 5 + len);
      if (command == 159) {
        _replyCommand(
          160,
          (SubscribeResponse()..status = Status.OK).writeToBuffer(),
        );
      } else if (command == 152) {
        final ohId = FetchRequest.fromBuffer(payload).ohId;
        fetchOhIds.add(ohId);
        if (holdFetch?.call(ohId) ?? false) {
          heldFetches++;
          continue;
        }
        _replyCommand(
          153,
          (FetchResponse()..status = Status.OK).writeToBuffer(),
        );
      }
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

/// Scripted network: the first dial of an address connects at once, every
/// redial waits until the test opens that address's gate — so the test, not
/// the client's 2–6 s retry backoff, decides when a host comes back.
class _GatedNet {
  final Map<String, List<_HostSocket>> sockets = {};
  final Map<String, Completer<void>> _gates = {};

  /// Redials of [address] that are waiting at the gate.
  final Map<String, int> waitingRedials = {};

  Future<Socket> dial(String host, int port) async {
    final address = '$host:$port';
    final list = sockets.putIfAbsent(address, () => []);
    if (list.isNotEmpty) {
      waitingRedials[address] = (waitingRedials[address] ?? 0) + 1;
      await _gates.putIfAbsent(address, Completer<void>.new).future;
      waitingRedials[address] = waitingRedials[address]! - 1;
    }
    final socket = _HostSocket(int.parse(host.split('.').last));
    list.add(socket);
    return socket;
  }

  void openGate(String address) {
    final gate = _gates.putIfAbsent(address, Completer<void>.new);
    if (!gate.isCompleted) gate.complete();
  }

  _HostSocket latest(String address) => sockets[address]!.last;
}

void main() {
  setUpAll(() => ActivePeer.plaintextTransportForTesting = true);
  tearDownAll(() => ActivePeer.plaintextTransportForTesting = false);

  late List<String> logs;
  late void Function(String, LogLevel) previousSink;
  late LogLevel previousLevel;
  setUp(() {
    logs = [];
    previousSink = RpLog.sink;
    previousLevel = RpLog.minLevel;
    RpLog.minLevel = LogLevel.debug;
    RpLog.sink = (message, level) => logs.add(message);
  });
  tearDown(() {
    RpLog.sink = previousSink;
    RpLog.minLevel = previousLevel;
  });

  /// Two mailboxes; returns once a regular cycle has fetched A and is held
  /// on B's fetch — i.e. a cycle is running and A is already behind it.
  Future<(RedPandaLightClient, _Node, OHRegistration, OHRegistration)>
  cycleHeldOnB() async {
    final (client, socket) = await connectedClient();
    addTearDown(client.disconnect);
    final node = _Node(socket);
    final a = await client.registerOutboundHandle(channelId: 'a');
    final b = await client.registerOutboundHandle(channelId: 'b');
    // Let the start-up/registration polls settle, then catch the next cycle
    // on B's fetch.
    await Future.delayed(const Duration(milliseconds: 300));
    node.holdFetch = (ohId) => _sameBytes(ohId, b.ohId);
    await pumpUntil(
      () => node.held.isNotEmpty,
      timeout: const Duration(seconds: 8),
      reason: 'no cycle reached the fetch of B',
    );
    node.holdFetch = null;
    expect(
      node.fetchTimesOf(a.ohId),
      isNotEmpty,
      reason: 'the cycle fetches A before B',
    );
    return (client, node, a, b);
  }

  test('a Notify after the cycle fetched the OH triggers a follow-up '
      'fetch right after the cycle', () async {
    final (_, node, a, _) = await cycleHeldOnB();

    node.notify(a.ohId);
    await Future.delayed(const Duration(milliseconds: 100));
    expect(
      logs.where((l) => l.contains('Notify timing after-fetch')),
      hasLength(1),
    );
    final released = DateTime.now();
    node.answerFetch(); // B answered — the cycle can finish

    await pumpUntil(
      () => node.fetchTimesOf(a.ohId, after: released).isNotEmpty,
      // The next regular tick is ~5 s after the cycle started; the
      // follow-up has to come well before it.
      timeout: const Duration(milliseconds: 1500),
      reason: 'no follow-up fetch of A after the cycle',
    );
    await Future.delayed(const Duration(milliseconds: 200));
    expect(
      logs.where((l) => l.contains('poll follow-up fetched')),
      hasLength(1),
      reason: 'a fetch-only follow-up, not a full cycle',
    );
    expect(
      node.fetchTimesOf(node.held.single, after: released),
      isEmpty,
      reason: 'the follow-up fetches only the notified OH',
    );
  });

  test('a Notify before the cycle reaches the OH needs no follow-up', () async {
    final (client, socket) = await connectedClient();
    addTearDown(client.disconnect);
    final node = _Node(socket);
    final a = await client.registerOutboundHandle(channelId: 'a');
    final b = await client.registerOutboundHandle(channelId: 'b');
    await Future.delayed(const Duration(milliseconds: 300));
    // Hold the cycle on A's fetch: B is still ahead of it.
    node.holdFetch = (ohId) => _sameBytes(ohId, a.ohId);
    await pumpUntil(
      () => node.held.isNotEmpty,
      timeout: const Duration(seconds: 8),
      reason: 'no cycle reached the fetch of A',
    );
    node.holdFetch = null;

    node.notify(b.ohId);
    await Future.delayed(const Duration(milliseconds: 100));
    expect(
      logs.where((l) => l.contains('Notify timing before-fetch')),
      hasLength(1),
    );
    final released = DateTime.now();
    node.answerFetch();

    await Future.delayed(const Duration(milliseconds: 800));
    expect(
      node.fetchTimesOf(b.ohId, after: released),
      hasLength(1),
      reason: 'B is fetched once, by the running cycle',
    );
    expect(logs.where((l) => l.contains('poll follow-up fetched')), isEmpty);
  });

  test('a stream of Notifies is bounded: a burst, then one cycle per '
      'pollStartRefill, and the full cycle keeps running', () async {
    final (_, node, a, _) = await cycleHeldOnB();

    // Worst case: every answered fetch of A is immediately followed by a
    // Notify for A, so every cycle ends with a follow-up pending.
    node.afterFetchAnswered = (ohId) {
      if (_sameBytes(ohId, a.ohId)) node.notify(ohId);
    };
    node.notify(a.ohId);
    final stormStart = DateTime.now();
    node.answerFetch();
    const window = Duration(milliseconds: 6500);
    await Future.delayed(window);
    node.afterFetchAnswered = null;

    final times = node.fetchTimesOf(a.ohId, after: stormStart);
    // Faster than the regular cadence: more than the 1–2 fetches the 5 s
    // interval would give in this window ...
    expect(times.length, greaterThanOrEqualTo(5));
    // ... but bounded (every fetch of A here is one cycle start): at most
    // the burst plus one per pollStartRefill.
    const burst = RedPandaLightClient.pollBurst;
    expect(
      times.length,
      lessThanOrEqualTo(
        burst +
            window.inMilliseconds ~/
                RedPandaLightClient.pollStartRefill.inMilliseconds +
            1,
      ),
    );
    // Any burst + 1 consecutive starts span at least one pollStartRefill.
    for (var i = 0; i + burst < times.length; i++) {
      expect(
        times[i + burst].difference(times[i]),
        greaterThanOrEqualTo(
          RedPandaLightClient.pollStartRefill -
              const Duration(milliseconds: 30),
        ),
        reason: 'fetches $i..${i + burst} ran without a pause',
      );
    }
    // The follow-ups do not push the regular (full) cycle out: it still runs
    // within its 5 s interval.
    // B is fetched only by full cycles: one must have run since the held
    // cycle ended (a regular tick is due ~5 s after that cycle started).
    final b = node.held.single;
    expect(
      node.fetchTimesOf(b, after: stormStart),
      isNotEmpty,
      reason: 'the follow-ups starved the regular cycle',
    );
  });

  test('a Notify while the OH fetch is in flight gets a follow-up', () async {
    final (client, socket) = await connectedClient();
    addTearDown(client.disconnect);
    final node = _Node(socket);
    final a = await client.registerOutboundHandle(channelId: 'a');
    await Future.delayed(const Duration(milliseconds: 300));
    node.holdFetch = (ohId) => _sameBytes(ohId, a.ohId);
    await pumpUntil(
      () => node.held.isNotEmpty,
      timeout: const Duration(seconds: 8),
      reason: 'no cycle reached the fetch of A',
    );
    node.holdFetch = null;
    // The response may or may not contain the new item — fetch again.
    node.notify(a.ohId);
    await Future.delayed(const Duration(milliseconds: 100));
    expect(
      logs.where((l) => l.contains('Notify timing during-fetch')),
      hasLength(1),
    );
    final released = DateTime.now();
    node.answerFetch();
    await pumpUntil(
      () => node.fetchTimesOf(a.ohId, after: released).isNotEmpty,
      timeout: const Duration(milliseconds: 1500),
      reason: 'no follow-up fetch of A after the in-flight Notify',
    );
  });

  test('disconnect during a cycle drops the queued follow-up', () async {
    final (client, node, a, _) = await cycleHeldOnB();
    node.notify(a.ohId);
    await Future.delayed(const Duration(milliseconds: 100));
    await client.disconnect();
    final released = DateTime.now();
    node.answerFetch();
    await Future.delayed(const Duration(milliseconds: 1500));
    expect(node.fetchTimesOf(a.ohId, after: released), isEmpty);
  });

  test('clustered Notifies (a message and its ACKs) are each fetched at '
      'once', () async {
    final (client, socket) = await connectedClient();
    addTearDown(client.disconnect);
    final node = _Node(socket);
    final a = await client.registerOutboundHandle(channelId: 'a');
    // Past the start-up polls, mid-interval: the next regular tick is seconds
    // away, the poll-start budget is full.
    await Future.delayed(const Duration(milliseconds: 2500));
    final start = DateTime.now();
    // pollBurst Notifies, each right after the previous one's fetch answered.
    var sent = 1;
    node.afterFetchAnswered = (ohId) {
      if (sent < RedPandaLightClient.pollBurst) {
        sent++;
        node.notify(ohId);
      }
    };
    node.notify(a.ohId);
    await pumpUntil(
      () =>
          node.fetchTimesOf(a.ohId, after: start).length >=
          RedPandaLightClient.pollBurst,
      // A pause for budget anywhere in the cluster would take ≥ 500 ms.
      timeout: const Duration(milliseconds: 700),
      reason: 'a clustered Notify waited for a pause',
    );
  });

  test('Notifies for the redundant copies of one message share one '
      'follow-up', () async {
    final (client, socket) = await connectedClient();
    addTearDown(client.disconnect);
    final node = _Node(socket);
    final ohs = [
      for (final c in ['a', 'b', 'c'])
        await client.registerOutboundHandle(channelId: c),
    ];
    await Future.delayed(const Duration(milliseconds: 2500));
    final start = DateTime.now();
    // The partner deposits into every mailbox: three Notifies within a few ms.
    // Sent synchronously: on a loaded runner, real gaps could add up past
    // the coalesce window and make this test flaky.
    for (final oh in ohs) {
      node.notify(oh.ohId);
    }
    await pumpUntil(
      () => ohs.every(
        (oh) => node.fetchTimesOf(oh.ohId, after: start).isNotEmpty,
      ),
      timeout: const Duration(milliseconds: 700),
      reason: 'not every notified mailbox was fetched',
    );
    final followUps = logs.where((l) => l.contains('poll follow-up fetched'));
    expect(followUps, hasLength(1));
    expect(followUps.single, contains('from 3 notified OH(s)'));
  });

  group('T167 review: a reconnect during a follow-up still gets its '
      'catch-up poll', () {
    const nodeA = '10.0.0.1:59558';
    const nodeB = '10.0.0.2:59558';
    late _GatedNet net;
    late RedPandaLightClient client;
    late OHRegistration ohA;
    late OHRegistration ohB;

    Future<OHRegistration> restoredOn(String host, int seed) async =>
        OHRegistration(
          ohId: List.generate(20, (i) => (i * 7 + seed * 31) & 0xff),
          keypair: await OHKeypair.generate(),
          expiresAtMs: DateTime.now()
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          serverEndpoint: host,
        );

    /// Two nodes, each hosting one of our mailboxes. [fetchResponseTimeout]
    /// is how long a fetch into a dead connection stays pending.
    Future<void> start({required Duration fetchResponseTimeout}) async {
      net = _GatedNet();
      final keys = await KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: const [nodeA, nodeB],
        peerRepository: InMemoryPeerRepository(),
        socketFactory: net.dial,
        fetchResponseTimeout: fetchResponseTimeout,
      );
      addTearDown(client.disconnect);
      ohA = await restoredOn(nodeA, 1);
      ohB = await restoredOn(nodeB, 2);
      await client.restoreOutboundHandle(ohA);
      await client.restoreOutboundHandle(ohB);
      await client.connect();
      await pumpUntil(
        () => client.activePeerAddresses.length == 2,
        timeout: const Duration(seconds: 10),
        reason: 'both scripted nodes connected',
      );
    }

    /// B drops and its redial waits at the gate. Then a full cycle is
    /// pulled forward (`onResume`: full cycle in 1 s, fast cadence) and the
    /// test waits for its end, so the next regular cycle is
    /// [RedPandaLightClient.activePollInterval] (5 s) away.
    Future<void> dropBAndWaitForCycleEnd() async {
      net.latest(nodeB).dropFromNodeSide();
      await pumpUntil(
        () => (net.waitingRedials[nodeB] ?? 0) > 0,
        timeout: const Duration(seconds: 15),
        reason: 'the client redials B (held at the gate)',
      );
      final seen = logs.length;
      client.onResume();
      await pumpUntil(
        () => logs.skip(seen).any((l) => l.contains('poll cycle fetched')),
        timeout: const Duration(seconds: 10),
        reason: 'a full poll cycle ended',
      );
    }

    /// Notify for A's mailbox; A holds the follow-up fetch.
    Future<DateTime> followUpHeldOnA() async {
      final a = net.latest(nodeA);
      a.holdFetch = (ohId) => _sameBytes(ohId, ohA.ohId);
      final t0 = DateTime.now();
      a.notify(ohA.ohId);
      await pumpUntil(
        () => a.heldFetches > 0,
        timeout: const Duration(seconds: 2),
        reason: 'the follow-up fetch of A is in flight',
      );
      expect(
        logs.where((l) => l.contains('poll follow-up fetched')),
        isEmpty,
        reason: 'precondition: the follow-up is still running',
      );
      return t0;
    }

    /// The catch-up poll is due ~1 s after the reconnect; the regular cycle
    /// ~5 s after the Notify. 3 s leaves ~2 s on either side.
    const catchUpDeadline = Duration(seconds: 3);

    test('a mailbox host that reconnects while the follow-up runs '
        '(_onPeerConnected)', () async {
      await start(fetchResponseTimeout: const Duration(seconds: 10));
      await dropBAndWaitForCycleEnd();
      final t0 = await followUpHeldOnA();

      // B comes back while the client stays connected over A: the
      // per-host path, not the client-wide connect edge.
      net.openGate(nodeB);
      await pumpUntil(
        () =>
            client.activePeerAddresses.contains(nodeB) &&
            net.sockets[nodeB]!.length == 2,
        timeout: const Duration(seconds: 2),
        reason: 'B reconnected',
      );
      expect(
        logs.any((l) => l.contains('a mailbox host reconnected')),
        isTrue,
        reason: 'precondition: _onPeerConnected handled B',
      );
      net.latest(nodeA).releaseFetches(); // the follow-up ends

      final b = net.latest(nodeB);
      await pumpUntil(
        () => b.fetched(ohB.ohId),
        timeout: t0.add(catchUpDeadline).difference(DateTime.now()),
        reason:
            "B's mailbox was not fetched after the reconnect — the "
            'catch-up poll was dropped while the follow-up ran',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
      'the client-wide connect edge during the follow-up (_updateStatus)',
      () async {
        // A fetch into a dead connection stays pending until this timeout;
        // it ends the follow-up shortly after the reconnect (A is gone, so
        // nobody can answer it).
        await start(fetchResponseTimeout: const Duration(seconds: 1));
        await dropBAndWaitForCycleEnd();
        final t0 = await followUpHeldOnA();

        // A drops too: no peer left, the follow-up's fetch stays pending.
        // A's own redial stays at its gate for the rest of the test.
        net.latest(nodeA).dropFromNodeSide();
        await pumpUntil(
          () => client.activePeerAddresses.isEmpty,
          timeout: const Duration(seconds: 2),
          reason: 'the client lost every peer',
        );
        net.openGate(nodeB);
        await pumpUntil(
          () => client.activePeerAddresses.contains(nodeB),
          timeout: const Duration(seconds: 2),
          reason: 'B reconnected (client-wide connect edge)',
        );
        expect(
          logs.any((l) => l.contains('a mailbox host reconnected')),
          isFalse,
          reason: 'precondition: the edge, not _onPeerConnected, handled B',
        );

        final b = net.latest(nodeB);
        await pumpUntil(
          () => b.fetched(ohB.ohId),
          timeout: t0.add(catchUpDeadline).difference(DateTime.now()),
          reason:
              "B's mailbox was not fetched after the reconnect — the "
              'catch-up poll was dropped while the follow-up ran',
        );
        expect(
          logs.any((l) => l.contains('poll follow-up fetched')),
          isTrue,
          reason: 'precondition: the follow-up ended (fetch timeout)',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
