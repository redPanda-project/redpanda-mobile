import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/client/worker_replay_state.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_fetch_status.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:test/test.dart';

/// T110: the worker-restore projection used to live inside
/// `RedPandaIsolateClient._patchChannelReplay` and was untestable without an
/// isolate. These tests pin the behaviour a respawned worker depends on: it
/// must be restored with the LATEST crypto and mailbox state, never a stale
/// snapshot.
void main() {
  List<int> ohId(int b) => List<int>.filled(20, b);

  CmdAddChannelKeys channelCmd(String id) => CmdAddChannelKeys(
    id,
    List<int>.filled(32, 1),
    channelSecret: List<int>.filled(32, 2),
    ownDisplayName: 'me',
    peerOhId: ohId(9),
    peerOhEndpoint: 'old-host:59558',
    isChannelCreator: true,
    ratchetState: 'ratchet-v1',
    sessionTags: const {'aa': 1},
    pendingRgbHex: 'beef',
  );

  Future<OHRegistration> registration(
    int b, {
    String? channelId,
    String endpoint = 'host:59558',
    int cursor = 0,
  }) async => OHRegistration(
    ohId: ohId(b),
    keypair: await OHKeypair.generate(),
    expiresAtMs: 5000,
    channelId: channelId,
    serverEndpoint: endpoint,
    lastCursor: cursor,
  );

  CmdAddChannelKeys onlyChannel(WorkerReplayState replay) =>
      replay.replayCommands().whereType<CmdAddChannelKeys>().single;

  List<CmdRestoreOutboundHandle> handles(WorkerReplayState replay) => replay
      .replayCommands()
      .whereType<CmdRestoreOutboundHandle>()
      .toList(growable: false);

  test('a ratchet update replaces only the ratchet state', () {
    final replay = WorkerReplayState()..recordChannelKeys(channelCmd('c1'));
    replay.apply(
      const RatchetStateUpdate(channelId: 'c1', stateJson: 'ratchet-v2'),
    );

    final cmd = onlyChannel(replay);
    expect(cmd.ratchetState, equals('ratchet-v2'));
    expect(cmd.sessionTags, equals({'aa': 1}));
    expect(cmd.pendingRgbHex, equals('beef'));
    expect(cmd.peerOhEndpoint, equals('old-host:59558'));
    expect(cmd.isChannelCreator, isTrue);
    expect(cmd.ownDisplayName, equals('me'));
  });

  test('a garlic update is an authoritative snapshot (RGB may null)', () {
    final replay = WorkerReplayState()..recordChannelKeys(channelCmd('c1'));
    replay.apply(
      const GarlicSessionUpdate(channelId: 'c1', sessionTags: {'bb': 2}),
    );

    final cmd = onlyChannel(replay);
    expect(cmd.sessionTags, equals({'bb': 2}));
    expect(cmd.pendingRgbHex, isNull);
    // Untouched by a garlic update.
    expect(cmd.ratchetState, equals('ratchet-v1'));
  });

  test('a peer-OH update moves the primary and the whole set', () {
    final replay = WorkerReplayState()..recordChannelKeys(channelCmd('c1'));
    replay.apply(
      PeerOhUpdate(
        channelId: 'c1',
        descriptors: [
          OHDescriptor(
            serverEndpoint: 'new-host:59558',
            handleId: ohId(7),
            authPublicKey: List<int>.filled(32, 3),
          ),
          OHDescriptor(
            serverEndpoint: 'other-host:59558',
            handleId: ohId(8),
            authPublicKey: List<int>.filled(32, 4),
          ),
        ],
      ),
    );

    final cmd = onlyChannel(replay);
    expect(cmd.peerOhEndpoint, equals('new-host:59558'));
    expect(cmd.peerOhId, equals(ohId(7)));
    expect(cmd.peerOhSet, hasLength(2));
    expect(cmd.peerOhSet!.first.endpoint, equals('new-host:59558'));
    // Crypto state survives a mailbox move.
    expect(cmd.ratchetState, equals('ratchet-v1'));
  });

  test('an empty peer-OH set never clears the known mailbox', () {
    final replay = WorkerReplayState()..recordChannelKeys(channelCmd('c1'));
    replay.apply(const PeerOhUpdate(channelId: 'c1', descriptors: []));

    expect(onlyChannel(replay).peerOhEndpoint, equals('old-host:59558'));
  });

  test('state for an unknown channel does not resurrect it', () {
    final replay = WorkerReplayState();
    replay.apply(const RatchetStateUpdate(channelId: 'ghost', stateJson: 'x'));

    expect(replay.replayCommands(), isEmpty);
  });

  test('a mailbox update advances cursor and expiry of the handle', () async {
    final replay = WorkerReplayState();
    final oh = await registration(1, channelId: 'c1');
    replay.recordOutboundHandle(
      CmdRestoreOutboundHandle(
        ohId: oh.ohId,
        privateKeyBytes: oh.keypair.privateKeyBytes.toList(),
        expiresAtMs: oh.expiresAtMs,
        channelId: 'c1',
        serverEndpoint: 'host:59558',
      ),
    );

    replay.apply(
      OhMailboxUpdate(
        ohId: ohId(1),
        channelId: 'c1',
        lastCursor: 42,
        expiresAtMs: 9000,
      ),
    );

    final restored = handles(replay).single;
    expect(restored.lastCursor, equals(42));
    expect(restored.expiresAtMs, equals(9000));
    expect(restored.serverEndpoint, equals('host:59558'));
    expect(
      restored.privateKeyBytes,
      equals(oh.keypair.privateKeyBytes.toList()),
    );
  });

  test('a mailbox update for an unknown handle is ignored', () {
    final replay = WorkerReplayState();
    replay.apply(OhMailboxUpdate(ohId: ohId(5), lastCursor: 1, expiresAtMs: 1));
    expect(replay.replayCommands(), isEmpty);
  });

  test('an own-OH set replaces exactly that channel\'s handles', () async {
    final replay = WorkerReplayState();
    final dead = await registration(1, channelId: 'c1');
    final foreign = await registration(3, channelId: 'c2');
    for (final oh in [dead, foreign]) {
      replay.recordOutboundHandle(
        CmdRestoreOutboundHandle(
          ohId: oh.ohId,
          privateKeyBytes: oh.keypair.privateKeyBytes.toList(),
          expiresAtMs: oh.expiresAtMs,
          channelId: oh.channelId,
          serverEndpoint: oh.serverEndpoint,
        ),
      );
    }

    final fresh = await registration(2, channelId: 'c1', cursor: 5);
    replay.apply(OwnOhSetUpdate(channelId: 'c1', handles: [fresh]));

    final ids = handles(replay).map((c) => c.ohId.first).toSet();
    // The dead mailbox of c1 is gone, c2's handle untouched.
    expect(ids, equals({2, 3}));
    final restored = handles(replay).firstWhere((c) => c.channelId == 'c1');
    expect(restored.lastCursor, equals(5));
    expect(
      restored.privateKeyBytes,
      equals(fresh.keypair.privateKeyBytes.toList()),
    );
  });

  test('an empty own-OH set clears that channel only', () async {
    // The cache mirrors the worker's live set — it is not a "last known
    // good" store, so an emptied channel must not replay dead handles.
    final replay = WorkerReplayState();
    final mine = await registration(1, channelId: 'c1');
    final foreign = await registration(3, channelId: 'c2');
    for (final oh in [mine, foreign]) {
      replay.recordOutboundHandle(
        CmdRestoreOutboundHandle(
          ohId: oh.ohId,
          privateKeyBytes: oh.keypair.privateKeyBytes.toList(),
          expiresAtMs: oh.expiresAtMs,
          channelId: oh.channelId,
          serverEndpoint: oh.serverEndpoint,
        ),
      );
    }

    replay.apply(const OwnOhSetUpdate(channelId: 'c1', handles: []));

    expect(handles(replay).map((c) => c.ohId.first).toSet(), equals({3}));
  });

  test('node scores are replayed, informational updates are not', () {
    final replay = WorkerReplayState();
    replay.apply(
      const NodeScoreUpdate([
        NodeScore(
          nodeIdHex: 'aa',
          successCount: 1,
          failureCount: 0,
          avgLatencyMs: 10,
          lastUpdatedMs: 1,
        ),
      ]),
    );
    replay.apply(const OhFetchStatus(ohId: [], success: true, atMs: 1));
    replay.apply(
      const GroupHandshakeEvent(
        channelId: 'c1',
        isProposal: true,
        groupIdHex: 'ff',
      ),
    );

    final commands = replay.replayCommands();
    expect(commands, hasLength(1));
    expect(
      (commands.single as CmdRestoreNodeScores).scores.single.nodeIdHex,
      equals('aa'),
    );
  });

  test('replay order is peers, channels, handles, groups, scores', () async {
    final replay = WorkerReplayState()
      ..recordPeer('1.2.3.4:59558')
      ..recordChannelKeys(channelCmd('c1'))
      ..recordGroup(
        CmdRegisterGroup(
          const GroupRegistration(
            groupId: 'g1',
            label: 'group',
            isAdmin: true,
            myMemberIdHex: 'aa',
            mySignSeed: [],
            myX25519Priv: [],
            keyEpoch: 1,
            members: [],
          ),
        ),
      )
      ..recordNodeScores(const [
        NodeScore(
          nodeIdHex: 'bb',
          successCount: 0,
          failureCount: 0,
          avgLatencyMs: 0,
          lastUpdatedMs: 0,
        ),
      ]);
    final oh = await registration(1, channelId: 'c1');
    replay.recordOutboundHandle(
      CmdRestoreOutboundHandle(
        ohId: oh.ohId,
        privateKeyBytes: oh.keypair.privateKeyBytes.toList(),
        expiresAtMs: oh.expiresAtMs,
        channelId: 'c1',
      ),
    );

    expect(
      replay.replayCommands().map((c) => c.runtimeType).toList(),
      equals([
        CmdAddPeer,
        CmdAddChannelKeys,
        CmdRestoreOutboundHandle,
        CmdRegisterGroup,
        CmdRestoreNodeScores,
      ]),
    );
  });

  test('an empty node-score snapshot sends no restore command', () {
    final replay = WorkerReplayState()..recordNodeScores(const []);
    expect(replay.replayCommands(), isEmpty);
  });

  group('T111: a partial re-register never costs the projection state', () {
    test('session tags, RGB and display name survive a subset re-register', () {
      final replay = WorkerReplayState()..recordChannelKeys(channelCmd('c1'));
      // Live state advanced past what any persisted row knows.
      replay.apply(
        const GarlicSessionUpdate(
          channelId: 'c1',
          sessionTags: {'live': 9},
          pendingRgbHex: 'cafe',
        ),
      );
      replay.apply(
        const RatchetStateUpdate(channelId: 'c1', stateJson: 'ratchet-v7'),
      );

      // Exactly the call `chat_screen.build` used to make: the channel row,
      // and nothing of the garlic session or the display name.
      replay.recordChannelKeys(
        CmdAddChannelKeys(
          'c1',
          List<int>.filled(32, 1),
          channelSecret: List<int>.filled(32, 2),
          peerOhId: ohId(9),
          peerOhEndpoint: 'old-host:59558',
          isChannelCreator: true,
          ratchetState: 'ratchet-v1',
        ),
      );

      final cmd = onlyChannel(replay);
      expect(cmd.sessionTags, equals({'live': 9}));
      expect(cmd.pendingRgbHex, equals('cafe'));
      expect(cmd.ownDisplayName, equals('me'));
      expect(cmd.ratchetState, equals('ratchet-v7'));
    });

    test('a stale re-register never moves the peer mailbox back', () {
      final replay = WorkerReplayState()..recordChannelKeys(channelCmd('c1'));
      replay.apply(
        PeerOhUpdate(
          channelId: 'c1',
          descriptors: [
            OHDescriptor(
              serverEndpoint: 'new-host:59558',
              handleId: ohId(7),
              authPublicKey: List<int>.filled(32, 3),
            ),
          ],
        ),
      );

      replay.recordChannelKeys(channelCmd('c1')); // carries ohId(9) again

      final cmd = onlyChannel(replay);
      expect(cmd.peerOhId, equals(ohId(7)));
      expect(cmd.peerOhEndpoint, equals('new-host:59558'));
      expect(cmd.peerOhSet, hasLength(1));
    });

    test('a consumed RGB is not resurrected by a re-register', () {
      final replay = WorkerReplayState()..recordChannelKeys(channelCmd('c1'));
      // The block was used; the live snapshot has no pending RGB any more.
      replay.apply(
        const GarlicSessionUpdate(channelId: 'c1', sessionTags: {'aa': 1}),
      );

      replay.recordChannelKeys(channelCmd('c1')); // still carries 'beef'

      expect(onlyChannel(replay).pendingRgbHex, isNull);
    });

    test('a re-register still fills gaps the projection has', () {
      // A channel first registered before anything was known about the
      // partner's mailbox or the ratchet.
      final replay = WorkerReplayState()
        ..recordChannelKeys(
          CmdAddChannelKeys(
            'c1',
            List<int>.filled(32, 1),
            isChannelCreator: false,
          ),
        );

      replay.recordChannelKeys(channelCmd('c1'));

      final cmd = onlyChannel(replay);
      expect(cmd.channelSecret, equals(List<int>.filled(32, 2)));
      expect(cmd.ownDisplayName, equals('me'));
      expect(cmd.peerOhId, equals(ohId(9)));
      expect(cmd.ratchetState, equals('ratchet-v1'));
      expect(cmd.sessionTags, equals({'aa': 1}));
      // The role is the channel's identity, not something a later caller
      // gets to flip.
      expect(cmd.isChannelCreator, isFalse);
    });
  });
}
