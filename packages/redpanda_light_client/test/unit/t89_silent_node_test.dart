import 'dart:async';
import 'dart:io';

import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:test/test.dart';

/// T89(b): reproduction of `client never connected to the node`.
///
/// A "node" that accepts the TCP connection and then says nothing used to wedge
/// the client permanently. `ActivePeer` had a dial timeout but no handshake
/// timeout, and a TCP-connected-but-unverified peer is not `isDisconnected`
/// (that wants `_socket == null` *and* `_isDisconnecting`), so
/// `RedPandaLightClient._runConnectionCheck` neither reaped the entry nor
/// re-dialled its address — the slot in `_peers` was taken. With a single known
/// peer, the configuration the emulator gate runs, the client sat on that one
/// silent socket forever at `connecting` and the gate reported "client never
/// connected to the node" three minutes later, with no evidence of why.
///
/// Measured against this server before the fix: 1 accepted connection in 45 s
/// and status stuck at `connecting`. With `ActivePeer.handshakeTimeout` the
/// dead connection is dropped, the address goes back into the normal retry
/// backoff and the client keeps trying.
void main() {
  test(
    'a node that never sends its handshake does not wedge the client',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final accepted = <Socket>[];
      // Accept and stay silent — no handshake header, and crucially no close
      // either, which is what a node with a wedged selector (or a link that ate
      // the FIN) looks like from here.
      server.listen(accepted.add);

      final keys = await KeyPair.generate();
      final client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: const [],
      );
      addTearDown(client.disconnect);
      await client.addPeer('127.0.0.1:${server.port}');
      await client.connect();

      // One handshake timeout plus the retry backoff and a connection-check tick.
      await Future<void>.delayed(
        ActivePeer.handshakeTimeout + const Duration(seconds: 10),
      );

      expect(
        accepted.length,
        greaterThan(1),
        reason:
            'the client must give up on the silent connection and re-dial; '
            'exactly one accepted connection is the T89b wedge',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('the timeout is looser than the node-side handshake reaper', () {
    // PeerJobs.HANDSHAKE_TIMEOUT_MS = 10 s: the node should be the one to end a
    // handshake it cannot finish, this is only the backstop for when its close
    // never reaches us.
    expect(
      ActivePeer.handshakeTimeout,
      greaterThan(const Duration(seconds: 10)),
    );
  });
}
