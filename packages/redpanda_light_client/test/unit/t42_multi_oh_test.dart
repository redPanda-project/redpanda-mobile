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
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/domain/send_exceptions.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// T42 multi-OH / multi-deposit unit tests. A scripted in-memory Socket plays
/// the single connected node (it forwards every deposit by oh_id, MS02b), so a
/// fan-out of FlaschenpostPuts to several peer OHs all lands on this one
/// connection — exactly what the client does at runtime. The exchange stays
/// plaintext (the encryption handshake is never completed; framing is
/// identical).
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

Future<(RedPandaLightClient, ScriptedSocket)> connectedClient({
  Duration depositResponseTimeout = const Duration(seconds: 10),
}) async {
  final socket = ScriptedSocket();
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: [liveEndpoint],
    depositResponseTimeout: depositResponseTimeout,
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
  return (client, socket);
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

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final channelKey = List<int>.generate(32, (i) => i + 1);

OHDescriptor peerOh(int seed, String endpoint) => OHDescriptor(
  serverEndpoint: endpoint,
  handleId: List<int>.generate(20, (i) => (seed + i) & 0xFF),
  authPublicKey: List<int>.generate(32, (i) => (seed * 2 + i) & 0xFF),
);

void main() {
  group('T42 multi-deposit: fan-out to all known peer OHs', () {
    test('deposits into every peer OH; first confirmation is enough', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      final ohA = peerOh(10, 'nodeA:1');
      final ohB = peerOh(90, 'nodeB:2');

      final deposits = <FlaschenpostPut>[];
      socket.onCommandFrame = (command, payload) {
        if (command == 141) {
          final put = FlaschenpostPut.fromBuffer(payload);
          deposits.add(put);
          socket.replyCommand(
            158,
            (FlaschenpostPutResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };

      client.addChannelKeys(
        'chan',
        channelKey,
        peerOhSet: [ohA, ohB],
        isChannelCreator: true,
      );

      final id = await client.sendMessage('chan', 'hello redundancy');
      expect(id, isNotEmpty);

      await pumpUntil(
        () => deposits.length >= 2,
        reason: 'the send did not fan out to both peer OHs',
      );
      final targetIds = deposits.map((d) => d.ohId).toList();
      expect(targetIds.any((t) => _sameBytes(t, ohA.handleId)), isTrue);
      expect(targetIds.any((t) => _sameBytes(t, ohB.handleId)), isTrue);
      // Direct fan-out, no garlic hops.
      expect(client.lastSendHopCount, equals(0));
    });

    test('one dead OH-host does not stall delivery (no wait)', () async {
      // ohA never gets a deposit response (its host is "down"); ohB confirms.
      // The send must complete on ohB's confirmation without waiting out ohA's
      // 10 s deposit timeout.
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      final ohA = peerOh(10, 'deadhost:1');
      final ohB = peerOh(90, 'livehost:2');

      socket.onCommandFrame = (command, payload) {
        if (command == 141) {
          final put = FlaschenpostPut.fromBuffer(payload);
          if (_sameBytes(put.ohId, ohB.handleId)) {
            socket.replyCommand(
              158,
              (FlaschenpostPutResponse()..status = Status.OK).writeToBuffer(),
            );
          }
          // ohA: intentionally no response (dead host).
        }
      };

      client.addChannelKeys(
        'chan',
        channelKey,
        peerOhSet: [ohA, ohB],
        isChannelCreator: true,
      );

      final started = DateTime.now();
      final id = await client
          .sendMessage('chan', 'reach me via the live OH')
          .timeout(const Duration(seconds: 3));
      final elapsed = DateTime.now().difference(started);
      expect(id, isNotEmpty);
      expect(
        elapsed,
        lessThan(const Duration(seconds: 3)),
        reason: 'delivery must not wait out the dead OH deposit timeout',
      );
    });

    test(
      'all deposits unconfirmed ⇒ throws (timeout is NOT success, T39)',
      () async {
        // No 158 response for ANY deposit — the message must stay undelivered so
        // the app keeps it pending and retries. Short deposit timeout keeps the
        // test fast.
        final (client, socket) = await connectedClient(
          depositResponseTimeout: const Duration(milliseconds: 400),
        );
        addTearDown(client.disconnect);

        final ohA = peerOh(10, 'deadA:1');
        final ohB = peerOh(90, 'deadB:2');

        var deposits = 0;
        socket.onCommandFrame = (command, payload) {
          if (command == 141) deposits++; // never answered
        };

        client.addChannelKeys(
          'chan',
          channelKey,
          peerOhSet: [ohA, ohB],
          isChannelCreator: true,
        );

        await expectLater(
          client.sendMessage('chan', 'nobody home'),
          throwsA(isA<DepositException>()),
        );
        expect(deposits, equals(2), reason: 'both peer OHs must be attempted');
      },
    );
  });

  group('T42 receive: oh_update array grows the peer OH set', () {
    test(
      'a 2-descriptor announce makes future sends fan out to both',
      () async {
        final (client, socket) = await connectedClient();
        addTearDown(client.disconnect);

        final ohA = peerOh(10, 'nodeA:1');
        final ohB = peerOh(90, 'nodeB:2');

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

        final deposits = <FlaschenpostPut>[];
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
          } else if (command == 141) {
            deposits.add(FlaschenpostPut.fromBuffer(payload));
            socket.replyCommand(
              158,
              (FlaschenpostPutResponse()..status = Status.OK).writeToBuffer(),
            );
          }
        };

        // We start knowing only ohA (from the QR/primary).
        client.addChannelKeys(
          'chan',
          channelKey,
          peerOhId: ohA.handleId,
          peerOhEndpoint: ohA.serverEndpoint,
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

        final updates = <PeerOhUpdate>[];
        final sub = client.peerOhUpdates.listen(updates.add);
        addTearDown(sub.cancel);

        await client.fetchMessages(ownOh);
        await pumpUntil(
          () => updates.isNotEmpty,
          reason: 'the oh_update array never arrived',
        );
        expect(updates.single.descriptors, hasLength(2));

        // A follow-up send now fans out to BOTH announced mailboxes.
        await client.sendMessage('chan', 'after the array announce');
        await pumpUntil(
          () => deposits.length >= 2,
          reason: 'the send after the announce did not fan out',
        );
        final ids = deposits.map((d) => d.ohId).toList();
        expect(ids.any((t) => _sameBytes(t, ohA.handleId)), isTrue);
        expect(ids.any((t) => _sameBytes(t, ohB.handleId)), isTrue);
      },
    );
  });
}
