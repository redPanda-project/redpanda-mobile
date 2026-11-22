import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
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
        _replyCommand(
          151,
          (RegisterOhResponse()..status = Status.OK).writeToBuffer(),
        );
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

({String address, DateTime connectedSince}) _peer(String a, int ageSeconds) => (
  address: a,
  connectedSince: DateTime(
    2026,
    11,
    22,
    12,
  ).subtract(Duration(seconds: ageSeconds)),
);

void main() {
  setUpAll(() => ActivePeer.plaintextTransportForTesting = true);
  tearDownAll(() => ActivePeer.plaintextTransportForTesting = false);

  group('T163 pickRotationVictim', () {
    final now = DateTime(2026, 11, 22, 12);
    const core = {'c1', 'c2', 'c3'};
    final peers = [
      _peer('c1', 60),
      _peer('c2', 60),
      _peer('c3', 60),
      _peer('host', 40), // oldest roaming peer
      _peer('roam', 20),
    ];

    test('without protection the oldest roaming peer is rotated', () {
      expect(
        RedPandaLightClient.pickRotationVictim(
          verifiedPeers: peers,
          core: core,
          protected: const {},
          now: now,
        ),
        'host',
      );
    });

    test('a mailbox host is never picked; the other roaming peer is', () {
      expect(
        RedPandaLightClient.pickRotationVictim(
          verifiedPeers: peers,
          core: core,
          protected: const {'host'},
          now: now,
        ),
        'roam',
        reason:
            'rotation must keep running for nodes without an own mailbox — '
            'the protected host still counts toward the full roaming slots',
      );
    });

    test('no victim when every old-enough roaming peer is a host', () {
      expect(
        RedPandaLightClient.pickRotationVictim(
          verifiedPeers: peers,
          core: core,
          protected: const {'host', 'roam'},
          now: now,
        ),
        isNull,
      );
    });

    test('no victim before the roaming slots are full or before minAge', () {
      expect(
        RedPandaLightClient.pickRotationVictim(
          verifiedPeers: peers.take(4),
          core: core,
          protected: const {},
          now: now,
        ),
        isNull,
      );
      expect(
        RedPandaLightClient.pickRotationVictim(
          verifiedPeers: [...peers.take(3), _peer('a', 9), _peer('b', 5)],
          core: core,
          protected: const {},
          now: now,
        ),
        isNull,
      );
    });
  });

  group('T163 connection check with 5 nodes', () {
    late _Net net;
    late InMemoryPeerRepository repo;
    late RedPandaLightClient client;
    final nodes = [for (var i = 1; i <= 5; i++) '10.0.0.$i:59558'];

    setUp(() async {
      net = _Net();
      repo = InMemoryPeerRepository();
      final keys = await KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: nodes,
        peerRepository: repo,
        socketFactory: net.dial,
      );
      await client.connect();
      await _pumpUntil(
        () => client.activePeerAddresses.length == 5,
        timeout: const Duration(seconds: 10),
        reason: 'all 5 scripted nodes connected',
      );
    });

    tearDown(() => client.disconnect());

    test(
      'rotation keeps the mailbox host and rotates a non-host roaming peer',
      () async {
        final oh = await client.registerOutboundHandle();
        final host = oh.serverEndpoint!;
        final hostSocket = net.latest(host);
        // Push the host out of the repository's best three, so it is a
        // roaming peer — the case the lab hit (scores of local nodes are
        // near-identical and the best three shift with every ping).
        for (var i = 0; i < 20; i++) {
          repo.updatePeer(host, isFailure: true);
        }
        final others = nodes.where((n) => n != host).toList();

        // Roaming peers become rotation candidates after 10 s; the check runs
        // every 3 s. 18 s covers at least one rotation.
        await _pumpUntil(
          () => others.any((n) => net.sockets[n]!.any((s) => s.closedByClient)),
          timeout: const Duration(seconds: 18),
          reason: 'a non-host roaming peer was rotated',
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
      'a mailbox host that reconnects is re-subscribed for Notify',
      () async {
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
        for (final n in nodes.where((n) => n != host)) {
          expect(
            net.sockets[n]!.every((s) => s.subscribes == 0),
            isTrue,
            reason: 'subscribes go only to the handle\'s own host ($n)',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );
  });
}
