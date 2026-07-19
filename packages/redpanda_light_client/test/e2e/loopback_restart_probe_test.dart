@Tags(['e2e'])
library;

// Probe (untracked, local-only): proves the cursor-reset bug. Sequence
// counters in OutboundMailboxStore are rebuilt from *surviving* items on
// node startup — a mailbox whose items were all acked (deleted) restarts
// its sequence at 1 after a node restart, while the client keeps its high
// persisted cursor. Every later deposit gets a sequence id <= cursor and
// is never returned by fetch: loopback (and real mail) silently dead.

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/logging/logger.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'test_helpers.dart';

const port = 51555;
final jarPath =
    Platform.environment['PROBE_JAR'] ??
    '/home/rbraun/redpanda/redpanda-mobile/references/redPandaj/target/redpanda.jar';

/// With the T40 fix in the node, the loopback must SUCCEED after the
/// restart; without it, it must fail (bug repro). Set PROBE_EXPECT=fixed.
final expectFixed = Platform.environment['PROBE_EXPECT'] == 'fixed';

/// Minimal node runner with a PERSISTENT working dir (mapdb data survives
/// restarts — the whole point of this probe).
class PersistentNode {
  final String workDir;
  Process? _process;
  StreamSubscription<List<int>>? _out, _err;

  PersistentNode(this.workDir) {
    Directory(workDir).createSync(recursive: true);
  }

  Future<void> start() async {
    _process = await Process.start(
      'java',
      ['-jar', jarPath],
      workingDirectory: workDir,
      environment: {'PORT': '$port'},
    );
    _out = _process!.stdout.listen((_) {});
    _err = _process!.stderr.listen((_) {});
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      try {
        final s = await Socket.connect('127.0.0.1', port);
        await s.close();
        s.destroy();
        return;
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) fail('node never opened $port');
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> stop() async {
    await _out?.cancel();
    await _err?.cancel();
    final p = _process;
    if (p == null) return;
    p.kill(ProcessSignal.sigterm);
    try {
      await p.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      p.kill(ProcessSignal.sigkill);
      await p.exitCode;
    }
    _process = null;
  }
}

void main() {
  setUpAll(() {
    RpLog.minLevel = LogLevel.debug;
    RpLog.sink = (message, level) => print('[rp:${level.name}] $message');
  });

  test('loopback works, node restarts, loopback dead (stale cursor)',
      () async {
    final node = PersistentNode(
      '/tmp/claude-1000/-home-rbraun-redpanda/17cd842e-6e68-404c-86a4-0043576f77bb/scratchpad/restart_probe_node',
    );
    await node.start();
    addTearDown(node.stop);

    final keys = await KeyPair.generate();
    final client = RedPandaLightClient(
      selfNodeId: NodeId.fromPublicKey(keys),
      selfKeys: keys,
      seeds: ['127.0.0.1:$port'],
      hopCandidateFilter: (_) => false, // direct deposit, no garlic
    );
    await client.connect();
    addTearDown(client.disconnect);
    expect(await waitForEncryption(client), isTrue);

    final channel = await Channel.generate('restart-probe');
    client.addChannelKeys(
      channel.id,
      channel.encryptionKey,
      isChannelCreator: true,
    );
    await client.registerOutboundHandle(channelId: channel.id);

    final before = await client.runLoopbackTest(channel.id);
    print('BEFORE restart: success=${before.success} error=${before.error}');
    expect(before.success, isTrue, reason: 'error: ${before.error}');

    final oh = client.registeredOutboundHandles.single;
    print('cursor after first loopback: ${oh.lastCursor}');

    // Let the ackFetch delete the item on the node before restarting.
    await Future.delayed(const Duration(seconds: 3));

    print('=== restarting node ===');
    await node.stop();
    await node.start();

    // Wait for the client to reconnect.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (client.activePeerAddresses.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('client never reconnected');
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    expect(await waitForEncryption(client), isTrue);
    await Future.delayed(const Duration(seconds: 2));

    final after = await client.runLoopbackTest(
      channel.id,
      timeout: const Duration(seconds: 20),
    );
    print(
      'AFTER restart: success=${after.success} error=${after.error} '
      '(cursor=${oh.lastCursor})',
    );
    if (expectFixed) {
      expect(
        after.success,
        isTrue,
        reason:
            'T40-fixed node must heal the stale cursor: ${after.error}',
      );
    } else {
      // Bug reproduction: fails although deposit + fetch are healthy.
      expect(
        after.success,
        isFalse,
        reason:
            'expected the stale-cursor bug to swallow the loopback message',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
