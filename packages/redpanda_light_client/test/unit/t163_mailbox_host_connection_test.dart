import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

/// T163: the connection to a node hosting one of our own mailboxes must not
/// be given up by the roaming rotation, and a host that reconnects while the
/// client stays connected must get its Notify subscription back.
///
/// Seen in the 5-node conversation lab: the rotation closed the host link
/// every ~15 s (`disconnected intentionally (Rotation)`), fetches failed with
/// `host node … not connected`, the Notify subscription was never renewed
/// after the redial, and deliveries in one direction fell back to the 5 s
/// poll (4–5 s per message, rounds over the 10 s budget).

/// Scripted node socket (plaintext, see [ActivePeer.plaintextTransportForTesting]).
/// Answers register (150), subscribe (159) and fetch (152) with OK and records
/// every subscribe it sees.
class _NodeSocket implements Socket {
  _NodeSocket(this.nodeIdByte);

  final int nodeIdByte;
  final _incoming = StreamController<Uint8List>();
  final List<int> _out = [];
  bool _handshakeAnswered = false;
  bool closedByClient = false;
  int registers = 0;
  int subscribes = 0;

  /// While true, register requests (150) are counted but not answered until
  /// [releaseRegisters].
  bool holdRegisters = false;
  int _heldRegisters = 0;

  /// Status the node answers register requests with.
  Status registerStatus = Status.OK;

  /// A real node answers with the (possibly clamped) expiry; without it the
  /// handle would count as locally expired.
  static List<int> _registerResponse(Status status) =>
      (RegisterOhResponse()
            ..status = status
            ..expiresAtMs = fixnum.Int64(
              DateTime.now()
                  .add(const Duration(days: 7))
                  .millisecondsSinceEpoch,
            ))
          .writeToBuffer();

  void releaseRegisters() {
    holdRegisters = false;
    for (; _heldRegisters > 0; _heldRegisters--) {
      _replyCommand(151, _registerResponse(registerStatus));
    }
  }

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

  /// The node drops the connection (not the client).
  void dropFromNodeSide() => _incoming.close();

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
      _out.removeRange(0, 5 + len);
      if (command == 150) {
        registers++;
        if (holdRegisters) {
          _heldRegisters++;
          continue;
        }
        _replyCommand(151, _registerResponse(registerStatus));
      } else if (command == 159) {
        subscribes++;
        _replyCommand(
          160,
          (SubscribeResponse()..status = Status.OK).writeToBuffer(),
        );
      } else if (command == 152) {
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
  void destroy() {
    closedByClient = true;
    _incoming.close();
  }

  @override
  Future<void> close() async {
    closedByClient = true;
    await _incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake network of scripted nodes; every dial gets a fresh socket.
class _Net {
  final Map<String, List<_NodeSocket>> sockets = {};

  Future<Socket> dial(String host, int port) async {
    final address = '$host:$port';
    final list = sockets.putIfAbsent(address, () => []);
    final socket = _NodeSocket(int.parse(host.split('.').last));
    list.add(socket);
    return socket;
  }

  _NodeSocket latest(String address) => sockets[address]!.last;

  bool everClosed(String address) =>
      sockets[address]?.any((s) => s.closedByClient) ?? false;
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

final _now = DateTime(2026, 11, 22, 12);

({String address, DateTime connectedSince, double score}) _peer(
  String a,
  int ageSeconds, {
  double score = 1,
}) => (
  address: a,
  connectedSince: _now.subtract(Duration(seconds: ageSeconds)),
  score: score,
);

({String address, int latencyMs}) _lat(String a, int ms) =>
    (address: a, latencyMs: ms);

String _node(int i) => '10.0.0.$i:59558';

Future<OHRegistration> _restoredOh(int seed, String host) async =>
    OHRegistration(
      ohId: List.generate(20, (i) => (i + seed * 31) & 0xff),
      keypair: await OHKeypair.generate(),
      expiresAtMs: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      serverEndpoint: host,
    );

void main() {
  setUpAll(() => ActivePeer.plaintextTransportForTesting = true);
  tearDownAll(() => ActivePeer.plaintextTransportForTesting = false);

  group('T163 pickRotationVictim', () {
    // Three high-scored peers, then the two oldest-but-weakest ones.
    final peers = [
      _peer('c1', 60, score: 9),
      _peer('c2', 60, score: 8),
      _peer('c3', 50, score: 7),
      _peer('host', 70, score: 1), // oldest overall
      _peer('roam', 20, score: 2),
    ];

    String? pick(
      Iterable<({String address, DateTime connectedSince, double score})> ps, {
      Set<String> protected = const {},
      int? slotsTaken,
      int limit = RedPandaLightClient.maxConnections,
    }) => RedPandaLightClient.pickRotationVictim(
      verifiedPeers: ps,
      protected: protected,
      slotsTaken: slotsTaken ?? ps.length,
      limit: limit,
      now: _now,
    );

    test('without protection the oldest roaming peer is rotated', () {
      expect(pick(peers), 'host');
    });

    test('a mailbox host is never picked; another peer rotates instead', () {
      // The pinned host uses one core slot, so the third-best peer is now
      // roaming and, being the oldest roaming peer, the victim.
      expect(pick(peers, protected: {'host'}), 'c3');
    });

    test('hosts filling the roaming slots do not stop the rotation', () {
      // Review B: with the old "not in the best three" rule, hosts on both
      // roaming slots left no victim. Three pinned hosts use up the core
      // budget; both remaining peers rotate.
      final ps = [
        _peer('h1', 90, score: 1),
        _peer('h2', 90, score: 1),
        _peer('h3', 90, score: 1),
        _peer('a', 30, score: 9),
        _peer('b', 40, score: 8),
      ];
      expect(pick(ps, protected: {'h1', 'h2', 'h3'}), 'b');
    });

    test('all slots held by hosts: only the extra slot rotates', () {
      final hosts = {for (var i = 1; i <= 5; i++) 'h$i'};
      final five = [for (final h in hosts) _peer(h, 90)];
      expect(pick(five, protected: hosts), isNull);
      final six = [...five, _peer('x', 30)];
      expect(
        pick(
          six,
          protected: hosts,
          limit: RedPandaLightClient.maxConnections + 1,
        ),
        'x',
      );
    });

    test('no victim before the slots are full or before minAge', () {
      expect(pick(peers.take(4)), isNull);
      expect(pick(peers, slotsTaken: 4), isNull);
      expect(
        pick([
          ...peers.take(3),
          _peer('a', 9, score: 1),
          _peer('b', 5, score: 1),
        ]),
        isNull,
      );
    });
  });

  group('T163 connectionLimit', () {
    String h(int i) => 'h$i';
    final hosts = {for (var i = 1; i <= 6; i++) h(i)};

    test('one extra slot only while every regular slot is a host', () {
      const max = RedPandaLightClient.maxConnections;
      int limitFor(List<String> peers) => RedPandaLightClient.connectionLimit(
        peerAddresses: peers,
        protected: hosts,
      );
      expect(limitFor(['a', 'b', 'c', 'd', 'e']), max);
      expect(limitFor([h(1), h(2), h(3), h(4), 'a']), max);
      expect(limitFor([h(1), h(2), h(3), h(4), h(5)]), max + 1);
      expect(limitFor([h(1), h(2), h(3), h(4), h(5), 'x']), max + 1);
      expect(
        limitFor([h(1), h(2), h(3), h(4), h(5), h(6)]),
        max + 1,
        reason: 'never more than one extra connection',
      );
    });
  });

  group('T163 pickOverCapacityVictims', () {
    test('trims the slowest unprotected peers, keeps hosts', () {
      final victims = RedPandaLightClient.pickOverCapacityVictims(
        peers: [
          _lat('fast', 5),
          _lat('host', 900), // slowest of all
          _lat('mid', 50),
          _lat('slow', 300),
          _lat('a', 10),
          _lat('b', 20),
        ],
        protected: {'host'},
        limit: 5,
      );
      expect(victims, ['slow']);
    });

    test('only protected peers left: the slowest host goes', () {
      final victims = RedPandaLightClient.pickOverCapacityVictims(
        peers: [_lat('h1', 10), _lat('h2', 30), _lat('h3', 20)],
        protected: {'h1', 'h2', 'h3'},
        limit: 2,
      );
      expect(victims, ['h2']);
    });

    test('nothing to trim at or below the limit', () {
      expect(
        RedPandaLightClient.pickOverCapacityVictims(
          peers: [_lat('a', 1), _lat('b', 2)],
          protected: const {},
          limit: 2,
        ),
        isEmpty,
      );
    });
  });

  group('T163 connection check with scripted nodes', () {
    late _Net net;
    late InMemoryPeerRepository repo;
    late RedPandaLightClient client;

    Future<void> start(
      List<String> seeds, {
      List<OHRegistration> restored = const [],
      int expectConnected = 5,
    }) async {
      net = _Net();
      repo = InMemoryPeerRepository();
      final keys = await KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: seeds,
        peerRepository: repo,
        socketFactory: net.dial,
      );
      for (final oh in restored) {
        await client.restoreOutboundHandle(oh);
      }
      await client.connect();
      await _pumpUntil(
        () => client.activePeerAddresses.length == expectConnected,
        timeout: const Duration(seconds: 10),
        reason: '$expectConnected scripted nodes connected',
      );
    }

    tearDown(() => client.disconnect());

    final five = [for (var i = 1; i <= 5; i++) _node(i)];

    test(
      'rotation keeps the mailbox host and rotates a non-host peer',
      () async {
        await start(five);
        final oh = await client.registerOutboundHandle();
        final host = oh.serverEndpoint!;
        final hostSocket = net.latest(host);
        // Push the host out of the repository's best three, so the pre-T163
        // rule ("not in the best three" = roaming) makes it the oldest
        // roaming peer and thus the victim. Asserted below, so a change of
        // the score formula cannot make this test pass vacuously.
        for (var i = 0; i < 20; i++) {
          repo.updatePeer(host, isFailure: true);
        }
        final others = five.where((n) => n != host).toList();

        // Rotation candidates need 10 s of age; the check runs every 3 s.
        await _pumpUntil(
          () => others.any(net.everClosed),
          timeout: const Duration(seconds: 18),
          reason: 'a non-host peer was rotated',
        );
        expect(
          repo.getBestPeers(3).map((p) => p.address),
          isNot(contains(host)),
          reason: 'precondition: the host is a roaming peer by score',
        );
        expect(
          hostSocket.closedByClient,
          isFalse,
          reason: 'the mailbox host must not be rotated away',
        );
        expect(net.sockets[host], hasLength(1), reason: 'host never redialled');
        expect(client.activePeerAddresses, contains(host));
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );

    test(
      'a mailbox host that reconnects is re-subscribed exactly once',
      () async {
        await start(five);
        final oh = await client.registerOutboundHandle();
        final host = oh.serverEndpoint!;
        final first = net.latest(host);
        await _pumpUntil(
          () => first.subscribes >= 1,
          timeout: const Duration(seconds: 5),
          reason: 'initial subscribe after registration',
        );

        // The host drops the connection; the other four stay up, so the
        // client-wide connect edge never fires again.
        first.dropFromNodeSide();
        await _pumpUntil(
          () =>
              net.sockets[host]!.length >= 2 &&
              client.activePeerAddresses.contains(host),
          timeout: const Duration(seconds: 15),
          reason: 'host redialled after its backoff',
        );
        final second = net.latest(host);
        await _pumpUntil(
          () => second.subscribes >= 1,
          timeout: const Duration(seconds: 5),
          reason: 'the reconnected host gets a SubscribeRequest',
        );
        // Let any duplicate show up before counting.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(first.subscribes, 1, reason: 'registration subscribe only');
        expect(second.subscribes, 1, reason: 'one re-subscribe, no duplicate');
        for (final n in five.where((n) => n != host)) {
          expect(
            net.sockets[n]!.every((s) => s.subscribes == 0),
            isTrue,
            reason: 'subscribes go only to the handle\'s own host ($n)',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );

    test(
      'with every slot held by a host, one extra roaming peer rotates',
      () async {
        // Review B: five mailbox hosts on five slots. Two more nodes become
        // known only after all hosts are connected (as from a peer list).
        final restored = [
          for (var i = 0; i < 5; i++) await _restoredOh(i, five[i]),
        ];
        await start(five, restored: restored);
        final n6 = _node(6);
        final n7 = _node(7);
        repo.updatePeer(n6);
        repo.updatePeer(n7);

        // The extra slot must be used, rotate, and be refilled. Which new
        // node the refill picks is the random slot filling's choice (the
        // rotated node's 2 s backoff is shorter than the 3 s check, so it
        // may be picked again) — not asserted.
        final fresh = [n6, n7];
        int dials() =>
            fresh.fold(0, (n, a) => n + (net.sockets[a]?.length ?? 0));
        var maxSeen = 0;
        await _pumpUntil(
          () {
            final open = client.activePeerAddresses.length;
            if (open > maxSeen) maxSeen = open;
            return fresh.any(net.everClosed) && dials() >= 2;
          },
          timeout: const Duration(seconds: 35),
          reason: 'the extra slot was used, rotated and refilled',
        );
        expect(
          maxSeen,
          lessThanOrEqualTo(RedPandaLightClient.maxConnections + 1),
        );
        for (final h in five) {
          expect(net.everClosed(h), isFalse, reason: 'host $h kept');
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'the target of a pending registration is protected until it lands',
      () async {
        await start(five);
        for (final n in five) {
          net.latest(n).holdRegisters = true;
        }
        expect(client.ownMailboxHostAddressesForTesting, isEmpty);

        final pending = client.registerOutboundHandle();
        await _pumpUntil(
          () => five.any((n) => net.latest(n).registers == 1),
          timeout: const Duration(seconds: 5),
          reason: 'register request sent',
        );
        final target = five.firstWhere((n) => net.latest(n).registers == 1);
        expect(client.registeredOutboundHandles, isEmpty);
        expect(client.ownMailboxHostAddressesForTesting, {target});

        net.latest(target).releaseRegisters();
        final oh = await pending;
        expect(oh.serverEndpoint, target);
        expect(client.ownMailboxHostAddressesForTesting, {target});

        // A failed registration releases its claim.
        for (final n in five) {
          net.latest(n)
            ..registerStatus = Status.RATE_LIMIT
            ..holdRegisters = false;
        }
        await expectLater(
          client.registerOutboundHandle(),
          throwsA(isA<RateLimitException>()),
        );
        // Expire the first mailbox: any claim the failed call leaked (even
        // one on the same node) would still show up.
        oh.expiresAtMs = DateTime.now().millisecondsSinceEpoch - 1;
        expect(client.ownMailboxHostAddressesForTesting, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('a locally expired mailbox no longer protects its host', () async {
      await start(five);
      final oh = await client.registerOutboundHandle();
      expect(client.ownMailboxHostAddressesForTesting, {oh.serverEndpoint});
      oh.expiresAtMs = DateTime.now().millisecondsSinceEpoch - 1;
      expect(client.ownMailboxHostAddressesForTesting, isEmpty);
    });
  });
}
