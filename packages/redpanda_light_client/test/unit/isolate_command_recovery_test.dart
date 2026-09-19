import 'dart:io';

import 'package:redpanda_light_client/src/client/isolate_client.dart';
import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/client/pending_command_queue.dart';
import 'package:redpanda_light_client/src/client/worker_replay_state.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/rendezvous_state_update.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:test/test.dart';

/// TD115: `RedPandaIsolateClient._send` used to DROP every command handed to
/// it while no worker isolate was attached ("For now just log"), so whether a
/// command survived the startup window or a respawn gap depended on whether
/// someone had remembered to make it replayable — `CmdEnsureOhRedundancy` was
/// the gap that got noticed.
///
/// The rule is now mechanical on two levels:
///  1. [IsolateCommand.recovery] is abstract, so the compiler forces every new
///     command class to declare whether it is re-established on worker ready
///     or must be queued. There is no third, silent option.
///  2. this test proves the declaration is TRUE — a command that claims to be
///     re-established must actually be produced by the worker-ready path, and
///     a command that claims to be queued must actually be bufferable.
///
/// The command classes are enumerated from the protocol SOURCE, not from a
/// hand-written list, so a newly added command class fails this test until it
/// is covered here (Dart has no usable reflection in this test runner).
void main() {
  // --- every command class in the protocol, with a sample instance ---------
  //
  // Adding a command class means adding it here; the first test below fails
  // otherwise.
  final samples = <String, IsolateCommand>{
    'CmdInit': CmdInit(),
    'CmdConnect': CmdConnect(),
    'CmdDisconnect': CmdDisconnect(),
    'CmdAddPeer': CmdAddPeer('10.0.0.1:59558'),
    'CmdLifecyclePause': CmdLifecyclePause(),
    'CmdLifecycleResume': CmdLifecycleResume(),
    'CmdSendMessage': CmdSendMessage(1, 'chan', 'hi'),
    'CmdRunLoopbackTest': CmdRunLoopbackTest(2, 'chan'),
    'CmdRunChannelDoctor': CmdRunChannelDoctor(3, 'chan'),
    'CmdRegisterOutboundHandle': CmdRegisterOutboundHandle(4),
    'CmdAddChannelKeys': CmdAddChannelKeys(
      'chan',
      List<int>.filled(32, 1),
      isChannelCreator: true,
    ),
    'CmdEnsureOhRedundancy': CmdEnsureOhRedundancy('chan'),
    'CmdRestoreRendezvousState': CmdRestoreRendezvousState('chan', '[]'),
    'CmdRestoreOutboundHandle': CmdRestoreOutboundHandle(
      ohId: List<int>.filled(20, 2),
      privateKeyBytes: List<int>.filled(32, 3),
      expiresAtMs: 1,
    ),
    'CmdRestoreNodeScores': CmdRestoreNodeScores(const <NodeScore>[]),
    'CmdRegisterGroup': CmdRegisterGroup(
      const GroupRegistration(
        groupId: 'g1',
        label: 'g',
        isAdmin: true,
        myMemberIdHex: 'aa',
        mySignSeed: <int>[],
        myX25519Priv: <int>[],
        keyEpoch: 1,
        members: <GroupMemberInfo>[],
      ),
    ),
    'CmdSendGroupMessage': CmdSendGroupMessage(5, 'g1', 'hi'),
    'CmdRotateGroupKey': CmdRotateGroupKey(6, 'g1', const []),
    'CmdRetryPendingRotations': CmdRetryPendingRotations(7, 'g1'),
    'CmdSendGroupHandshake': CmdSendGroupHandshake(8, 'chan', const []),
    'CmdSendGroupInfoUpdate': CmdSendGroupInfoUpdate(9, 'g1', 'label'),
  };

  /// Command class names as declared in the protocol source.
  Set<String> declaredCommandClasses() {
    final source = File(
      'lib/src/client/isolate_protocol.dart',
    ).readAsStringSync();
    return RegExp(
      r'class (Cmd\w+) extends IsolateCommand',
    ).allMatches(source).map((m) => m.group(1)!).toSet();
  }

  /// A replay projection carrying one of every kind of state it knows, so
  /// `replayCommands()` emits every command type the projection can restore.
  WorkerReplayState fullyPopulatedProjection() {
    final replay = WorkerReplayState()
      ..recordPeer('10.0.0.1:59558')
      ..recordChannelKeys(
        CmdAddChannelKeys(
          'chan',
          List<int>.filled(32, 1),
          isChannelCreator: true,
        ),
      )
      ..recordOutboundHandle(
        CmdRestoreOutboundHandle(
          ohId: List<int>.filled(20, 2),
          privateKeyBytes: List<int>.filled(32, 3),
          expiresAtMs: 1,
          channelId: 'chan',
        ),
      )
      ..recordGroup(samples['CmdRegisterGroup']! as CmdRegisterGroup)
      ..recordNodeScores([NodeScore.empty('ab')])
      ..apply(
        const RendezvousStateUpdate(channelId: 'chan', mergeStateJson: '[]'),
      );
    return replay;
  }

  test('every command class in the protocol has a sample instance here', () {
    expect(
      samples.keys.toSet(),
      equals(declaredCommandClasses()),
      reason:
          'a new IsolateCommand class must be classified (CommandRecovery) '
          'and covered by this test — see TD115',
    );
  });

  test('the sample instances are the classes their map keys name', () {
    for (final entry in samples.entries) {
      expect(entry.value.runtimeType.toString(), entry.key);
    }
  });

  test('every reestablishedOnWorkerReady command is really re-established', () {
    final claimed = {
      for (final cmd in samples.values)
        if (cmd.recovery == CommandRecovery.reestablishedOnWorkerReady)
          cmd.runtimeType,
    };

    // What the worker-ready path actually re-sends: the replay projection
    // plus the flag/init-driven commands (`_onWorkerReady`/`_replayState`).
    final replayed = fullyPopulatedProjection()
        .replayCommands()
        .map((c) => c.runtimeType)
        .toSet();
    final reestablished = {
      ...replayed,
      ...RedPandaIsolateClient.flagOrInitReestablishedCommands,
    };

    expect(
      replayed.intersection(
        RedPandaIsolateClient.flagOrInitReestablishedCommands,
      ),
      isEmpty,
      reason:
          'a command is either replayed from WorkerReplayState or carried '
          'by a flag, not both — one of the two mechanisms is dead code',
    );
    expect(
      claimed,
      equals(reestablished),
      reason:
          'a command claiming reestablishedOnWorkerReady that the ready '
          'path never sends is a SILENT DROP (TD115); a command the ready '
          'path sends but that claims to be queued would be delivered '
          'twice',
    );
  });

  test('a queued command is either request-bound or knowingly not', () {
    // `requestId` decides whether a buffered command survives a worker death
    // (see PendingCommandQueue.discardRequestBound). A new fire-and-forget
    // command therefore has to be added here deliberately instead of
    // inheriting the death policy by accident.
    const knownFireAndForget = {CmdEnsureOhRedundancy};
    for (final cmd in samples.values.where(
      (c) => c.recovery == CommandRecovery.queuedUntilWorkerReady,
    )) {
      expect(
        cmd.requestId != null,
        !knownFireAndForget.contains(cmd.runtimeType),
        reason:
            '${cmd.runtimeType}: a queued command either carries the request '
            'id of a waiting caller or is listed as fire-and-forget here',
      );
    }
  });

  test('every queuedUntilWorkerReady command can be buffered', () {
    final queue = PendingCommandQueue();
    final queued = samples.values
        .where((c) => c.recovery == CommandRecovery.queuedUntilWorkerReady)
        .toList();
    expect(queued, isNotEmpty);
    for (final cmd in queued) {
      expect(queue.add(cmd), isNull, reason: '${cmd.runtimeType} evicted');
    }
    expect(queue.drain().map((c) => c.runtimeType).toList(), [
      for (final cmd in queued) cmd.runtimeType,
    ]);
  });

  group('PendingCommandQueue', () {
    test('drains in FIFO order and empties itself', () {
      final queue = PendingCommandQueue()
        ..add(CmdEnsureOhRedundancy('a'))
        ..add(CmdEnsureOhRedundancy('b'));
      final drained = queue.drain().cast<CmdEnsureOhRedundancy>();
      expect(drained.map((c) => c.channelId), ['a', 'b']);
      expect(queue.isEmpty, isTrue);
      expect(queue.drain(), isEmpty);
    });

    test('overflow evicts the OLDEST command and reports it', () {
      final queue = PendingCommandQueue();
      for (var i = 0; i < PendingCommandQueue.capacity; i++) {
        expect(queue.add(CmdEnsureOhRedundancy('c$i')), isNull);
      }
      final evicted = queue.add(CmdEnsureOhRedundancy('overflow'));
      expect(evicted, isA<CmdEnsureOhRedundancy>());
      expect((evicted! as CmdEnsureOhRedundancy).channelId, 'c0');
      expect(queue.length, PendingCommandQueue.capacity);
      final drained = queue.drain().cast<CmdEnsureOhRedundancy>();
      expect(drained.first.channelId, 'c1');
      expect(drained.last.channelId, 'overflow');
    });

    test('remove drops the copy of a request whose caller gave up', () {
      // The isolate client calls this from every request timeout: a request
      // whose future already completed must not be executed by a later
      // flush (a first send attempt has no stable message id yet, so a late
      // execution would deliver a second, undedupable message).
      final queue = PendingCommandQueue();
      final abandoned = CmdSendMessage(1, 'chan', 'first attempt');
      final alive = CmdSendMessage(2, 'chan', 'still waiting');
      queue
        ..add(abandoned)
        ..add(alive);

      expect(queue.remove(abandoned), isTrue);
      // Only the abandoned one goes; an identical-looking command that was
      // never queued is not mistaken for it.
      expect(queue.remove(CmdSendMessage(1, 'chan', 'first attempt')), isFalse);
      expect(queue.drain(), [alive]);
    });

    test('a worker death discards requests but keeps fire-and-forget', () {
      final queue = PendingCommandQueue();
      final request = CmdSendMessage(1, 'chan', 'hi');
      final fireAndForget = CmdEnsureOhRedundancy('chan');
      queue
        ..add(request)
        ..add(fireAndForget);

      // The request's caller was just failed by `_failPendingRequests`;
      // re-running it after the respawn would execute a request nobody
      // awaits. The top-up has no caller, so dropping it would be exactly
      // the silent loss TD115 removes.
      expect(queue.discardRequestBound(), [request]);
      expect(queue.drain(), [fireAndForget]);
    });

    test('a reestablished command must not be buffered', () {
      // The queue must never hold a command the ready path replays: the
      // replay sends the newest state, the buffered copy an older one.
      expect(
        () => PendingCommandQueue().add(CmdAddPeer('10.0.0.1:1')),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
