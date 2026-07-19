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
import 'package:redpanda_light_client/src/domain/decrypted_message.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// T21 OH failover unit tests. A scripted in-memory Socket plays the ONE
/// reachable node while the OH's recorded host stays unreachable (every dial
/// to it fails). The exchange stays plaintext because the encryption
/// handshake is never completed — command framing is identical.
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

const deadEndpoint = 'dead:2';
const liveEndpoint = 'scripted:1';

/// Client whose only reachable node is the [ScriptedSocket]; dials to any
/// other endpoint (the dead OH host) fail immediately.
Future<(RedPandaLightClient, ScriptedSocket)> connectedClient() async {
  final socket = ScriptedSocket();
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: [liveEndpoint],
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

final channelKey = List<int>.generate(32, (i) => i);
final peerOhId = List<int>.generate(20, (i) => 100 + i);

Future<OHRegistration> deadHostRegistration() async {
  return OHRegistration(
    ohId: List.generate(20, (i) => i),
    keypair: await OHKeypair.generate(),
    expiresAtMs: DateTime.now()
        .add(const Duration(days: 7))
        .millisecondsSinceEpoch,
    channelId: 'chan',
    serverEndpoint: deadEndpoint,
  );
}

void main() {
  group('T21 ChannelMessage oh_update codec', () {
    test('roundtrips the oh_update field', () {
      final descriptorJson = OHDescriptor(
        serverEndpoint: liveEndpoint,
        handleId: List<int>.generate(20, (i) => i),
        authPublicKey: List<int>.generate(32, (i) => i),
      ).toJson();
      final msg = ChannelMessage(
        messageId: Uint8List.fromList(List<int>.generate(16, (i) => i)),
        timestampMs: 12345,
        content: '',
        ohUpdate: Uint8List.fromList(utf8.encode(descriptorJson)),
      );
      final decoded = ChannelMessage.decode(msg.encode());
      expect(decoded.isOhUpdate, isTrue);
      expect(utf8.decode(decoded.ohUpdate!), equals(descriptorJson));
      final descriptor = OHDescriptor.fromJson(utf8.decode(decoded.ohUpdate!));
      expect(descriptor.serverEndpoint, equals(liveEndpoint));
    });

    test('regular messages carry no oh_update', () {
      final msg = ChannelMessage(
        messageId: Uint8List.fromList(List<int>.generate(16, (i) => i)),
        timestampMs: 12345,
        content: 'hi',
      );
      expect(ChannelMessage.decode(msg.encode()).isOhUpdate, isFalse);
    });
  });

  group('T21 failover: dead host, reachable alternative', () {
    test(
      'three unreachable fetch cycles move the mailbox and announce it',
      () async {
        final (client, socket) = await connectedClient();
        addTearDown(client.disconnect);

        RegisterOhRequest? registerRequest;
        FlaschenpostPut? announceDeposit;
        socket.onCommandFrame = (command, payload) {
          if (command == 150) {
            registerRequest = RegisterOhRequest.fromBuffer(payload);
            socket.replyCommand(
              151,
              (RegisterOhResponse()
                    ..status = Status.OK
                    ..expiresAtMs = fixnum.Int64(
                      DateTime.now()
                          .add(const Duration(days: 7))
                          .millisecondsSinceEpoch,
                    ))
                  .writeToBuffer(),
            );
          } else if (command == 159) {
            socket.replyCommand(
              160,
              (SubscribeResponse()..status = Status.OK).writeToBuffer(),
            );
          } else if (command == 152) {
            socket.replyCommand(
              153,
              (FetchResponse()..status = Status.OK).writeToBuffer(),
            );
          } else if (command == 141) {
            announceDeposit ??= FlaschenpostPut.fromBuffer(payload);
            socket.replyCommand(
              158,
              (FlaschenpostPutResponse()..status = Status.OK).writeToBuffer(),
            );
          }
        };

        client.addChannelKeys(
          'chan',
          channelKey,
          peerOhId: peerOhId,
          peerOhEndpoint: 'peerhost:9',
          isChannelCreator: true,
        );
        final oldOh = await deadHostRegistration();
        await client.restoreOutboundHandle(oldOh);

        final replacements = <OHRegistration>[];
        final sub = client.ohRegistrationUpdates.listen(replacements.add);
        addTearDown(sub.cancel);

        // Three provably one-sided failures (the scripted node is verified
        // the whole time) — the third one crosses the threshold.
        for (var i = 0; i < 3; i++) {
          await client.fetchMessages(oldOh);
        }

        await pumpUntil(
          () => registerRequest != null,
          reason: 'no failover registration was sent',
        );
        await pumpUntil(
          () => replacements.isNotEmpty,
          reason: 'no replacement registration was published',
        );

        final replacement = replacements.single;
        expect(replacement.channelId, equals('chan'));
        expect(
          replacement.serverEndpoint,
          equals(liveEndpoint),
          reason: 'the new mailbox must live on the reachable node',
        );
        expect(_sameBytes(replacement.ohId, registerRequest!.ohId), isTrue);
        expect(
          _sameBytes(replacement.ohId, oldOh.ohId),
          isFalse,
          reason: 'the replacement must be a NEW handle',
        );

        // The dead handle is retired; only the replacement is polled.
        expect(
          client.registeredOutboundHandles.any(
            (oh) => _sameBytes(oh.ohId, oldOh.ohId),
          ),
          isFalse,
        );
        expect(
          client.registeredOutboundHandles.any(
            (oh) => _sameBytes(oh.ohId, replacement.ohId),
          ),
          isTrue,
        );

        // The in-band announce goes to the PARTNER's mailbox and carries the
        // new descriptor, ratchet-encrypted (v4) — decryptable only by the
        // partner's session.
        await pumpUntil(
          () => announceDeposit != null,
          reason: 'no oh_update announce was deposited',
        );
        expect(_sameBytes(announceDeposit!.ohId, peerOhId), isTrue);

        final partnerSession = await RatchetSession.create(
          channelKey: channelKey,
          isChannelCreator: false,
        );
        final message = await partnerSession.decrypt(
          announceDeposit!.content,
          'chan',
        );
        expect(message.isOhUpdate, isTrue);
        expect(message.content, isEmpty);
        final descriptor = OHDescriptor.fromJson(
          utf8.decode(message.ohUpdate!),
        );
        expect(descriptor.serverEndpoint, equals(liveEndpoint));
        expect(_sameBytes(descriptor.handleId, replacement.ohId), isTrue);
        expect(
          _sameBytes(
            descriptor.authPublicKey,
            replacement.keypair.publicKeyBytes,
          ),
          isTrue,
        );
      },
    );
  });

  group('T21 failover guard: local outage', () {
    test('no failover while NO alternative node is reachable', () async {
      // Every dial fails — this is airplane mode, not a dead host.
      final keys = await KeyPair.generate();
      final client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
        socketFactory: (h, p) async =>
            throw const SocketException('test: no network'),
      );
      addTearDown(client.disconnect);

      client.addChannelKeys(
        'chan',
        channelKey,
        peerOhId: peerOhId,
        isChannelCreator: true,
      );
      final oldOh = await deadHostRegistration();
      await client.restoreOutboundHandle(oldOh);

      final replacements = <OHRegistration>[];
      final sub = client.ohRegistrationUpdates.listen(replacements.add);
      addTearDown(sub.cancel);

      for (var i = 0; i < 5; i++) {
        await client.fetchMessages(oldOh);
      }
      await Future.delayed(const Duration(milliseconds: 200));

      expect(replacements, isEmpty);
      expect(
        client.registeredOutboundHandles.any(
          (oh) => _sameBytes(oh.ohId, oldOh.ohId),
        ),
        isTrue,
        reason: 'the handle must survive a local outage untouched',
      );
    });
  });

  group('T21 receive: oh_update applies and deduplicates', () {
    test('fetched oh_update moves the peer mailbox for future sends', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      final newPeerOhId = List<int>.generate(20, (i) => 200 - i);
      final newPeerKey = List<int>.generate(32, (i) => 50 + i);
      final descriptorJson = OHDescriptor(
        serverEndpoint: 'newhost:7',
        handleId: newPeerOhId,
        authPublicKey: newPeerKey,
      ).toJson();

      // The partner (channel creator) announces their new mailbox twice with
      // the same message id (the announce is re-sent on purpose).
      final partnerSession = await RatchetSession.create(
        channelKey: channelKey,
        isChannelCreator: true,
      );
      final announceId = Uint8List.fromList(List<int>.generate(16, (i) => i));
      ChannelMessage announce() => ChannelMessage(
        messageId: announceId,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        content: '',
        ohUpdate: Uint8List.fromList(utf8.encode(descriptorJson)),
      );
      final firstCopy = await partnerSession.encrypt(announce(), 'chan');
      final secondCopy = await partnerSession.encrypt(announce(), 'chan');

      final deposits = <FlaschenpostPut>[];
      var itemsDelivered = false;
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
          if (itemsDelivered) {
            socket.replyCommand(
              153,
              (FetchResponse()..status = Status.OK).writeToBuffer(),
            );
            return;
          }
          itemsDelivered = true;
          socket.replyCommand(
            153,
            (FetchResponse()
                  ..status = Status.OK
                  ..nextCursor = fixnum.Int64(2)
                  ..items.addAll([
                    MailItem(
                      payload: firstCopy,
                      receivedAtMs: fixnum.Int64(
                        DateTime.now().millisecondsSinceEpoch,
                      ),
                    ),
                    MailItem(
                      payload: secondCopy,
                      receivedAtMs: fixnum.Int64(
                        DateTime.now().millisecondsSinceEpoch,
                      ),
                    ),
                  ]))
                .writeToBuffer(),
          );
        } else if (command == 141) {
          deposits.add(FlaschenpostPut.fromBuffer(payload));
          socket.replyCommand(
            158,
            (FlaschenpostPutResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };

      client.addChannelKeys(
        'chan',
        channelKey,
        peerOhId: List<int>.generate(20, (i) => 100 + i),
        peerOhEndpoint: 'oldhost:9',
        isChannelCreator: false,
      );
      final ownOh = OHRegistration(
        ohId: List.generate(20, (i) => 60 + i),
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
      final surfaced = <DecryptedMessage>[];
      final msgSub = client.incomingMessages.listen(surfaced.add);
      addTearDown(msgSub.cancel);

      // Both copies arrive in one fetch batch (delivered by the scripted
      // node on the next poll).
      final messages = await client.fetchMessages(ownOh);
      expect(
        messages,
        isEmpty,
        reason: 'an oh_update must never surface as a chat message',
      );
      await pumpUntil(
        () => updates.isNotEmpty,
        reason: 'the oh_update never arrived',
      );
      await Future.delayed(const Duration(milliseconds: 100));
      expect(surfaced, isEmpty);
      expect(
        updates,
        hasLength(1),
        reason: 'the duplicate copy must be ignored',
      );
      expect(updates.single.channelId, equals('chan'));
      expect(updates.single.descriptor.serverEndpoint, equals('newhost:7'));
      expect(_sameBytes(updates.single.descriptor.handleId, newPeerOhId), true);

      // A follow-up send deposits into the NEW peer mailbox.
      await client.sendMessage('chan', 'hello after failover');
      await pumpUntil(
        () => deposits.isNotEmpty,
        reason: 'the send after the oh_update never deposited',
      );
      expect(_sameBytes(deposits.last.ohId, newPeerOhId), isTrue);
    });

    test('an unreadable oh_update is dropped without touching state', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      final partnerSession = await RatchetSession.create(
        channelKey: channelKey,
        isChannelCreator: true,
      );
      final bogus = await partnerSession.encrypt(
        ChannelMessage(
          messageId: Uint8List.fromList(List<int>.generate(16, (i) => 7)),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          content: '',
          ohUpdate: Uint8List.fromList(utf8.encode('{"ep": 42}')),
        ),
        'chan',
      );

      var itemsDelivered = false;
      socket.onCommandFrame = (command, payload) {
        if (command == 159) {
          socket.replyCommand(
            160,
            (SubscribeResponse()..status = Status.OK).writeToBuffer(),
          );
        } else if (command == 152) {
          final response = FetchResponse()..status = Status.OK;
          if (!itemsDelivered) {
            itemsDelivered = true;
            response
              ..nextCursor = fixnum.Int64(1)
              ..items.add(
                MailItem(
                  payload: bogus,
                  receivedAtMs: fixnum.Int64(
                    DateTime.now().millisecondsSinceEpoch,
                  ),
                ),
              );
          }
          socket.replyCommand(153, response.writeToBuffer());
        }
      };

      client.addChannelKeys(
        'chan',
        channelKey,
        peerOhId: peerOhId,
        peerOhEndpoint: 'oldhost:9',
        isChannelCreator: false,
      );
      final ownOh = OHRegistration(
        ohId: List.generate(20, (i) => 80 + i),
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

      final messages = await client.fetchMessages(ownOh);

      expect(messages, isEmpty);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(updates, isEmpty);
    });
  });
}
