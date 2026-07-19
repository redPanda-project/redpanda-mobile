@Tags(['e2e'])
library;

// Probe (untracked, local-only): reproduces the Connection-doctor loopback
// failure against the REAL testnet. Runs the loopback twice on one client:
//   1. default (garlic hops, like the phone)
//   2. hopCandidateFilter disabled (direct deposit, like the unit test)
// Prints all RpLog output so the failing leg is visible.

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';
import 'test_helpers.dart';

const nodeA = '5.75.137.166:59558';

Future<RedPandaLightClient> makeClient({
  bool Function(PeerStats peer)? hopCandidateFilter,
}) async {
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: [nodeA],
    hopCandidateFilter: hopCandidateFilter,
  );
  await client.connect();
  expect(await waitForEncryption(client), isTrue, reason: 'encrypted session');
  return client;
}

Future<void> runProbe(RedPandaLightClient client, String label) async {
  final channel = await Channel.generate('loopback-probe');
  client.addChannelKeys(
    channel.id,
    channel.encryptionKey,
    isChannelCreator: true,
  );
  await client.registerOutboundHandle(channelId: channel.id);
  // Give peer exchange a moment so hop candidates (other nodes + keys) exist.
  await Future.delayed(const Duration(seconds: 8));
  final sw = Stopwatch()..start();
  final result = await client.runLoopbackTest(channel.id);
  print(
    '[$label] success=${result.success} hops=${result.hopCount} '
    'rtt=${result.roundtripMs}ms error=${result.error} '
    '(waited ${sw.elapsed.inSeconds}s)',
  );
}

void main() {
  setUpAll(() {
    RpLog.minLevel = LogLevel.debug;
    RpLog.sink = (message, level) => print('[rp:${level.name}] $message');
  });

  test('realnet loopback via garlic hops (phone path)', () async {
    final client = await makeClient();
    addTearDown(client.disconnect);
    await runProbe(client, 'GARLIC');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('realnet loopback direct deposit (no hops)', () async {
    final client = await makeClient(hopCandidateFilter: (_) => false);
    addTearDown(client.disconnect);
    await runProbe(client, 'DIRECT');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
