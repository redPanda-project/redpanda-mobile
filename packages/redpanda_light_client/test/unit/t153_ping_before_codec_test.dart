import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:test/test.dart';

import '../helpers/wait_for.dart';
import 'handshake_v23_test.dart' show connect;

/// Node that answers the plaintext part of the v23 handshake (magic, public
/// key) but never answers ACTIVATE_ENCRYPTION — freezing the client in the
/// window where `isHandshakeVerified` is already true but no codec exists.
class _StalledKeyExchangeSocket implements Socket {
  _StalledKeyExchangeSocket(this.serverKeys);

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

void main() {
  group('T153: latency ping vs. transport encryption', () {
    test(
      'ping() between ACTIVATE_ENCRYPTION and codec setup sends nothing',
      () async {
        final socket = _StalledKeyExchangeSocket(await KeyPair.generate());
        final keys = await KeyPair.generate();
        final peer = ActivePeer(
          address: 'scripted:23',
          selfNodeId: NodeId.fromPublicKey(keys),
          selfKeys: keys,
          socketFactory: (h, p) async => socket,
          onStatusChange: (_) {},
          onDisconnect: () {},
        );
        await peer.connect();

        // ACTIVATE_ENCRYPTION (3 + 32-byte ephemeral key) is out; the node
        // has not answered, so the client has no codec yet.
        await waitFor(
          () => socket.writes.any((w) => w.length == 33 && w.first == 3),
          description: 'ACTIVATE_ENCRYPTION sent',
        );
        expect(peer.isHandshakeVerified, isTrue);
        expect(peer.isEncryptionActive, isFalse);
        final before = socket.writes.length;

        // What the 3 s connection check does for every verified peer.
        peer.ping();
        // Asserting that nothing happens: a fixed delay is the right tool
        // (see waitFor). Long enough for the tx chain to drain.
        await Future.delayed(const Duration(milliseconds: 200));

        expect(
          socket.writes.sublist(before),
          isEmpty,
          reason:
              'a plaintext PING (0x05) here is read by the node as a GCM '
              'frame of length 0x05000000 and kills the connection',
        );
        peer.disconnect();
      },
    );

    test('ping() once encryption is active sends an encrypted PING', () async {
      final (peer, server, _) = await connect();
      await waitFor(() => peer.isEncryptionActive);
      // Initial PING + REQUEST_PEER_LIST from the encryption finalization.
      await server.firstEncryptedCommand.future;
      await waitFor(() => server.decryptedFromClient.length >= 2);
      final before = server.decryptedFromClient.length;

      peer.ping();

      await waitFor(
        () => server.decryptedFromClient.length > before,
        description: 'encrypted latency PING received',
      );
      expect(server.decryptedFromClient.sublist(before), equals([5]));
      peer.disconnect();
    });
  });
}
