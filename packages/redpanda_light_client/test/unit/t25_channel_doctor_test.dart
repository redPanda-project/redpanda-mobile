import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/channel_doctor_report.dart';
import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

import '../helpers/garlic_test_utils.dart';

/// A scripted in-memory Socket (see t20_loopback_test.dart): plaintext command
/// framing, the encryption handshake is never completed.
class ScriptedSocket implements Socket {
  final _done = Completer<void>();

  @override
  Future<void> get done => _done.future;

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
    if (!_incoming.isClosed) {
      _incoming.add(Uint8List.fromList(data));
    }
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
        if (command == 159) {
          replyCommand(
            160,
            (SubscribeResponse()..status = Status.OK).writeToBuffer(),
          );
        } else {
          onCommandFrame?.call(command, payload);
        }
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
Future<(RedPandaLightClient, ScriptedSocket, List<TestHop>)>
connectedClient() async {
  final socket = ScriptedSocket();
  final repo = InMemoryPeerRepository();
  final relays = <TestHop>[];
  for (var i = 0; i < 3; i++) {
    final hop = await TestHop.generate(i + 1);
    relays.add(hop);
    repo.updatePeer(
      '10.4.0.$i:5000',
      nodeId: HEX.encode(hop.nodeId),
      encryptionPublicKey: HEX.encode(hop.keys.publicKey),
    );
  }
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: ['scripted:1'],
    peerRepository: repo,
    // Only the scripted node is dialable; the relays are KNOWN peers (garlic
    // hop candidates), never open connections.
    socketFactory: (h, p) async {
      if (h != 'scripted') {
        throw const SocketException('test: only the scripted node is dialable');
      }
      return socket;
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

/// Scripted node for the doctor flow: OH registrations (150) → OK with a
/// 7-day expiry; garlic deposits (142, T45) are peeled with the known relay
/// keys and their payload captured; fetches (152) → deliver captured deposits
/// once while [deliverOnFetch] is true.
class DoctorNodeScript {
  final ScriptedSocket socket;
  final List<TestHop> relays;
  bool deliverOnFetch;
  final _mailbox = <List<int>>[];
  var _cursor = 0;

  DoctorNodeScript(this.socket, this.relays, {required this.deliverOnFetch}) {
    socket.onCommandFrame = _handle;
  }

  void _handle(int command, Uint8List payload) {
    if (command == 150) {
      final response = RegisterOhResponse()
        ..status = Status.OK
        ..expiresAtMs = fixnum.Int64(
          DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
        );
      socket.replyCommand(151, response.writeToBuffer());
    } else if (command == 142) {
      unawaited(() async {
        final deposit = await peelGarlicDeposit(payload, relays);
        if (deposit != null) _mailbox.add(deposit.payload);
      }());
    } else if (command == 152) {
      final response = FetchResponse()..status = Status.OK;
      if (deliverOnFetch) {
        for (final content in _mailbox) {
          _cursor++;
          response.items.add(
            MailItem()
              ..payload = content
              ..receivedAtMs = fixnum.Int64(
                DateTime.now().millisecondsSinceEpoch,
              ),
          );
        }
        _mailbox.clear();
      }
      response.nextCursor = fixnum.Int64(_cursor);
      socket.replyCommand(153, response.writeToBuffer());
    }
  }
}

DoctorStage stageNamed(ChannelDoctorReport report, String name) =>
    report.stages.firstWhere((s) => s.name == name);

void main() {
  group('T25 runChannelDoctor', () {
    test('healthy channel: all six stages are green', () async {
      final (client, socket, relays) = await connectedClient();
      addTearDown(client.disconnect);
      DoctorNodeScript(socket, relays, deliverOnFetch: true);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        // T44: channel secret enables the rendezvous doctor stage.
        channelSecret: channel.channelSecret,
        peerOhId: List<int>.generate(20, (i) => i),
        peerOhEndpoint: 'peer:9',
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: channel.id);
      // Prime a successful fetch so the "last fetch" stage is fresh.
      await client.runLoopbackTest(channel.id);

      final report = await client.runChannelDoctor(channel.id);

      expect(report.stages, hasLength(6));
      for (final stage in report.stages) {
        expect(
          stage.status,
          DoctorStatus.ok,
          reason: '${stage.name}: ${stage.detail}',
        );
        expect(stage.detail, isNotEmpty);
      }
      expect(
        stageNamed(report, 'Loopback self-test').detail,
        contains('Round trip'),
      );
      expect(stageNamed(report, 'Rendezvous').status, DoctorStatus.ok);
    });

    test('not connected: node stage and mailbox stage are red', () async {
      final keys = await KeyPair.generate();
      final client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: const [],
      );
      addTearDown(client.disconnect);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        peerOhId: List<int>.generate(20, (i) => i),
        isChannelCreator: true,
      );

      final report = await client.runChannelDoctor(
        channel.id,
        timeout: const Duration(milliseconds: 300),
      );

      final node = stageNamed(report, 'Host node reachable');
      expect(node.status, DoctorStatus.fail);
      expect(node.detail, contains('Not connected'));

      final ownMailbox = stageNamed(report, 'Own mailbox announced');
      expect(ownMailbox.status, DoctorStatus.fail);
      expect(ownMailbox.detail, contains('No own mailbox'));

      // Peer OH was provided, so that stage is green even offline.
      expect(stageNamed(report, 'Peer mailbox known').status, DoctorStatus.ok);
      // Nothing ever fetched.
      expect(
        stageNamed(report, 'Last fetch success').status,
        DoctorStatus.warn,
      );
      // Loopback cannot run without an own mailbox.
      expect(
        stageNamed(report, 'Loopback self-test').status,
        DoctorStatus.fail,
      );
    });

    test('peer OH missing: sending stage is amber', () async {
      final (client, socket, relays) = await connectedClient();
      addTearDown(client.disconnect);
      DoctorNodeScript(socket, relays, deliverOnFetch: true);

      final channel = await Channel.generate('Test');
      // No peerOhId registered.
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: channel.id);

      final report = await client.runChannelDoctor(channel.id);

      final peer = stageNamed(report, 'Peer mailbox known');
      expect(peer.status, DoctorStatus.warn);
      expect(peer.detail, contains('Peer mailbox unknown'));
    });

    test('loopback never returns: self-test stage is red', () async {
      final (client, socket, relays) = await connectedClient();
      addTearDown(client.disconnect);
      // Deposits accepted, but fetches never return the deposited item.
      DoctorNodeScript(socket, relays, deliverOnFetch: false);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        peerOhId: List<int>.generate(20, (i) => i),
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: channel.id);

      final report = await client.runChannelDoctor(
        channel.id,
        timeout: const Duration(milliseconds: 500),
      );

      final loopback = stageNamed(report, 'Loopback self-test');
      expect(loopback.status, DoctorStatus.fail);
      expect(loopback.detail, contains('not received within'));
    });

    test('own mailbox expired: mailbox stage is red', () async {
      final (client, socket, relays) = await connectedClient();
      addTearDown(client.disconnect);
      DoctorNodeScript(socket, relays, deliverOnFetch: true);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        peerOhId: List<int>.generate(20, (i) => i),
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: channel.id);
      // Force the registration into the past.
      client.registeredOutboundHandles.first.expiresAtMs = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;

      final report = await client.runChannelDoctor(channel.id);

      final ownMailbox = stageNamed(report, 'Own mailbox announced');
      expect(ownMailbox.status, DoctorStatus.fail);
      expect(ownMailbox.detail, contains('expired'));
    });

    test('own mailbox renewing soon: mailbox stage is amber', () async {
      final (client, socket, relays) = await connectedClient();
      addTearDown(client.disconnect);
      DoctorNodeScript(socket, relays, deliverOnFetch: true);

      final channel = await Channel.generate('Test');
      client.addChannelKeys(
        channel.id,
        channel.encryptionKey,
        peerOhId: List<int>.generate(20, (i) => i),
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: channel.id);
      // Within the 1-day renewal threshold but not expired.
      client.registeredOutboundHandles.first.expiresAtMs = DateTime.now()
          .add(const Duration(hours: 12))
          .millisecondsSinceEpoch;

      final report = await client.runChannelDoctor(channel.id);

      expect(
        stageNamed(report, 'Own mailbox announced').status,
        DoctorStatus.warn,
      );
    });
  });
}
