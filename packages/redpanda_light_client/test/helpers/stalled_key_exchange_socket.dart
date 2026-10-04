import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

/// Node that answers the plaintext part of the v23 handshake (magic, public
/// key) but never answers ACTIVATE_ENCRYPTION — freezing the client in the
/// window where `isHandshakeVerified` is already true but no codec exists.
class StalledKeyExchangeSocket implements Socket {
  StalledKeyExchangeSocket(this.serverKeys);

  final KeyPair serverKeys;
  final _incoming = StreamController<Uint8List>();

  /// Every write of the client, as handed to [add].
  final List<List<int>> writes = [];

  bool _handshakeAnswered = false;

  void _reply(List<int> data) {
    if (!_incoming.isClosed) _incoming.add(Uint8List.fromList(data));
  }

  @override
  void add(List<int> data) {
    writes.add(List<int>.of(data));
    if (!_handshakeAnswered) {
      _handshakeAnswered = true;
      final b = BytesBuilder();
      b.add('k3gV'.codeUnits);
      b.addByte(23);
      b.addByte(0);
      b.add(NodeId.fromPublicKey(serverKeys).bytes);
      b.add(Uint8List(4));
      _reply(b.toBytes());
      return;
    }
    if (data.isNotEmpty && data.first == 1) {
      // REQUEST_PUBLIC_KEY → our 64-byte export. The client then starts its
      // side of the key exchange (ACTIVATE_ENCRYPTION), which we leave
      // unanswered.
      _reply([2, ...serverKeys.publicKeyBytes]);
    }
  }

  @override
  Future<void> get done => Completer<void>().future;

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
  void destroy() => _incoming.close();

  @override
  Future<void> close() async => _incoming.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
