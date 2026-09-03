import 'dart:isolate';

import 'package:redpanda_light_client/src/client/isolate_protocol.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/domain/garlic_session_update.dart';
import 'package:redpanda_light_client/src/domain/group_state.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_fetch_status.dart';
import 'package:redpanda_light_client/src/domain/oh_mailbox_update.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/peer_oh_update.dart';
import 'package:redpanda_light_client/src/domain/routing_ack.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/node_scorer.dart';
import 'package:test/test.dart';

/// T110: the generic state channel rests on ONE assumption — every
/// [StateUpdate] subtype is isolate-sendable as-is, because the transport no
/// longer converts anything into per-event "…Data" primitives.
///
/// This test spawns a REAL worker isolate that builds one instance of every
/// subtype (including [OwnOhSetUpdate], which carries an [OHRegistration] with
/// its Ed25519 keypair) and sends them over a [SendPort] exactly the way the
/// worker does. A subtype that stops being sendable fails here instead of
/// silently killing the worker's state forwarder in the field.
void main() {
  test('every StateUpdate subtype survives the isolate boundary', () async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(buildUpdates, receivePort.sendPort);
    addTearDown(() => isolate.kill(priority: Isolate.immediate));

    final received = <StateUpdate>[];
    await for (final message in receivePort) {
      if (message == 'done') break;
      received.add((message as EventStateUpdate).update);
    }
    receivePort.close();

    expect(
      received.map((u) => u.runtimeType).toList(),
      equals([
        RatchetStateUpdate,
        GarlicSessionUpdate,
        OhMailboxUpdate,
        OhFetchStatus,
        PeerOhUpdate,
        OwnOhSetUpdate,
        RoutingAckUpdate,
        ChannelAckUpdate,
        NodeScoreUpdate,
        GroupStateUpdate,
        GroupHandshakeEvent,
      ]),
    );

    // Spot-check the one payload that is not made of plain primitives: the
    // own-OH set travels with a live OHKeypair, and the private seed must
    // arrive intact (it is what re-registers the mailbox after a respawn).
    final ownOh = received.whereType<OwnOhSetUpdate>().single;
    expect(ownOh.channelId, equals('c1'));
    final handle = ownOh.handles.single;
    expect(handle.serverEndpoint, equals('host:59558'));
    expect(handle.lastCursor, equals(7));
    expect(handle.keypair.privateKeyBytes, hasLength(32));
    expect(handle.keypair.publicKeyBytes, hasLength(32));

    final peerOh = received.whereType<PeerOhUpdate>().single;
    expect(peerOh.descriptors.single.serverEndpoint, equals('peer:59558'));

    // MS08 Decision 13: the per-member id must survive the boundary. The old
    // hand-written EventRoutingAckUpdate/EventChannelAckUpdate had no field
    // for it, so group receipt aggregation never ran in the real app.
    expect(
      received.whereType<RoutingAckUpdate>().single.memberIdHex,
      equals('member-1'),
    );
    expect(
      received.whereType<ChannelAckUpdate>().single.memberIdHex,
      equals('member-1'),
    );
  });
}

/// Worker side: builds every [StateUpdate] subtype and ships it home.
Future<void> buildUpdates(SendPort port) async {
  final keypair = await OHKeypair.generate();
  final updates = <StateUpdate>[
    const RatchetStateUpdate(channelId: 'c1', stateJson: '{"v":1}'),
    const GarlicSessionUpdate(
      channelId: 'c1',
      sessionTags: {'aa': 1},
      pendingRgbHex: 'beef',
    ),
    OhMailboxUpdate(
      ohId: List<int>.filled(20, 1),
      channelId: 'c1',
      lastCursor: 3,
      expiresAtMs: 1000,
    ),
    OhFetchStatus(
      ohId: List<int>.filled(20, 1),
      channelId: 'c1',
      success: true,
      atMs: 1000,
    ),
    PeerOhUpdate(
      channelId: 'c1',
      descriptors: [
        OHDescriptor(
          serverEndpoint: 'peer:59558',
          handleId: List<int>.filled(20, 2),
          authPublicKey: List<int>.filled(32, 3),
        ),
      ],
    ),
    OwnOhSetUpdate(
      channelId: 'c1',
      handles: [
        OHRegistration(
          ohId: List<int>.filled(20, 4),
          keypair: keypair,
          expiresAtMs: 2000,
          channelId: 'c1',
          serverEndpoint: 'host:59558',
          lastCursor: 7,
        ),
      ],
    ),
    const RoutingAckUpdate.ack(
      channelId: 'c1',
      messageIdHex: 'ab12',
      status: 0,
      latencyMs: 42,
      memberIdHex: 'member-1',
    ),
    const ChannelAckUpdate(
      channelId: 'c1',
      messageIdHex: 'ab12',
      timestampMs: 1000,
      memberIdHex: 'member-1',
    ),
    const NodeScoreUpdate([
      NodeScore(
        nodeIdHex: 'aa',
        successCount: 1,
        failureCount: 0,
        avgLatencyMs: 10,
        lastUpdatedMs: 1,
      ),
    ]),
    const GroupStateUpdate(
      groupId: 'g1',
      label: 'group',
      keyEpoch: 1,
      members: [],
      cryptoStateJson: '{}',
      pendingItems: [],
      pendingRotations: {},
    ),
    const GroupHandshakeEvent(
      channelId: 'c1',
      isProposal: true,
      groupIdHex: 'ff',
    ),
  ];
  for (final update in updates) {
    port.send(EventStateUpdate(update));
  }
  port.send('done');
}
