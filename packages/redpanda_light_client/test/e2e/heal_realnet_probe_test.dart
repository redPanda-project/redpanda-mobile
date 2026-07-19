@Tags(['e2e'])
library;

// Probe (untracked, local-only): verifies the T40 heal on the LIVE testnet.
// Simulates a broken old channel by forcing the client cursor to a stale
// high value after registration — exactly the state every pre-restart
// channel is in. With the deployed fix the node clamps the cursor and the
// loopback must come back; without it this times out.

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';
import 'test_helpers.dart';

const nodeA = '5.75.137.166:59558';

void main() {
  setUpAll(() {
    RpLog.minLevel = LogLevel.debug;
    RpLog.sink = (message, level) => print('[rp:${level.name}] $message');
  });

  test('realnet: stale high cursor heals, loopback succeeds', () async {
    final keys = await KeyPair.generate();
    final client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: [nodeA],
      hopCandidateFilter: (PeerStats p) => false,
    );
    await client.connect();
    addTearDown(client.disconnect);
    expect(await waitForEncryption(client), isTrue);

    final channel = await Channel.generate('heal-probe');
    client.addChannelKeys(
      channel.id,
      channel.encryptionKey,
      isChannelCreator: true,
    );
    await client.registerOutboundHandle(channelId: channel.id);
    await Future.delayed(const Duration(seconds: 5));

    // Simulate the broken-old-channel state: stale persisted cursor far
    // above anything the (fresh) server-side mailbox ever assigned.
    final oh = client.registeredOutboundHandles.single;
    oh.lastCursor = 999;

    final result = await client.runLoopbackTest(channel.id);
    print(
      'HEAL PROBE: success=${result.success} hops=${result.hopCount} '
      'rtt=${result.roundtripMs}ms error=${result.error} '
      'cursorAfter=${oh.lastCursor}',
    );
    expect(result.success, isTrue, reason: 'error: ${result.error}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
