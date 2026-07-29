import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Socket stub that stays open so the dial counts as "in flight".
class _IdleSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

  @override
  Future<void> get done => Completer<void>().future;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  void add(List<int> data) {}

  @override
  void destroy() => _controller.close();

  @override
  Future<void> close() async => _controller.close();

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // T78: _runConnectionCheck awaits DNS lookups between picking an address and
  // registering the ActivePeer in _peers. Two checks overlapping inside that
  // window used to dial the same address twice; the node then disconnects the
  // duplicate (TD020, redpandaj#276) and the client can be left with no active
  // peer right after reporting encryption as active. Two addPeer() calls in one
  // turn put two checks into the window deterministically — in the field it is
  // a slow lookup under CPU pressure that lets the 3 s timer re-pick the
  // address.
  test('overlapping connection checks dial an address only once', () async {
    final attempts = <String>[];

    Future<Socket> countingFactory(String host, int port) async {
      attempts.add('$host:$port');
      return _IdleSocket();
    }

    final keys = await KeyPair.generate();
    final client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      // No seeds: the address is introduced below, so the constructor's
      // load().then() check cannot have dialled it already.
      seeds: const [],
      socketFactory: countingFactory,
    );
    await Future.delayed(const Duration(milliseconds: 200));

    // Both checks start in the same turn and suspend on the same lookups.
    final first = client.addPeer('127.0.0.1:5100');
    final second = client.addPeer('127.0.0.1:5100');
    await Future.wait([first, second]);

    // Long enough for both dials to get through the lookups, short enough to
    // stay below the 3 s reconnect tick.
    await Future.delayed(const Duration(milliseconds: 1500));

    expect(
      attempts.where((a) => a == '127.0.0.1:5100').length,
      1,
      reason:
          'a second check must not re-dial an address whose dial has not been '
          'registered in _peers yet',
    );

    await client.disconnect();
  });
}
