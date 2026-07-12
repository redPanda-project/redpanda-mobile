import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:test/test.dart';

/// Minimal manual socket mock whose [done] future can be failed on demand,
/// simulating a write error ("connection reset by peer" during a send).
class WriteErrorSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  final Completer<void> _done = Completer<void>();
  bool destroyed = false;

  void failWrites(Object error) {
    if (!_done.isCompleted) {
      _done.completeError(error);
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(List<int> data) {}

  @override
  void destroy() {
    destroyed = true;
    _controller.close();
  }

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a socket write error triggers a clean shutdown instead of becoming an '
      'unhandled async error', () async {
    final socket = WriteErrorSocket();
    final selfKeys = await KeyPair.generate();
    final selfNodeId = NodeId(Uint8List(20));

    var disconnected = 0;
    final peer = ActivePeer(
      address: 'localhost:1234',
      selfNodeId: selfNodeId,
      selfKeys: selfKeys,
      socketFactory: (h, p) async => socket,
      onStatusChange: (_) {},
      onDisconnect: () => disconnected++,
    );

    await peer.connect();
    expect(disconnected, 0);

    // Simulate the kernel rejecting a queued write. Without a handler on
    // socket.done this error escaped as an unhandled async error and
    // killed the surrounding isolate (observed on the testnet as a dead
    // network worker after "Connection reset by peer").
    socket.failWrites(
      const SocketException('Connection reset by peer', osError: null),
    );
    await Future<void>.delayed(Duration.zero);

    expect(disconnected, 1, reason: 'write error must trigger onDisconnect');
    expect(socket.destroyed, isTrue);
    expect(peer.isDisconnected, isTrue);
  });
}
