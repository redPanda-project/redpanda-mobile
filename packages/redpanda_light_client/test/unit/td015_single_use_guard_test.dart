import 'dart:typed_data';

import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:test/test.dart';

/// TD015 (T56): [RedPandaLightClient] is a single-use object. [disconnect] is
/// a terminal shutdown that permanently closes every broadcast stream
/// controller and clears the OH registry, so a subsequent [connect] on the
/// SAME instance would silently restore nothing (no mailbox polling, no
/// incoming events) while still flipping the status back to connecting.
///
/// Analysis for T56 found NO production lifecycle path that cycles
/// disconnect()/connect() on a live instance: Android/iOS pause/resume go
/// through onPause()/onResume(), transient link loss is handled per-peer, and
/// the isolate worker builds a fresh client on every respawn. This test guards
/// against future misuse by asserting that reuse fails loudly instead of
/// half-dead.
void main() {
  group('TD015 single-use guard', () {
    late NodeId nodeId;
    late KeyPair keyPair;

    setUp(() async {
      nodeId = NodeId(Uint8List.fromList(List.filled(20, 7)));
      keyPair = await KeyPair.generate();
    });

    // No seeds => the connection check finds nothing to dial, so no socket is
    // ever opened: the guard itself is pure and touches no network path.
    RedPandaLightClient newClient() => RedPandaLightClient(
      selfNodeId: nodeId,
      selfKeys: keyPair,
      seeds: const [],
    );

    test('connect() after disconnect() throws StateError', () async {
      final client = newClient();
      await client.disconnect();

      expect(client.connect, throwsA(isA<StateError>()));
    });

    test(
      'connect() after disconnect() still throws even if connect ran first',
      () async {
        final client = newClient();
        await client.connect();
        await client.disconnect();

        expect(client.connect, throwsA(isA<StateError>()));
      },
    );

    test('disconnect() is idempotent (second call does not throw)', () async {
      final client = newClient();
      await client.disconnect();

      await expectLater(client.disconnect(), completes);
    });

    test('a fresh instance connects normally after another was '
        'disconnected', () async {
      final dead = newClient();
      await dead.disconnect();
      expect(dead.connect, throwsA(isA<StateError>()));

      // The single-use guard is per-instance: a brand-new client (what the
      // isolate worker builds on respawn) is unaffected.
      final fresh = newClient();
      await expectLater(fresh.connect(), completes);
      await fresh.disconnect();
    });
  });
}
