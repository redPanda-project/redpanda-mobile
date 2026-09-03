import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// T26 resume catch-up: after [RedPandaLightClient.onResume] the next
/// mailbox poll happens within ~1 s instead of waiting for the regular
/// 5–30 s tick — the iOS foreground-only reception depends on it.
///
/// Same plaintext ScriptedSocket harness as the T38/T21 suites.
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
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> close() async {
    _incoming.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

void main() {
  test('onResume pulls the next mailbox poll forward to ~1 s', () async {
    final socket = ScriptedSocket();
    final keys = await KeyPair.generate();
    final client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: ['scripted:1'],
      socketFactory: (h, p) async => socket,
    );
    addTearDown(client.disconnect);
    await client.connect();
    await pumpUntil(
      () => client.activePeerAddresses.isNotEmpty,
      reason: 'peer never became handshake-verified',
    );

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

    await client.registerOutboundHandle(channelId: 'chan');

    // Let a regular poll complete, then measure from right after it: the
    // next scheduled poll is >= 4 s away (active cadence 5 s, fixed rate).
    await pumpUntil(() => fetches > 0, reason: 'no initial poll happened');
    final baseline = fetches;

    client.onResume();

    // The resume-triggered poll fires at ~1 s — far before the next
    // cadence tick could.
    await pumpUntil(
      () => fetches > baseline,
      timeout: const Duration(milliseconds: 2500),
      reason: 'onResume did not pull the mailbox poll forward',
    );
  });
}
