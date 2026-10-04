import 'dart:async';

import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:test/test.dart';

import '../helpers/stalled_key_exchange_socket.dart';
import '../helpers/wait_for.dart';
import 'handshake_v23_test.dart' show connect;

void main() {
  group('T153: latency ping vs. transport encryption', () {
    test(
      'ping() between ACTIVATE_ENCRYPTION and codec setup sends nothing',
      () async {
        final socket = StalledKeyExchangeSocket(await KeyPair.generate());
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
      // Initial PING from the encryption finalization.
      await server.firstEncryptedCommand.future;
      // Count PINGs only: the client's PONG (6) to the server's initial PING
      // may still arrive at any point.
      int pings() => server.decryptedFromClient.where((b) => b == 5).length;
      final before = pings();

      peer.ping();

      await waitFor(
        () => pings() > before,
        description: 'encrypted latency PING received',
      );
      expect(pings(), equals(before + 1));
      peer.disconnect();
    });
  });
}
