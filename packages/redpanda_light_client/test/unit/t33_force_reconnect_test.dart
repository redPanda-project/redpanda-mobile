import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// T33 force-reconnect unit tests: consecutive fetch timeouts on the same
/// connection are the signature of a half-open socket — the client must tear
/// the connection down and redial instead of burning further timeout cycles.
///
/// A scripted in-memory Socket plays the node; `answersFetch` controls
/// whether a fetch (152) gets its response (153) or times out. The exchange
/// stays plaintext because the encryption handshake is never completed —
/// command framing is identical.
class ScriptedSocket implements Socket {
  ScriptedSocket({required this.answersFetch});

  /// Whether fetch requests (152) are answered — false simulates the
  /// half-open connection: writes succeed, the node never responds.
  bool answersFetch;

  bool destroyed = false;

  @override
  Future<void> get done => Completer<void>().future;

  final _incoming = StreamController<Uint8List>();
  final List<int> _outBuffer = [];
  bool _handshakeAnswered = false;

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
      if (command == 150 || command == 152 || command == 159) {
        if (_outBuffer.length < 5) return;
        final len = ByteData.sublistView(
          Uint8List.fromList(_outBuffer.sublist(1, 5)),
        ).getInt32(0, Endian.big);
        if (_outBuffer.length < 5 + len) return;
        _outBuffer.removeRange(0, 5 + len);
        if (command == 150) {
          replyCommand(
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
          replyCommand(
            160,
            (SubscribeResponse()..status = Status.OK).writeToBuffer(),
          );
        } else if (command == 152 && answersFetch) {
          replyCommand(
            153,
            (FetchResponse()..status = Status.OK).writeToBuffer(),
          );
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
    destroyed = true;
    _incoming.close();
  }

  @override
  Future<void> close() async {
    _incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const liveEndpoint = 'scripted:1';

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

Future<OHRegistration> hostRegistration() async {
  return OHRegistration(
    ohId: List.generate(20, (i) => i),
    keypair: await OHKeypair.generate(),
    expiresAtMs: DateTime.now()
        .add(const Duration(days: 7))
        .millisecondsSinceEpoch,
    channelId: 'chan',
    serverEndpoint: liveEndpoint,
  );
}

void main() {
  late List<ScriptedSocket> sockets;
  late RedPandaLightClient client;

  /// Client whose socket factory hands out a FRESH scripted socket per dial
  /// (a reconnect must get a new connection, like a real redial would).
  Future<void> connectClient({required bool answersFetch}) async {
    sockets = [];
    final keys = await KeyPair.generate();
    client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: [liveEndpoint],
      fetchResponseTimeout: const Duration(milliseconds: 300),
      socketFactory: (h, p) async {
        final socket = ScriptedSocket(answersFetch: answersFetch);
        sockets.add(socket);
        return socket;
      },
    );
    await client.connect();
    await pumpUntil(
      () => client.activePeerAddresses.isNotEmpty,
      reason: 'peer never became handshake-verified',
    );
  }

  test(
    'two consecutive fetch timeouts drop the connection and redial',
    () async {
      await connectClient(answersFetch: false);
      addTearDown(() => client.disconnect());
      final oh = await hostRegistration();
      await client.restoreOutboundHandle(oh);

      expect(await client.fetchMessages(oh), isEmpty); // timeout 1
      expect(
        sockets.first.destroyed,
        isFalse,
        reason: 'a single timeout must NOT drop the connection',
      );

      expect(await client.fetchMessages(oh), isEmpty); // timeout 2
      expect(
        sockets.first.destroyed,
        isTrue,
        reason: 'the second consecutive timeout must drop the connection',
      );
      await pumpUntil(
        () => sockets.length >= 2,
        reason: 'no redial after dropping the half-open connection',
      );
      await pumpUntil(
        () => client.activePeerAddresses.isNotEmpty,
        reason: 'redialed connection never became handshake-verified',
      );
    },
  );

  test('a fetch response in between resets the timeout counter', () async {
    await connectClient(answersFetch: false);
    addTearDown(() => client.disconnect());
    final oh = await hostRegistration();
    await client.restoreOutboundHandle(oh);

    expect(await client.fetchMessages(oh), isEmpty); // timeout 1

    sockets.first.answersFetch = true;
    await client.fetchMessages(oh); // success — resets the counter

    sockets.first.answersFetch = false;
    expect(await client.fetchMessages(oh), isEmpty); // timeout 1 again

    expect(
      sockets.first.destroyed,
      isFalse,
      reason: 'non-consecutive timeouts must not drop the connection',
    );
    expect(sockets, hasLength(1));
  });
}
