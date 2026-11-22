import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/client/rendezvous_timing.dart';
import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';
import 'package:redpanda_light_client/src/crypto/ratchet.dart';
import 'package:redpanda_light_client/src/crypto/rendezvous_manager.dart';
import 'package:redpanda_light_client/src/domain/counterpart_oh_update.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/oh_registration.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/return_path.dart';
import 'package:redpanda_light_client/src/generated/outbound.pb.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/models/peer_stats.dart';
import 'package:redpanda_light_client/src/network/active_peer.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

import '../helpers/garlic_test_utils.dart';

/// T160/T161 pairing order. A scripted in-memory node answers registration,
/// subscribe and fetch; every garlic packet (command 142) the client submits
/// is peeled with the known relay keys, so the test sees exactly which
/// rendezvous packets (record_store / record_lookup) and deposits went out,
/// in which order, and can answer a lookup through the client's own mailbox
/// the way a node does (a fetched item tagged with the lookup's ack tag).
class ScriptedNode implements Socket {
  @override
  Future<void> get done => Completer<void>().future;

  final _incoming = StreamController<Uint8List>();
  final List<int> _outBuffer = [];
  bool _handshakeAnswered = false;

  /// Items the next fetch (command 152) hands out, then cleared.
  final List<MailItem> mailbox = [];

  /// Every submitted garlic packet, in submission order.
  final List<Uint8List> garlic = [];

  static Uint8List nodeHandshake() {
    final b = BytesBuilder();
    b.add('k3gV'.codeUnits);
    b.addByte(22);
    b.addByte(0);
    b.add(Uint8List(20));
    b.add(Uint8List(4));
    return b.toBytes();
  }

  void _reply(List<int> data) {
    if (!_incoming.isClosed) _incoming.add(Uint8List.fromList(data));
  }

  void _replyCommand(int command, List<int> protobufBytes) {
    final b = BytesBuilder();
    b.addByte(command);
    final len = ByteData(4)..setInt32(0, protobufBytes.length, Endian.big);
    b.add(len.buffer.asUint8List());
    b.add(protobufBytes);
    _reply(b.toBytes());
  }

  void _onFrame(int command, Uint8List payload) {
    switch (command) {
      case 150:
        _replyCommand(
          151,
          (RegisterOhResponse()
                ..status = Status.OK
                ..expiresAtMs = fixnum.Int64(
                  DateTime.now()
                      .add(const Duration(days: 7))
                      .millisecondsSinceEpoch,
                ))
              .writeToBuffer(),
        );
      case 159:
        _replyCommand(
          160,
          (SubscribeResponse()..status = Status.OK).writeToBuffer(),
        );
      case 152:
        final items = List.of(mailbox);
        mailbox.clear();
        _replyCommand(
          153,
          (FetchResponse()
                ..status = Status.OK
                ..nextCursor = fixnum.Int64(items.length + 1)
                ..items.addAll(items))
              .writeToBuffer(),
        );
      case 142:
        garlic.add(payload);
    }
  }

  @override
  void add(List<int> data) {
    _outBuffer.addAll(data);
    if (!_handshakeAnswered) {
      if (_outBuffer.length < 30) return;
      _outBuffer.removeRange(0, 30);
      _handshakeAnswered = true;
      _reply(nodeHandshake());
    }
    while (_outBuffer.isNotEmpty) {
      final command = _outBuffer[0];
      if (const {141, 142, 150, 152, 156, 159}.contains(command)) {
        if (_outBuffer.length < 5) return;
        final len = ByteData.sublistView(
          Uint8List.fromList(_outBuffer.sublist(1, 5)),
        ).getInt32(0, Endian.big);
        if (_outBuffer.length < 5 + len) return;
        final payload = Uint8List.fromList(_outBuffer.sublist(5, 5 + len));
        _outBuffer.removeRange(0, 5 + len);
        _onFrame(command, payload);
      } else {
        _outBuffer.removeAt(0);
      }
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  void destroy() => _incoming.close();

  @override
  Future<void> close() async => _incoming.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const nodeEndpoint = 'scripted:1';
const chan = 'chan';
final channelKey = List<int>.generate(32, (i) => i + 1);
final channelSecret = List<int>.generate(32, (i) => 200 - i);

/// Short, deterministic T160 timing: the tests exercise the order of
/// events, not the production durations (those are pinned in
/// `rendezvous_timing_test.dart`).
const testHold = Duration(milliseconds: 400);
RendezvousTiming testTiming() => RendezvousTiming(
  prePublishHoldMax: testHold,
  pairingLookupDelays: const [
    Duration(milliseconds: 250),
    Duration(milliseconds: 250),
    Duration(milliseconds: 250),
  ],
  jitter: 0,
  firstRetryFloor: Duration.zero,
  yesterdayOffsetMin: const Duration(milliseconds: 40),
  yesterdayOffsetMax: const Duration(milliseconds: 40),
  random: Random(7),
);

Future<(RedPandaLightClient, ScriptedNode, List<TestHop>)> connectedClient({
  int hopCount = 6,
  RendezvousTiming? timing,
  bool Function(PeerStats peer)? hopFilter,
}) async {
  final node = ScriptedNode();
  final repo = InMemoryPeerRepository();
  final relays = <TestHop>[];
  for (var i = 0; i < hopCount; i++) {
    final hop = await TestHop.generate(i + 1);
    relays.add(hop);
    repo.updatePeer(
      '10.3.0.$i:5000',
      nodeId: HEX.encode(hop.nodeId),
      encryptionPublicKey: HEX.encode(hop.keys.publicKey),
    );
  }
  final keys = await KeyPair.generate();
  final client = RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: [nodeEndpoint],
    peerRepository: repo,
    rendezvousTiming: timing ?? testTiming(),
    hopCandidateFilter: hopFilter,
    socketFactory: (h, p) async {
      if (h == 'scripted') return node;
      throw const SocketException('test: unreachable');
    },
  );
  await client.connect();
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (client.activePeerAddresses.isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('node never became verified');
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return (client, node, relays);
}

Future<void> pumpUntil(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('pumpUntil timed out${reason != null ? ': $reason' : ''}');
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

/// Today's (index 0) and yesterday's (index 1) record key, hex.
Future<List<String>> recordKeysHex() async {
  final m = RendezvousManager()
    ..register(
      chan,
      channelSecret: channelSecret,
      isCreator: true,
      ownName: '',
    );
  final keys = await m.lookupKeys(chan, DateTime.now().millisecondsSinceEpoch);
  return [for (final k in keys) HEX.encode(k)];
}

/// One peeled garlic packet as the node would see it at the exit.
class Submitted {
  final int command;
  final Uint8List inner;
  final String exitNodeIdHex;
  Submitted(this.command, this.inner, this.exitNodeIdHex);

  bool get isStore => command == GarlicBuilder.cmdRecordStore;
  bool get isLookup => command == GarlicBuilder.cmdRecordLookup;
  bool get isDeposit => !isStore && !isLookup;

  /// The looked-up record key (hex).
  String get lookupKeyHex => HEX.encode(inner.sublist(1, 21));

  /// The lookup's ack session tag (the answer must carry it).
  Uint8List get lookupAckTag =>
      ReturnPathBlock.deserialize(inner.sublist(1 + 20)).ackSessionTag;

  /// The stored record's entries, decrypted with the channel secret.
  Future<List<RendezvousEntry>> storedEntries() async {
    final len = ByteData.sublistView(inner, 1, 5).getUint32(0);
    final record = RendezvousManager.recordFromStoreBytes(
      inner.sublist(5, 5 + len),
    );
    return ChannelRendezvous.decryptRecordContent(
      channelSecret,
      record.content,
    );
  }

  /// The stored record's timestamp.
  int get storedTs {
    final len = ByteData.sublistView(inner, 1, 5).getUint32(0);
    return RendezvousManager.recordFromStoreBytes(
      inner.sublist(5, 5 + len),
    ).timestampMs;
  }

  Future<Set<String>> storedParticipants() async => {
    for (final e in await storedEntries()) HEX.encode(e.participantId),
  };
}

Future<List<Submitted>> peelAll(ScriptedNode node, List<TestHop> relays) async {
  final out = <Submitted>[];
  for (final packet in List.of(node.garlic)) {
    final peeled = await peelGarlicToExit(packet, relays);
    out.add(Submitted(peeled.inner[0], peeled.inner, peeled.exitNodeIdHex));
  }
  return out;
}

String participantHex({required bool creator}) => HEX.encode(
  ChannelRendezvous.participantId(channelSecret, isCreator: creator),
);

OHDescriptor creatorOh(int seed) => OHDescriptor(
  serverEndpoint: 'creator$seed:59558',
  handleId: List<int>.generate(20, (i) => (seed * 7 + i) & 0xFF),
  authPublicKey: List<int>.generate(32, (i) => (seed + i) & 0xFF),
);

OHDescriptor joinerOh(int seed) => OHDescriptor(
  serverEndpoint: 'joiner$seed:59558',
  handleId: List<int>.generate(20, (i) => (seed * 11 + i + 100) & 0xFF),
  authPublicKey: List<int>.generate(32, (i) => (seed + i + 50) & 0xFF),
);

/// A record published by the [creator] (or joiner) side alone:
/// `[1 found][KademliaStore]`, the payload of a record_lookup answer.
Future<Uint8List> recordAnswer(
  List<OHDescriptor> ohs, {
  bool creator = true,
  int? atMs,
  List<RendezvousEntry> extraEntries = const [],
}) async {
  final m = RendezvousManager()
    ..register(
      chan,
      channelSecret: channelSecret,
      isCreator: creator,
      ownName: creator ? 'Alice' : 'Bob',
    );
  m.setOwnOhs(chan, ohs);
  final now = atMs ?? DateTime.now().millisecondsSinceEpoch;
  if (extraEntries.isNotEmpty) {
    m.restoreMergeState(
      chan,
      jsonEncode([
        for (final e in extraEntries)
          {
            'pid': HEX.encode(e.participantId),
            'name': e.name,
            'ts': e.entryTs,
            'ohs': [for (final oh in e.ohs) oh.toJsonMap()],
          },
      ]),
    );
  }
  final store = (await m.buildSignedStore(chan, now))!;
  return Uint8List.fromList([1, ...store]);
}

Future<Uint8List> creatorAnswer(
  List<OHDescriptor> ohs, {
  int? atMs,
  List<RendezvousEntry> extraEntries = const [],
}) => recordAnswer(ohs, atMs: atMs, extraEntries: extraEntries);

final Uint8List noRecordAnswer = Uint8List.fromList([0]);

MailItem answerItem(Uint8List ackTag, List<int> payload) => MailItem(
  payload: payload,
  sessionTag: ackTag,
  receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
);

Future<void> deliver(
  RedPandaLightClient client,
  ScriptedNode node,
  OHRegistration ownOh,
  MailItem item,
) async {
  node.mailbox.add(item);
  await client.fetchMessages(ownOh);
}

Future<OHRegistration> restoredOwnOh(RedPandaLightClient client) async {
  final oh = OHRegistration(
    ohId: List.generate(20, (i) => 60 + i),
    keypair: await OHKeypair.generate(),
    expiresAtMs: DateTime.now()
        .add(const Duration(days: 7))
        .millisecondsSinceEpoch,
    channelId: chan,
    serverEndpoint: nodeEndpoint,
  );
  await client.restoreOutboundHandle(oh);
  return oh;
}

Future<Uint8List> firstDepositPacket(
  ScriptedNode node,
  List<TestHop> relays,
) async {
  for (final packet in List.of(node.garlic)) {
    final inner = await peelGarlicInnermost(packet, relays);
    if (inner[0] != GarlicBuilder.cmdRecordStore &&
        inner[0] != GarlicBuilder.cmdRecordLookup) {
      return packet;
    }
  }
  fail('no deposit was submitted');
}

bool sameBytes(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);

void main() {
  setUpAll(() => ActivePeer.plaintextTransportForTesting = true);
  tearDownAll(() => ActivePeer.plaintextTransportForTesting = false);

  group('T160 joiner: read before write', () {
    test('the joiner looks up first and publishes only the MERGED record; '
        'adopting the creator announces the own mailboxes (T161)', () async {
      final (client, node, relays) = await connectedClient(
        // Long hold: only the answer may end it here.
        timing: RendezvousTiming(
          prePublishHoldMax: const Duration(seconds: 20),
          jitter: 0,
          random: Random(1),
        ),
      );
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      final learned = <CounterpartOhUpdate>[];
      final sub = client.stateUpdates.of<CounterpartOhUpdate>().listen(
        learned.add,
      );
      addTearDown(sub.cancel);

      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      final ownOh = await client.registerOutboundHandle(channelId: chan);

      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isLookup),
        reason: 'the joiner never looked the record up',
      );
      var sent = await peelAll(node, relays);
      expect(sent.where((s) => s.isStore), isEmpty);
      final today = sent.firstWhere((s) => s.isLookup);
      expect(today.lookupKeyHex, keys[0], reason: 'today\'s key goes first');

      final aliceOhs = [creatorOh(1), creatorOh(2)];
      await deliver(
        client,
        node,
        ownOh,
        answerItem(today.lookupAckTag, await creatorAnswer(aliceOhs)),
      );
      await pumpUntil(() => learned.isNotEmpty, reason: 'no adoption');
      expect(client.counterpartOhIds(chan), hasLength(2));
      expect(client.pairingLookupsActive(chan), isFalse);

      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isStore),
        reason: 'the held publish never went out',
      );
      sent = await peelAll(node, relays);
      expect(await sent.firstWhere((s) => s.isStore).storedParticipants(), {
        participantHex(creator: true),
        participantHex(creator: false),
      });

      // T161: the own mailbox set is announced in-band right away.
      await pumpUntil(
        () async =>
            (await peelAll(node, relays)).where((s) => s.isDeposit).length >= 2,
        reason: 'no oh_update announce after the rendezvous adoption',
      );
      final creatorSession = await RatchetSession.create(
        channelKey: channelKey,
        isChannelCreator: true,
      );
      final deposit = (await peelGarlicDeposit(
        await firstDepositPacket(node, relays),
        relays,
      ))!;
      expect(aliceOhs.any((oh) => sameBytes(oh.handleId, deposit.ohId)), true);
      final message = await creatorSession.decrypt(deposit.payload, chan);
      expect(message.isOhUpdate, isTrue);
      final announced = jsonDecode(utf8.decode(message.ohUpdate!)) as List;
      expect(
        announced.map(
          (m) => OHDescriptor.fromJsonMap(m as Map<String, dynamic>).handleId,
        ),
        contains(equals(ownOh.ohId)),
      );
    });

    test('P1: every answer of the hold lost — the own entry is written once, '
        'and the NEXT publish reads first again', () async {
      final (client, node, relays) = await connectedClient();
      addTearDown(client.disconnect);
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      await client.registerOutboundHandle(channelId: chan);

      // Nobody answers: after the hold, the joiner writes itself.
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isStore),
        reason: 'the joiner stayed silent after the hold expired',
      );
      var sent = await peelAll(node, relays);
      final firstStore = sent.indexWhere((s) => s.isStore);
      expect(await sent[firstStore].storedParticipants(), {
        participantHex(creator: false),
      });

      // A further own mailbox (redundancy top-up) changes the set: this
      // publish must be preceded by a read again — the joiner still knows no
      // creator entry.
      await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async =>
            (await peelAll(node, relays)).where((s) => s.isStore).length >= 2,
        reason: 'the second publish never went out',
      );
      sent = await peelAll(node, relays);
      final secondStore = sent.lastIndexWhere((s) => s.isStore);
      final stores = [
        for (var i = 0; i < sent.length; i++)
          if (sent[i].isStore) i,
      ];
      expect(stores, hasLength(2));
      expect(
        sent.sublist(firstStore + 1, secondStore).any((s) => s.isLookup),
        isTrue,
        reason: 'the second publish must read first',
      );
    });

    test(
      'P3: a late answer with the creator\'s OLDER record after the '
      'hold timed out makes the joiner republish the merged record',
      () async {
        final (client, node, relays) = await connectedClient();
        addTearDown(client.disconnect);
        final keys = await recordKeysHex();
        client.addChannelKeys(
          chan,
          channelKey,
          channelSecret: channelSecret,
          isChannelCreator: false,
        );
        final createdAt = DateTime.now().millisecondsSinceEpoch - 60000;
        final ownOh = await client.registerOutboundHandle(channelId: chan);
        await pumpUntil(
          () async => (await peelAll(node, relays)).any((s) => s.isStore),
        );
        var sent = await peelAll(node, relays);
        final ownStore = sent.firstWhere((s) => s.isStore);
        final firstLookup = sent.firstWhere(
          (s) => s.isLookup && s.lookupKeyHex == keys[0],
        );

        // The answer to the FIRST lookup comes back only now, carrying the
        // creator's record from channel creation — older than our write.
        final answer = await creatorAnswer([creatorOh(3)], atMs: createdAt);
        expect(
          RendezvousManager.recordFromStoreBytes(answer.sublist(1)).timestampMs,
          lessThan(ownStore.storedTs),
        );
        await deliver(
          client,
          node,
          ownOh,
          answerItem(firstLookup.lookupAckTag, answer),
        );

        await pumpUntil(
          () async =>
              (await peelAll(node, relays)).where((s) => s.isStore).length >= 2,
          reason: 'no republish after learning the creator from a late answer',
        );
        sent = await peelAll(node, relays);
        expect(await sent.lastWhere((s) => s.isStore).storedParticipants(), {
          participantHex(creator: true),
          participantHex(creator: false),
        });
        expect(client.counterpartOhIds(chan), hasLength(1));
      },
    );

    test('only a record FOUND under TODAY\'s key releases the hold — not '
        '"no record" (blacklist false negative), not a stray tag, not '
        'yesterday\'s record; today\'s key is asked once more (Q3)', () async {
      final (client, node, relays) = await connectedClient(
        timing: RendezvousTiming(
          prePublishHoldMax: const Duration(seconds: 20),
          pairingLookupDelays: const [
            Duration(milliseconds: 600),
            Duration(seconds: 30),
          ],
          jitter: 0,
          firstRetryFloor: Duration.zero,
          yesterdayOffsetMin: const Duration(milliseconds: 40),
          yesterdayOffsetMax: const Duration(milliseconds: 40),
          random: Random(3),
        ),
      );
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      final ownOh = await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async =>
            (await peelAll(node, relays)).where((s) => s.isLookup).length >= 2,
        reason: 'today\'s and yesterday\'s lookup',
      );
      var sent = await peelAll(node, relays);
      final today = sent.firstWhere((s) => s.lookupKeyHex == keys[0]);
      final yesterday = sent.firstWhere((s) => s.lookupKeyHex == keys[1]);

      final now = DateTime.now().millisecondsSinceEpoch;
      final oldOh = creatorOh(1); // the creator's mailbox in yesterday's record
      final newOh = creatorOh(2); // and in today's, newer record
      await deliver(
        client,
        node,
        ownOh,
        answerItem(Uint8List.fromList(List.filled(16, 9)), noRecordAnswer),
      );
      await deliver(
        client,
        node,
        ownOh,
        answerItem(today.lookupAckTag, noRecordAnswer),
      );
      await deliver(
        client,
        node,
        ownOh,
        answerItem(
          yesterday.lookupAckTag,
          await creatorAnswer([oldOh], atMs: now - 3600 * 1000),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      sent = await peelAll(node, relays);
      expect(
        sent.where((s) => s.isStore),
        isEmpty,
        reason: 'neither "no record" nor yesterday\'s record may release',
      );

      // Yesterday's record was adopted and ended the pairing sequence; the
      // client asks today's key once more, and that answer finds today's
      // record.
      await pumpUntil(
        () async =>
            (await peelAll(
              node,
              relays,
            )).where((s) => s.isLookup && s.lookupKeyHex == keys[0]).length >=
            2,
        reason: 'today\'s key was not asked again',
      );
      final pairingLookup = (await peelAll(
        node,
        relays,
      )).where((s) => s.isLookup && s.lookupKeyHex == keys[0]).elementAt(1);
      await deliver(
        client,
        node,
        ownOh,
        answerItem(pairingLookup.lookupAckTag, await creatorAnswer([newOh])),
      );
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isStore),
        timeout: const Duration(seconds: 3),
        reason: 'today\'s found record must release the hold',
      );
      final entries = await (await peelAll(
        node,
        relays,
      )).firstWhere((s) => s.isStore).storedEntries();
      final creatorEntry = entries.firstWhere(
        (e) => HEX.encode(e.participantId) == participantHex(creator: true),
      );
      expect(
        sameBytes(creatorEntry.ohs.single.handleId, newOh.handleId),
        isTrue,
        reason: 'the write carries today\'s creator entry, not yesterday\'s',
      );
    });
    test('Q4: the first answer lost — a pairing lookup\'s found answer '
        'releases the hold long before it would run out', () async {
      final (client, node, relays) = await connectedClient(
        timing: RendezvousTiming(
          prePublishHoldMax: const Duration(seconds: 20),
          pairingLookupDelays: const [
            Duration(milliseconds: 500),
            Duration(seconds: 30),
          ],
          jitter: 0,
          firstRetryFloor: Duration.zero,
          yesterdayOffsetMin: const Duration(milliseconds: 40),
          yesterdayOffsetMax: const Duration(milliseconds: 40),
          random: Random(5),
        ),
      );
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      final ownOh = await client.registerOutboundHandle(channelId: chan);
      // Nobody answers the first round; the pairing step at +500 ms asks
      // today's key again.
      await pumpUntil(
        () async =>
            (await peelAll(
              node,
              relays,
            )).where((s) => s.isLookup && s.lookupKeyHex == keys[0]).length >=
            2,
        reason: 'the pairing lookup never went out',
      );
      final step = (await peelAll(
        node,
        relays,
      )).where((s) => s.isLookup && s.lookupKeyHex == keys[0]).elementAt(1);
      await deliver(
        client,
        node,
        ownOh,
        answerItem(step.lookupAckTag, await creatorAnswer([creatorOh(3)])),
      );
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isStore),
        timeout: const Duration(seconds: 3),
        reason: 'the pairing lookup\'s answer did not release the hold',
      );
      expect(
        await (await peelAll(
          node,
          relays,
        )).firstWhere((s) => s.isStore).storedParticipants(),
        {participantHex(creator: true), participantHex(creator: false)},
      );
    });

    test('Q1: when no route avoids today\'s executing node, yesterday\'s '
        'lookup still goes out on an ordinary route', () async {
      // Only one relay may serve as a hop: today's lookup exits there, and
      // avoiding it leaves nothing.
      final (client, node, relays) = await connectedClient(
        hopFilter: (p) => p.address == '10.3.0.0:5000',
      );
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async => (await peelAll(
          node,
          relays,
        )).any((s) => s.isLookup && s.lookupKeyHex == keys[1]),
        timeout: const Duration(seconds: 3),
        reason: 'yesterday\'s lookup was dropped in the small network',
      );
    });

    test('Q5: a first read that could not be sent starts no pairing '
        'sequence; the next read that goes out starts it with yesterday\'s '
        'lookup', () async {
      var hopsAllowed = false;
      final (client, node, relays) = await connectedClient(
        hopFilter: (_) => hopsAllowed,
      );
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      await client.registerOutboundHandle(channelId: chan);
      await Future.delayed(const Duration(milliseconds: 300));
      expect(await peelAll(node, relays), isEmpty);
      expect(client.pairingLookupsActive(chan), isFalse);
      expect(client.pairingLookupAttemptsOf(chan), 0);

      hopsAllowed = true;
      await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async => (await peelAll(
          node,
          relays,
        )).any((s) => s.isLookup && s.lookupKeyHex == keys[1]),
        timeout: const Duration(seconds: 3),
        reason: 'the first round that went out must ask yesterday\'s key',
      );
      await pumpUntil(
        () => client.pairingLookupAttemptsOf(chan) >= 1,
        timeout: const Duration(seconds: 3),
        reason: 'the pairing sequence did not start',
      );
    });

    test('a third participant\'s entry survives the joiner\'s merged '
        'publish (the record is shared by every participant)', () async {
      final (client, node, relays) = await connectedClient();
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      final ownOh = await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isLookup),
      );
      final lookup = (await peelAll(
        node,
        relays,
      )).firstWhere((s) => s.isLookup && s.lookupKeyHex == keys[0]);

      final third = RendezvousEntry(
        participantId: CryptoUtils.randomBytes(32),
        name: 'Carol',
        entryTs: DateTime.now().millisecondsSinceEpoch - 1000,
        ohs: [creatorOh(9)],
      );
      await deliver(
        client,
        node,
        ownOh,
        answerItem(
          lookup.lookupAckTag,
          await creatorAnswer([creatorOh(1)], extraEntries: [third]),
        ),
      );
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isStore),
        reason: 'the held publish never went out',
      );
      final stored = await (await peelAll(
        node,
        relays,
      )).firstWhere((s) => s.isStore).storedParticipants();
      expect(stored, {
        participantHex(creator: true),
        participantHex(creator: false),
        HEX.encode(third.participantId),
      });
    });

    test('P6: the first round asks yesterday\'s key on its own route and '
        'later; the pairing lookups ask only today\'s', () async {
      final (client, node, relays) = await connectedClient();
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: false,
      );
      await client.registerOutboundHandle(channelId: chan);
      // Three pairing lookups at +250 ms each, then the sequence is used up.
      await pumpUntil(
        () =>
            client.pairingLookupAttemptsOf(chan) >= 3 &&
            !client.pairingLookupsActive(chan),
        reason: 'the pairing sequence did not run out',
      );
      await Future.delayed(const Duration(milliseconds: 100));
      final lookups = (await peelAll(
        node,
        relays,
      )).where((s) => s.isLookup).toList();
      final yesterday = lookups
          .where((s) => s.lookupKeyHex == keys[1])
          .toList();
      expect(yesterday, hasLength(1), reason: 'yesterday\'s key only once');
      expect(lookups.first.lookupKeyHex, keys[0]);
      expect(
        yesterday.single.exitNodeIdHex,
        isNot(lookups.first.exitNodeIdHex),
        reason: 'no node may execute both keys of the round',
      );
      // initial + 3 pairing rounds of today's key (a read-before-write of the
      // timed-out hold's publish adds none: it is the same initial lookup).
      expect(
        lookups.where((s) => s.lookupKeyHex == keys[0]).length,
        greaterThanOrEqualTo(4),
      );
    });
  });

  group('T160 creator', () {
    test('the creator\'s first publish at creation is immediate, without a '
        'lookup', () async {
      final (client, node, relays) = await connectedClient();
      addTearDown(client.disconnect);
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: true,
      );
      await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isStore),
        timeout: const Duration(seconds: 2),
        reason: 'the creator\'s publish was held',
      );
      await Future.delayed(const Duration(milliseconds: 200));
      final sent = await peelAll(node, relays);
      expect(sent.where((s) => s.isLookup), isEmpty);
      expect(client.pairingLookupsActive(chan), isFalse);
    });

    test('Q2: the creation exemption is used up by a FAILED first attempt '
        '— the retry reads first', () async {
      var hopsAllowed = false;
      final (client, node, relays) = await connectedClient(
        hopFilter: (_) => hopsAllowed,
      );
      addTearDown(client.disconnect);
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: true,
      );
      // First publish at creation: no hops, nothing can go out.
      await client.registerOutboundHandle(channelId: chan);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(await peelAll(node, relays), isEmpty);

      // Later (the joiner may have written meanwhile) hops are there; the
      // next publish must read first.
      hopsAllowed = true;
      await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async => (await peelAll(node, relays)).isNotEmpty,
        reason: 'nothing went out once hops existed',
      );
      final first = (await peelAll(node, relays)).first;
      expect(
        first.isLookup,
        isTrue,
        reason: 'a retry of the creator\'s first publish must not be blind',
      );
    });

    test(
      'P2: a creator coming back (restart, offline at the scan) reads '
      'before it writes, keeps the joiner in the record and adopts him',
      () async {
        final (client, node, relays) = await connectedClient();
        addTearDown(client.disconnect);
        final keys = await recordKeysHex();
        final learned = <CounterpartOhUpdate>[];
        final sub = client.stateUpdates.of<CounterpartOhUpdate>().listen(
          learned.add,
        );
        addTearDown(sub.cancel);
        client.addChannelKeys(
          chan,
          channelKey,
          channelSecret: channelSecret,
          isChannelCreator: true,
        );
        // The mailbox comes back from storage — no fresh registration, so the
        // creation exemption does not apply; the poll cycle's sweep publishes.
        final ownOh = await restoredOwnOh(client);

        await pumpUntil(
          () async => (await peelAll(node, relays)).any((s) => s.isLookup),
          reason: 'the returning creator did not read first',
        );
        var sent = await peelAll(node, relays);
        expect(sent.where((s) => s.isStore), isEmpty);
        final today = sent.firstWhere(
          (s) => s.isLookup && s.lookupKeyHex == keys[0],
        );
        // The DHT holds the joiner's lone record (his hold timed out, the
        // creator's entry is gone).
        final bobOh = joinerOh(1);
        await deliver(
          client,
          node,
          ownOh,
          answerItem(
            today.lookupAckTag,
            await recordAnswer([bobOh], creator: false),
          ),
        );
        await pumpUntil(
          () async => (await peelAll(node, relays)).any((s) => s.isStore),
          reason: 'no publish after the read',
        );
        sent = await peelAll(node, relays);
        expect(await sent.firstWhere((s) => s.isStore).storedParticipants(), {
          participantHex(creator: true),
          participantHex(creator: false),
        });
        await pumpUntil(() => learned.isNotEmpty, reason: 'no adoption');
        expect(client.counterpartOhIds(chan), [bobOh.handleId]);
        // ... and announces itself to the joiner in-band.
        await pumpUntil(
          () async => (await peelAll(node, relays)).any((s) => s.isDeposit),
          reason: 'no announce to the joiner',
        );
        final deposit = (await peelGarlicDeposit(
          await firstDepositPacket(node, relays),
          relays,
        ))!;
        expect(sameBytes(deposit.ohId, bobOh.handleId), isTrue);
      },
    );

    test('P4: a creator that learned the joiner in-band, whose one-shot '
        'lookup was throttled, still reads before its next publish', () async {
      final (client, node, relays) = await connectedClient();
      addTearDown(client.disconnect);
      final keys = await recordKeysHex();
      client.addChannelKeys(
        chan,
        channelKey,
        channelSecret: channelSecret,
        isChannelCreator: true,
      );
      final ownOh = await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isStore),
      );
      // A send before anyone joined fails and stamps the recovery throttle.
      await expectLater(
        client.sendMessage(chan, 'too early'),
        throwsA(anything),
      );
      // Recovery asks today's key and, on its own route a moment later,
      // yesterday's.
      await pumpUntil(
        () async =>
            (await peelAll(node, relays)).where((s) => s.isLookup).length >= 2,
      );
      await Future.delayed(const Duration(milliseconds: 100));
      final lookupsBefore = (await peelAll(
        node,
        relays,
      )).where((s) => s.isLookup).length;

      // The joiner's in-band announce arrives; the one-shot read is
      // throttled away.
      final bobOh = joinerOh(2);
      final joinerSession = await RatchetSession.create(
        channelKey: channelKey,
        isChannelCreator: false,
      );
      final announce = await joinerSession.encrypt(
        ChannelMessage(
          messageId: Uint8List.fromList(List.generate(16, (i) => i)),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          content: '',
          ohUpdate: Uint8List.fromList(
            utf8.encode(jsonEncode([bobOh.toJsonMap()])),
          ),
        ),
        chan,
      );
      await deliver(
        client,
        node,
        ownOh,
        MailItem(
          payload: announce,
          receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await pumpUntil(() => client.counterpartOhIds(chan).isNotEmpty);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(
        (await peelAll(node, relays)).where((s) => s.isLookup).length,
        lookupsBefore,
        reason: 'precondition: the one-shot read was throttled',
      );

      // Its next publish (another own mailbox) reads first and carries Bob.
      final storesBefore = (await peelAll(
        node,
        relays,
      )).where((s) => s.isStore).length;
      await client.registerOutboundHandle(channelId: chan);
      await pumpUntil(
        () async =>
            (await peelAll(node, relays)).where((s) => s.isLookup).length >
            lookupsBefore,
        reason: 'the publish did not read first',
      );
      var sent = await peelAll(node, relays);
      expect(sent.where((s) => s.isStore).length, storesBefore);
      final read = sent.lastWhere(
        (s) => s.isLookup && s.lookupKeyHex == keys[0],
      );
      await deliver(
        client,
        node,
        ownOh,
        answerItem(
          read.lookupAckTag,
          await recordAnswer([bobOh], creator: false),
        ),
      );
      await pumpUntil(
        () async =>
            (await peelAll(node, relays)).where((s) => s.isStore).length >
            storesBefore,
      );
      sent = await peelAll(node, relays);
      expect(await sent.lastWhere((s) => s.isStore).storedParticipants(), {
        participantHex(creator: true),
        participantHex(creator: false),
      });
    });
  });

  group('T161 the pending announce', () {
    test('kept while no counterpart mailbox is known, sent once an in-band '
        'oh_update brings one', () async {
      final (client, node, relays) = await connectedClient();
      addTearDown(client.disconnect);
      // No channel secret: rendezvous stays dormant, only the in-band path
      // is exercised.
      client.addChannelKeys(chan, channelKey, isChannelCreator: false);
      final ownOh = await restoredOwnOh(client);

      client.queueOwnOhAnnounceForTesting(chan);
      await client.flushPendingOhAnnounceForTesting(chan);
      expect(
        client.hasPendingOhAnnounce(chan),
        isTrue,
        reason: 'the announce must wait for a target, not be dropped',
      );
      expect((await peelAll(node, relays)).where((s) => s.isDeposit), isEmpty);

      final creatorSession = await RatchetSession.create(
        channelKey: channelKey,
        isChannelCreator: true,
      );
      final aliceOh = creatorOh(4);
      final announce = await creatorSession.encrypt(
        ChannelMessage(
          messageId: Uint8List.fromList(List.generate(16, (i) => i)),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          content: '',
          ohUpdate: Uint8List.fromList(
            utf8.encode(jsonEncode([aliceOh.toJsonMap()])),
          ),
        ),
        chan,
      );
      await deliver(
        client,
        node,
        ownOh,
        MailItem(
          payload: announce,
          receivedAtMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isDeposit),
        reason: 'the pending announce was not sent after the adoption',
      );
      final deposit = (await peelGarlicDeposit(
        await firstDepositPacket(node, relays),
        relays,
      ))!;
      expect(sameBytes(deposit.ohId, aliceOh.handleId), isTrue);
      final message = await creatorSession.decrypt(deposit.payload, chan);
      expect(message.isOhUpdate, isTrue);
    });

    test('concurrent triggers send once; a newer announce queued meanwhile '
        'survives the older one running out of budget', () async {
      final (client, node, relays) = await connectedClient();
      addTearDown(client.disconnect);
      client.addChannelKeys(
        chan,
        channelKey,
        counterpartOhSet: [creatorOh(5)],
        isChannelCreator: false,
      );
      await restoredOwnOh(client);

      client.queueOwnOhAnnounceForTesting(chan);
      await Future.wait([
        client.flushPendingOhAnnounceForTesting(chan),
        client.flushPendingOhAnnounceForTesting(chan),
        client.flushPendingOhAnnounceForTesting(chan),
      ]);
      expect(
        client.pendingOhAnnounceSendsLeftForTesting(chan),
        2,
        reason: 'three simultaneous triggers spend ONE send of the budget',
      );
      await pumpUntil(
        () async => (await peelAll(node, relays)).any((s) => s.isDeposit),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      expect(
        (await peelAll(node, relays)).where((s) => s.isDeposit),
        hasLength(1),
      );

      // Use up the old announce's budget down to its last send ...
      await client.flushPendingOhAnnounceForTesting(chan);
      expect(client.pendingOhAnnounceSendsLeftForTesting(chan), 1);
      // ... and queue a newer one while that last send is in flight.
      final last = client.flushPendingOhAnnounceForTesting(chan);
      client.queueOwnOhAnnounceForTesting(chan);
      final again = client.flushPendingOhAnnounceForTesting(chan);
      await Future.wait([last, again]);
      expect(
        client.hasPendingOhAnnounce(chan),
        isTrue,
        reason: 'the newer announce must not be removed with the old one',
      );
      expect(
        client.pendingOhAnnounceSendsLeftForTesting(chan),
        2,
        reason: 'the newer announce was sent once after the old one',
      );
    });
  });
}
