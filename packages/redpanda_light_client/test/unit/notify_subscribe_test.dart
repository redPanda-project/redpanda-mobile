import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// Connection-Notify (T38) unit tests. A scripted in-memory Socket captures
/// the client's writes and lets the test inject node frames. The exchange
/// stays plaintext because the encryption handshake is never completed —
/// command framing (`[cmd][len:4][protobuf]`) is identical.
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

void main() {
  group('T38 proto: Subscribe/Notify wire compatibility', () {
    test('SubscribeRequest roundtrips all fields', () {
      final req = SubscribeRequest()
        ..ohId = List<int>.generate(20, (i) => i)
        ..timestampMs = fixnum.Int64(1234567890)
        ..nonce = List<int>.generate(16, (i) => 255 - i)
        ..signature = List<int>.generate(64, (i) => i);
      final decoded = SubscribeRequest.fromBuffer(req.writeToBuffer());
      expect(decoded.ohId, equals(List<int>.generate(20, (i) => i)));
      expect(decoded.timestampMs.toInt(), equals(1234567890));
      expect(decoded.nonce, equals(List<int>.generate(16, (i) => 255 - i)));
      expect(decoded.signature, equals(List<int>.generate(64, (i) => i)));
    });

    test('SubscribeResponse roundtrips status and server time', () {
      final res = SubscribeResponse()
        ..status = Status.NOT_FOUND
        ..serverTimeMs = fixnum.Int64(42);
      final decoded = SubscribeResponse.fromBuffer(res.writeToBuffer());
      expect(decoded.status, equals(Status.NOT_FOUND));
      expect(decoded.serverTimeMs.toInt(), equals(42));
    });

    test('Notify roundtrips oh_id', () {
      final n = Notify()..ohId = List<int>.generate(20, (i) => i * 2);
      final decoded = Notify.fromBuffer(n.writeToBuffer());
      expect(decoded.ohId, equals(List<int>.generate(20, (i) => i * 2)));
    });
  });

  group('T38 subscribe: sent after registration', () {
    test(
      'a SubscribeRequest for the new OH follows the registration',
      () async {
        final (client, socket) = await connectedClient();
        addTearDown(client.disconnect);

        final subscribed = <List<int>>[];
        socket.onCommandFrame = (command, payload) {
          if (command == 150) {
            socket.replyCommand(
              151,
              (RegisterOhResponse()..status = Status.OK).writeToBuffer(),
            );
          } else if (command == 159) {
            final req = SubscribeRequest.fromBuffer(payload);
            // The subscribe is a signed ownership proof, exactly like a fetch.
            expect(req.signature, hasLength(64));
            expect(req.nonce, hasLength(16));
            expect(req.timestampMs.toInt(), greaterThan(0));
            subscribed.add(req.ohId);
            socket.replyCommand(
              160,
              (SubscribeResponse()..status = Status.OK).writeToBuffer(),
            );
          } else if (command == 152) {
            socket.replyCommand(
              153,
              (FetchResponse()..status = Status.OK).writeToBuffer(),
            );
          }
        };

        final oh = await client.registerOutboundHandle(channelId: 'a');
        await pumpUntil(
          () => subscribed.isNotEmpty,
          reason: 'no subscribe was sent',
        );
        expect(_sameBytes(subscribed.first, oh.ohId), isTrue);
      },
    );
  });

  group('T38 subscribe: SubscribeResponse FIFO correlation', () {
    test('two overlapping subscribes each get their own response', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      final registerOhIds = <List<int>>[];
      final subscribeOhIds = <List<int>>[];
      socket.onCommandFrame = (command, payload) {
        if (command == 150) {
          registerOhIds.add(RegisterOhRequest.fromBuffer(payload).ohId);
          socket.replyCommand(
            151,
            (RegisterOhResponse()..status = Status.OK).writeToBuffer(),
          );
        } else if (command == 159) {
          final n = subscribeOhIds.length;
          subscribeOhIds.add(SubscribeRequest.fromBuffer(payload).ohId);
          // The first two subscribes are answered manually below to control
          // FIFO ordering; later ones (from the re-registration cascade) are
          // acknowledged OK right away so no completer lingers.
          if (n >= 2) {
            socket.replyCommand(
              160,
              (SubscribeResponse()..status = Status.OK).writeToBuffer(),
            );
          }
        } else if (command == 152) {
          socket.replyCommand(
            153,
            (FetchResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };

      final a = await client.registerOutboundHandle(channelId: 'a');
      final b = await client.registerOutboundHandle(channelId: 'b');
      await pumpUntil(
        () => subscribeOhIds.length >= 2,
        reason: 'both subscribes never went out',
      );

      // FIFO: the first response belongs to A (subscribed first), the second
      // to B. Both NOT_FOUND, so each must re-register ITS OWN handle. A
      // single-slot matcher would drop one and only one handle would recover.
      socket.replyCommand(
        160,
        (SubscribeResponse()..status = Status.NOT_FOUND).writeToBuffer(),
      );
      socket.replyCommand(
        160,
        (SubscribeResponse()..status = Status.NOT_FOUND).writeToBuffer(),
      );

      await pumpUntil(
        () =>
            registerOhIds.where((id) => _sameBytes(id, a.ohId)).length >= 2 &&
            registerOhIds.where((id) => _sameBytes(id, b.ohId)).length >= 2,
        reason: 'both handles should re-register after their NOT_FOUND',
      );
    });
  });

  group('T38 notify: triggers a fetch', () {
    test('Notify for a known OH pulls a fetch forward immediately', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      var fetches = 0;
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
          fetches++;
          socket.replyCommand(
            153,
            (FetchResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };

      final oh = await client.registerOutboundHandle(channelId: 'a');
      // Ignore the registration-triggered poll; measure the Notify effect.
      await Future.delayed(const Duration(milliseconds: 100));
      final baseline = fetches;

      socket.replyCommand(161, (Notify()..ohId = oh.ohId).writeToBuffer());

      // The immediate re-poll fires on the next event loop, far sooner than
      // the ~2 s scheduled poll cadence.
      await pumpUntil(
        () => fetches > baseline,
        timeout: const Duration(milliseconds: 800),
        reason: 'Notify did not trigger a fetch',
      );
    });
  });

  group('T38 notify: unknown OH ignored', () {
    test('Notify for an unregistered OH does not trigger a fetch', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      var fetches = 0;
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
          fetches++;
          socket.replyCommand(
            153,
            (FetchResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };

      await client.registerOutboundHandle(channelId: 'a');
      await Future.delayed(const Duration(milliseconds: 100));
      final baseline = fetches;

      // An oh_id that matches no registered handle.
      socket.replyCommand(
        161,
        (Notify()..ohId = List<int>.generate(20, (i) => 200 + (i % 40)))
            .writeToBuffer(),
      );

      // No immediate fetch must follow (checked well before the ~2 s poll).
      await Future.delayed(const Duration(milliseconds: 400));
      expect(fetches, equals(baseline));
    });
  });

  group('T38 subscribe: failure does not break polling', () {
    test('a non-OK SubscribeResponse leaves the poll loop running', () async {
      final (client, socket) = await connectedClient();
      addTearDown(client.disconnect);

      var fetches = 0;
      var reRegisters = 0;
      List<int>? firstRegisterOhId;
      socket.onCommandFrame = (command, payload) {
        if (command == 150) {
          final ohId = RegisterOhRequest.fromBuffer(payload).ohId;
          if (firstRegisterOhId == null) {
            firstRegisterOhId = ohId;
          } else if (_sameBytes(ohId, firstRegisterOhId!)) {
            reRegisters++;
          }
          socket.replyCommand(
            151,
            (RegisterOhResponse()..status = Status.OK).writeToBuffer(),
          );
        } else if (command == 159) {
          // Reject the subscription — must be tolerated, polling carries on.
          socket.replyCommand(
            160,
            (SubscribeResponse()..status = Status.BAD_REQUEST).writeToBuffer(),
          );
        } else if (command == 152) {
          fetches++;
          socket.replyCommand(
            153,
            (FetchResponse()..status = Status.OK).writeToBuffer(),
          );
        }
      };

      await client.registerOutboundHandle(channelId: 'a');

      // The mailbox is still polled despite the rejected subscribe.
      await pumpUntil(
        () => fetches > 0,
        reason: 'polling stopped after a subscribe failure',
      );
      // A non-NOT_FOUND rejection must NOT trigger a re-registration.
      expect(reRegisters, equals(0));
    });
  });
}
