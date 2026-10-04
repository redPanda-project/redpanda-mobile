import 'dart:async';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/models/connection_status.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:test/test.dart';

import '../helpers/stalled_key_exchange_socket.dart';
import '../helpers/wait_for.dart';
import 'handshake_v23_test.dart' show ScriptedV23Server, connect;

/// T156: nothing but the handshake may be sent before transport encryption is
/// active, and a key exchange that never completes must not hold the peer
/// forever.
///
/// TD273: `isHandshakeVerified` flips at the plaintext magic, long before the
/// codec exists. Payload senders used to pick peers by it, so e.g. an OH
/// registration in that window went out as plaintext `[150][len]…`; a real
/// node reads that as a GCM frame length of 0x96…… and drops the connection.
///
/// TD274: the handshake timer used to be cancelled at the magic. Until T153
/// the plaintext latency PING "accidentally" ended a stalled key exchange;
/// now the timer has to.
void main() {
  group('T156/TD273: payload commands wait for encryption', () {
    test(
      'registerOutboundHandle() in the key-exchange window sends nothing',
      () async {
        final socket = StalledKeyExchangeSocket(await KeyPair.generate());
        final keys = await KeyPair.generate();
        final statuses = <ConnectionStatus>[];
        final client = RedPandaLightClient(
          selfNodeId: NodeId.fromPublicKey(keys),
          selfKeys: keys,
          seeds: ['scripted:23'],
          socketFactory: (h, p) async => socket,
        );
        final sub = client.connectionStatus.listen(statuses.add);
        addTearDown(sub.cancel);
        addTearDown(client.disconnect);
        await client.connect();

        // ACTIVATE_ENCRYPTION (3 + 32-byte ephemeral key) is out and stays
        // unanswered: verified, but no codec.
        await waitFor(
          () => socket.writes.any((w) => w.length == 33 && w.first == 3),
          description: 'ACTIVATE_ENCRYPTION sent',
        );
        // Verified but not encrypted: still "connecting", not "active".
        expect(client.connectingPeerAddresses, contains('scripted:23'));
        expect(client.activePeerAddresses, isEmpty);
        expect(client.isEncryptionActive, isFalse);
        final before = socket.writes.length;

        // No peer can carry the request: the registration comes back
        // unconfirmed (no host endpoint) instead of hitting the wire. On the
        // old code it went out and waited 10 s for a response.
        final registration = await client.registerOutboundHandle(
          channelId: 'c',
        );

        // Asserting that nothing happens: a fixed delay is the right tool
        // (see waitFor). Covers the tx chain and the queued subscribe.
        await Future.delayed(const Duration(milliseconds: 300));
        expect(
          socket.writes.sublist(before),
          isEmpty,
          reason:
              'a plaintext REGISTER_OH (0x96…) is read by the node as a GCM '
              'frame length and kills the connection',
        );
        expect(registration.serverEndpoint, isNull);
        // "connected" is only reported once encryption is active, so the
        // connect edge (subscribe, catch-up poll) has not fired either.
        expect(statuses, isNot(contains(ConnectionStatus.connected)));
      },
    );

    test(
      'client reports connected exactly once, only after encryption',
      () async {
        final server = await ScriptedV23Server.create();
        server.holdActivation = Completer<void>();
        final keys = await KeyPair.generate();
        final statuses = <ConnectionStatus>[];
        final client = RedPandaLightClient(
          selfNodeId: NodeId.fromPublicKey(keys),
          selfKeys: keys,
          seeds: ['scripted:23'],
          socketFactory: (h, p) async => server,
        );
        final sub = client.connectionStatus.listen(statuses.add);
        addTearDown(sub.cancel);
        addTearDown(client.disconnect);
        await client.connect();

        // The client's ACTIVATE_ENCRYPTION reached the server, whose answer
        // is held back: verified, no codec.
        await waitFor(
          () => server.clientEphemeral != null,
          description: 'client ACTIVATE_ENCRYPTION received',
        );
        // Asserting that nothing happens while the exchange is frozen.
        await Future.delayed(const Duration(milliseconds: 300));
        expect(statuses, isNot(contains(ConnectionStatus.connected)));
        expect(client.activePeerAddresses, isEmpty);
        expect(client.connectingPeerAddresses, contains('scripted:23'));

        server.holdActivation!.complete();
        await waitFor(
          () => statuses.contains(ConnectionStatus.connected),
          description: 'client connected after encryption',
        );
        expect(client.isEncryptionActive, isTrue);
        expect(client.activePeerAddresses, contains('scripted:23'));
        // The node requires the first encrypted command to be PING.
        expect(await server.firstEncryptedCommand.future, equals(5));
        // Asserting no second connect edge.
        await Future.delayed(const Duration(milliseconds: 300));
        expect(
          statuses.where((st) => st == ConnectionStatus.connected),
          hasLength(1),
        );
      },
    );

    test('canSendCommands flips with the codec, not with the magic', () async {
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
      addTearDown(peer.disconnect);
      await peer.connect();
      await waitFor(() => peer.isHandshakeVerified);
      expect(peer.canSendCommands, isFalse);

      final (encrypted, _, statuses) = await connect();
      addTearDown(encrypted.disconnect);
      await waitFor(() => encrypted.canSendCommands);
      expect(encrypted.isEncryptionActive, isTrue);
      expect(statuses, contains(ConnectionStatus.connected));
    });
    test(
      'a shutdown during the key exchange never reports connected',
      () async {
        final socket = StalledKeyExchangeSocket(await KeyPair.generate());
        final keys = await KeyPair.generate();
        final statuses = <ConnectionStatus>[];
        final peer = ActivePeer(
          address: 'scripted:23',
          selfNodeId: NodeId.fromPublicKey(keys),
          selfKeys: keys,
          socketFactory: (h, p) async => socket,
          onStatusChange: statuses.add,
          onDisconnect: () {},
        );
        await peer.connect();
        // Public key parsed: the client now sits in the 100 ms delay before
        // its own ACTIVATE_ENCRYPTION.
        await waitFor(
          () => peer.discoveredNodeId != null,
          description: 'node public key parsed',
        );

        // The node's ACTIVATE_ENCRYPTION arrives first; its handler waits for
        // the client's own initiation (the 100 ms delay) before finalizing.
        // The peer shuts down inside that wait, so finalization resumes on a
        // dead peer — it must not report "connected" (that would wedge the
        // client's aggregate status at connected with nothing sendable).
        socket.reply([3, ...List<int>.filled(32, 9)]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(peer.isEncryptionActive, isFalse);
        await peer.disconnect();
        await Future.delayed(const Duration(milliseconds: 400));

        expect(statuses, equals([ConnectionStatus.disconnected]));
        expect(peer.canSendCommands, isFalse);
      },
    );
  });

  group('T156/TD274: handshake deadline covers the key exchange', () {
    test('a key exchange that never completes drops the peer', () async {
      final socket = StalledKeyExchangeSocket(await KeyPair.generate());
      final keys = await KeyPair.generate();
      var disconnected = false;
      final peer = ActivePeer(
        address: 'scripted:23',
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        socketFactory: (h, p) async => socket,
        onStatusChange: (_) {},
        onDisconnect: () => disconnected = true,
        handshakeDeadline: const Duration(milliseconds: 500),
      );
      addTearDown(peer.disconnect);
      await peer.connect();
      await waitFor(() => peer.isHandshakeVerified);

      await waitFor(
        () => disconnected,
        description: 'peer dropped after the handshake deadline',
      );
      expect(peer.isDisconnected, isTrue);
      expect(peer.isEncryptionActive, isFalse);
    });

    test('a completed key exchange stops the deadline', () async {
      var disconnected = false;
      final (peer, _, _) = await connect(
        onDisconnect: () => disconnected = true,
        handshakeDeadline: const Duration(milliseconds: 500),
      );
      addTearDown(peer.disconnect);
      await waitFor(() => peer.isEncryptionActive);

      // Asserting that nothing happens past the deadline.
      await Future.delayed(const Duration(milliseconds: 800));
      expect(disconnected, isFalse);
      expect(peer.canSendCommands, isTrue);
    });
  });
}
