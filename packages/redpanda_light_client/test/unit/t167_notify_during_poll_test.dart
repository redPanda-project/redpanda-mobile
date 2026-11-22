import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';

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
    // Three Notifies, each right after the previous one's fetch answered.
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
    for (final oh in ohs) {
      node.notify(oh.ohId);
      await Future.delayed(const Duration(milliseconds: 3));
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
}
