import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/counterpart_oh_update.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

import '../helpers/garlic_test_utils.dart';

/// T42 multi-OH / multi-deposit unit tests. A scripted in-memory Socket plays
/// the single connected node; the client's peer repository is pre-seeded with
/// relay candidates so each deposit travels its own GARLIC route (T45: sends
/// are garlic-only, one hop-disjoint route per counterpart OH — never a direct
/// FlaschenpostPut). The mock captures the command-142 frames and peels them
/// with the known relay keys to recover which OH each route deposits into. The
/// exchange stays plaintext (the encryption handshake is never completed;
/// framing is identical).
class ScriptedSocket implements Socket {
  @override
  Future<void> get done => Completer<void>().future;

  final _incoming = StreamController<Uint8List>();
  final List<int> _outBuffer = [];
  bool _handshakeAnswered = false;

  void Function(int command, Uint8List payload)? onCommandFrame;

  static Uint8List nodeHandshake() {
    final b = BytesBuilder();
    b.add('k3gV'.codeUnits);
    b.addByte(22);
    b.addByte(0);
    b.add(Uint8List(20));
    b.add(Uint8List(4));
    return b.toBytes();
  }

  void reply(List<int> data) {
    if (!_incoming.isClosed) _incoming.add(Uint8List.fromList(data));
  }

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
    if (!_handshakeAnswered) {
      if (_outBuffer.length < 30) return;
      _outBuffer.removeRange(0, 30);
      _handshakeAnswered = true;
      reply(nodeHandshake());
    }
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
  void destroy() => _incoming.close();

  @override
  Future<void> close() async => _incoming.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const liveEndpoint = 'scripted:1';

Future<(RedPandaLightClient, ScriptedSocket, List<TestHop>)> connectedClient({
  Duration depositResponseTimeout = const Duration(seconds: 10),
  int hopCount = 3,
}) async {
  final socket = ScriptedSocket();
  final repo = InMemoryPeerRepository();
  final relays = <TestHop>[];
  for (var i = 0; i < hopCount; i++) {
    final hop = await TestHop.generate(i + 1);
    relays.add(hop);
    repo.updatePeer(
      '10.2.0.$i:5000',
      nodeId: HEX.encode(hop.nodeId),
      encryptionPublicKey: HEX.encode(hop.keys.publicKey),
    );
  }
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: [liveEndpoint],
    depositResponseTimeout: depositResponseTimeout,
    peerRepository: repo,
    socketFactory: (h, p) async {
      if (h == 'scripted') return socket;
      throw const SocketException('test: unreachable');
    },
  );
  await client.connect();
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (client.activePeerAddresses.isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('peer never became handshake-verified');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return (client, socket, relays);
}

Future<void> pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
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

final channelKey = List<int>.generate(32, (i) => i + 1);

OHDescriptor counterpartOh(int seed, String endpoint) => OHDescriptor(
  serverEndpoint: endpoint,
  handleId: List<int>.generate(20, (i) => (seed + i) & 0xFF),
  authPublicKey: List<int>.generate(32, (i) => (seed * 2 + i) & 0xFF),
);

void main() {
  group('T45 multi-OH: one garlic route per counterpart OH (never direct)', () {
    test(
      'fans out to every counterpart OH over garlic; no direct deposit',
      () async {
        // Six relays so the two 3-hop routes can be fully disjoint.
        final (client, socket, relays) = await connectedClient(hopCount: 6);
        addTearDown(client.disconnect);

        final ohA = counterpartOh(10, 'nodeA:1');
        final ohB = counterpartOh(90, 'nodeB:2');

        final garlicFrames = <Uint8List>[];
        var directDeposits = 0;
        socket.onCommandFrame = (command, payload) {
          if (command == 142) garlicFrames.add(payload);
          if (command == 141) directDeposits++;
        };

        client.addChannelKeys(
          'chan',
          channelKey,
          counterpartOhSet: [ohA, ohB],
          isChannelCreator: true,
        );

        final id = await client.sendMessage('chan', 'hello redundancy');
        expect(id, isNotEmpty);

        await pumpUntil(
          () => garlicFrames.length >= 2,
          reason:
              'the send did not fan out to both counterpart OHs over garlic',
        );
        expect(
          directDeposits,
          equals(0),
          reason: 'no deposit may go out direct',
        );
        // Peel each route and confirm both counterpart OHs are covered — with disjoint
        // relay hop sets across the two routes (best-effort anti-correlation).
        final ohIds = <String>{};
        final firstHops = <String>[];
        for (final frame in garlicFrames.take(2)) {
          firstHops.add(HEX.encode(ParsedPacket.parse(frame).nextHop));
          final deposit = await peelGarlicDeposit(frame, relays);
          ohIds.add(HEX.encode(deposit!.ohId));
        }
        expect(ohIds, contains(HEX.encode(ohA.handleId)));
        expect(ohIds, contains(HEX.encode(ohB.handleId)));
        expect(client.lastSendHopCount, greaterThan(0));
        expect(
          firstHops.toSet(),
          hasLength(2),
          reason: 'the two routes must start on disjoint relay hops',
        );
      },
    );

    test('fan-out is non-blocking: garlic submission never waits on a '
        'confirmation (T39: submit != delivered)', () async {
      // Garlic is fire-and-forget: sendMessage returns once the packets are
      // submitted, regardless of whether any OH host is reachable. Delivery is
      // confirmed asynchronously by the R-ACK (or re-sent on its timeout) — a
      // dead OH host can never stall the send call.
      final (client, socket, _) = await connectedClient();
      addTearDown(client.disconnect);

      final ohA = counterpartOh(10, 'deadhost:1');
      final ohB = counterpartOh(90, 'livehost:2');

      var garlic = 0;
      socket.onCommandFrame = (command, payload) {
        if (command == 142) garlic++;
        // No FlaschenpostPutResponse is ever sent — irrelevant for garlic.
      };

      client.addChannelKeys(
        'chan',
        channelKey,
        counterpartOhSet: [ohA, ohB],
        isChannelCreator: true,
      );

      final started = DateTime.now();
      final id = await client
          .sendMessage('chan', 'reach me via any live OH')
          .timeout(const Duration(seconds: 3));
      final elapsed = DateTime.now().difference(started);
      expect(id, isNotEmpty);
      expect(elapsed, lessThan(const Duration(seconds: 3)));
      await pumpUntil(() => garlic >= 2, reason: 'both routes must be sent');
    });

    test(
      'no route can be built ⇒ throws, nothing sent (stays pending)',
      () async {
        // No relay candidates AND no self-hop identity (scripted handshake sends
        // no 64-byte export): a garlic route cannot be formed, so the message
        // stays pending — and NOTHING goes out as a direct deposit.
        final (client, socket, _) = await connectedClient(hopCount: 0);
        addTearDown(client.disconnect);

        final ohA = counterpartOh(10, 'nodeA:1');
        final ohB = counterpartOh(90, 'nodeB:2');

        var frames = 0;
        socket.onCommandFrame = (command, payload) {
          if (command == 141 || command == 142) frames++;
        };

        client.addChannelKeys(
          'chan',
          channelKey,
          counterpartOhSet: [ohA, ohB],
          isChannelCreator: true,
        );

        await expectLater(
          client.sendMessage('chan', 'nobody to route through'),
          throwsA(isA<DepositException>()),
        );
        expect(frames, equals(0), reason: 'no deposit of any kind may be sent');
      },
    );
  });

  group('T42 receive: oh_update array grows the counterpart OH set', () {
    test(
      'a 2-descriptor announce makes future sends fan out to both',
      () async {
        final (client, socket, relays) = await connectedClient();
        addTearDown(client.disconnect);

        final ohA = counterpartOh(10, 'nodeA:1');
        final ohB = counterpartOh(90, 'nodeB:2');

        // The partner announces BOTH mailboxes as a JSON array.
        final partnerSession = await RatchetSession.create(
          channelKey: channelKey,
          isChannelCreator: true,
        );
        final announce = ChannelMessage(
          messageId: Uint8List.fromList(List<int>.generate(16, (i) => i)),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          content: '',
          ohUpdate: Uint8List.fromList(
            utf8.encode(jsonEncode([ohA.toJsonMap(), ohB.toJsonMap()])),
          ),
        );
        final announcePayload = await partnerSession.encrypt(announce, 'chan');

        final garlicFrames = <Uint8List>[];
        var announceDelivered = false;
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
            final response = FetchResponse()..status = Status.OK;
            if (!announceDelivered) {
              announceDelivered = true;
              response
                ..nextCursor = fixnum.Int64(1)
                ..items.add(
                  MailItem(
                    payload: announcePayload,
                    receivedAtMs: fixnum.Int64(
                      DateTime.now().millisecondsSinceEpoch,
                    ),
                  ),
                );
            }
            socket.replyCommand(153, response.writeToBuffer());
          } else if (command == 142) {
            garlicFrames.add(payload);
          }
        };

        // We start knowing only ohA (from the QR/primary).
        client.addChannelKeys(
          'chan',
          channelKey,
          counterpartOhId: ohA.handleId,
          counterpartOhEndpoint: ohA.serverEndpoint,
          isChannelCreator: false,
        );
        final ownOh = OHRegistration(
          ohId: List.generate(20, (i) => 200 + (i & 0x3F)),
          keypair: await OHKeypair.generate(),
          expiresAtMs: DateTime.now()
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          channelId: 'chan',
          serverEndpoint: liveEndpoint,
        );
        await client.restoreOutboundHandle(ownOh);

        final updates = <CounterpartOhUpdate>[];
        final sub = client.stateUpdates.of<CounterpartOhUpdate>().listen(
          updates.add,
        );
        addTearDown(sub.cancel);

        await client.fetchMessages(ownOh);
        await pumpUntil(
          () => updates.isNotEmpty,
          reason: 'the oh_update array never arrived',
        );
        expect(updates.single.descriptors, hasLength(2));

        // A follow-up send now fans out to BOTH announced mailboxes, each over
        // its own garlic route.
        await client.sendMessage('chan', 'after the array announce');
        await pumpUntil(
          () => garlicFrames.length >= 2,
          reason: 'the send after the announce did not fan out over garlic',
        );
        final ohIds = <String>{};
        for (final frame in garlicFrames.take(2)) {
          final deposit = await peelGarlicDeposit(frame, relays);
          ohIds.add(HEX.encode(deposit!.ohId));
        }
        expect(ohIds, contains(HEX.encode(ohA.handleId)));
        expect(ohIds, contains(HEX.encode(ohB.handleId)));
      },
    );
  });
}
