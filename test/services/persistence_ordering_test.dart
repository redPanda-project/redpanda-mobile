import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

/// T110 — ordering invariants of the single persistence channel.
///
/// Before T110 the sync service held four separate future chains (ratchet,
/// garlic, node scores, group state) plus fire-and-forget writes for mailbox,
/// own-OH, peer-OH and ACK updates. The chains are now ONE, which must
/// guarantee at least what they guaranteed before:
///
/// * **I1** same-kind writes are applied in emission order (a slow earlier
///   write must never overwrite a newer state);
/// * **I2** a failing write neither breaks the chain nor kills the
///   subscription — every following update is still persisted;
/// * **I3** cross-kind writes are applied in emission order too — in
///   particular a ratchet-state write emitted before a message ACK is
///   committed BEFORE the ACK is applied (this is new: the old code had no
///   ordering across kinds at all);
/// * **I4** the mailbox-overflow warning is re-broadcast only after the
///   cursor/expiry write.
class _RecordingSyncService extends MessageSyncService {
  _RecordingSyncService(
    super.client,
    super.messages,
    super.outboundHandles,
    super.db,
    super.groups,
  );

  /// Write-order log, one entry per handler entry/exit.
  final List<String> order = [];

  /// When set, [handleRatchetStateUpdate] throws instead of writing.
  bool failRatchetWrite = false;

  @override
  Future<void> handleRatchetStateUpdate(RatchetStateUpdate update) async {
    order.add('ratchet:start');
    // Simulate a slow DB write: anything queued behind must wait.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (failRatchetWrite) {
      order.add('ratchet:throw');
      throw StateError('ratchet write failed');
    }
    await super.handleRatchetStateUpdate(update);
    order.add('ratchet:done');
  }

  @override
  Future<void> handleChannelAckUpdate(ChannelAckUpdate update) async {
    order.add('channelAck:start');
    await super.handleChannelAckUpdate(update);
    order.add('channelAck:done');
  }

  @override
  Future<void> handleMailboxUpdate(OhMailboxUpdate update) async {
    order.add('mailbox:start');
    await super.handleMailboxUpdate(update);
    order.add('mailbox:done');
  }
}

void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;
  late _RecordingSyncService service;
  late MessageRepository messages;

  const ohIdHex = '0202020202020202020202020202020202020202';

  setUp(() {
    db = createTestDatabase();
    client = FakeRedPandaClient();
    messages = MessageRepository(db);
    service = _RecordingSyncService(
      client,
      messages,
      OutboundHandleRepository(db),
      db,
      GroupRepository(db),
    );
  });

  tearDown(() async {
    await service.dispose();
    await client.disconnect();
    await db.close();
  });

  Future<void> insertChannel(String uuid) async {
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            uuid: uuid,
            label: uuid,
            encryptionKey: 'aa' * 32,
            authPublicKey: 'bb' * 32,
          ),
        );
  }

  Future<void> insertHandle() async {
    await db
        .into(db.outboundHandles)
        .insert(
          OutboundHandlesCompanion.insert(
            ohId: ohIdHex,
            keypairBytes: (await OHKeypair.generate()).privateKeyBytes,
            serverEndpoint: 'localhost:59558',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
          ),
        );
  }

  /// Waits until the persistence chain has gone quiet: the write-order log
  /// must stay unchanged for [quiet] before we assert on it.
  ///
  /// Was a flat 200 ms sleep, which measured a serialized 3x30 ms handler
  /// chain plus real Drift writes and went red under full-suite load (T111
  /// added a channel-table watcher that does its own reads at start()).
  /// Waiting for the condition instead of guessing a duration keeps the
  /// invariant the same and the test honest — the cap is only a failure
  /// deadline, not the expected wait.
  Future<void> settle({
    Duration quiet = const Duration(milliseconds: 150),
    Duration cap = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(cap);
    var lastLength = -1;
    var stableSince = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (service.order.length != lastLength) {
        lastLength = service.order.length;
        stableSince = DateTime.now();
        continue;
      }
      if (DateTime.now().difference(stableSince) >= quiet) return;
    }
  }

  test('I1: same-kind writes land in emission order, newest wins', () async {
    await insertChannel('channel-1');
    service.start();

    for (var i = 1; i <= 3; i++) {
      client.stateController.add(
        RatchetStateUpdate(channelId: 'channel-1', stateJson: 'state-$i'),
      );
    }
    await settle();

    expect(
      service.order,
      equals([
        'ratchet:start',
        'ratchet:done',
        'ratchet:start',
        'ratchet:done',
        'ratchet:start',
        'ratchet:done',
      ]),
    );
    final channel = await db.select(db.channels).getSingle();
    expect(channel.ratchetState, equals('state-3'));
  });

  test('I2: a failing write neither breaks the chain nor the sub', () async {
    await insertChannel('channel-1');
    final messageRow = await messages.insertOutgoing(
      conversationId: 'channel-1',
      senderId: 'me',
      content: 'hi',
      messageId: 'ab12',
    );
    await messages.updateMessageStatus(messageRow, MessageStatus.sent);
    service.start();
    service.failRatchetWrite = true;

    client.stateController.add(
      const RatchetStateUpdate(channelId: 'channel-1', stateJson: 'boom'),
    );
    client.stateController.add(
      const ChannelAckUpdate(
        channelId: 'channel-1',
        messageIdHex: 'ab12',
        timestampMs: 1700000000000,
      ),
    );
    await settle();

    expect(service.order, contains('ratchet:throw'));
    expect(service.order, contains('channelAck:done'));
    final message = await db.select(db.messages).getSingle();
    expect(message.status, equals(MessageStatus.delivered));
    // The ratchet write threw, so nothing was persisted for it.
    final channel = await db.select(db.channels).getSingle();
    expect(channel.ratchetState, isNull);
  });

  test('I3: ratchet state is written BEFORE a later message ACK', () async {
    await insertChannel('channel-1');
    final messageRow = await messages.insertOutgoing(
      conversationId: 'channel-1',
      senderId: 'me',
      content: 'hi',
      messageId: 'cd34',
    );
    await messages.updateMessageStatus(messageRow, MessageStatus.sent);
    service.start();

    // The ratchet write is deliberately slow; the ACK is emitted right after.
    client.stateController.add(
      const RatchetStateUpdate(
        channelId: 'channel-1',
        stateJson: '{"advanced":true}',
      ),
    );
    client.stateController.add(
      const ChannelAckUpdate(
        channelId: 'channel-1',
        messageIdHex: 'cd34',
        timestampMs: 1700000000000,
      ),
    );
    await settle();

    expect(
      service.order,
      equals([
        'ratchet:start',
        'ratchet:done',
        'channelAck:start',
        'channelAck:done',
      ]),
    );
  });

  test('I4: overflow is re-broadcast after the cursor write', () async {
    await insertHandle();
    service.start();

    // Cursor value visible in the DB at the moment the overflow warning
    // reaches a UI listener. Read ON the event (not after a sleep), so the
    // assertion cannot pass by timing luck.
    final cursorWhenWarned = Completer<int>();
    final sub = service.overflowEvents.listen((_) {
      cursorWhenWarned.complete(
        db.select(db.outboundHandles).getSingle().then((r) => r.lastCursor),
      );
    });
    addTearDown(sub.cancel);

    client.stateController.add(
      OhMailboxUpdate(
        ohId: HEX.decode(ohIdHex),
        lastCursor: 12,
        expiresAtMs: DateTime.now()
            .add(const Duration(days: 3))
            .millisecondsSinceEpoch,
        mailboxOverflow: true,
      ),
    );
    // The warning is raised only after the cursor/expiry writes committed —
    // a UI listener never sees an overflow with a stale cursor.
    expect(
      await cursorWhenWarned.future.timeout(const Duration(seconds: 5)),
      equals(12),
    );
    await settle();

    final handle = await db.select(db.outboundHandles).getSingle();
    expect(handle.lastCursor, equals(12));
    expect(service.order, equals(['mailbox:start', 'mailbox:done']));
  });

  test('stop() drains the queued writes before returning', () async {
    // Callers close the database right after stop()/dispose(); a write still
    // in flight would then fail against a closed connection.
    await insertChannel('channel-1');
    service.start();

    client.stateController.add(
      const RatchetStateUpdate(channelId: 'channel-1', stateJson: 'slow'),
    );
    // No settle(): stop() is called while the slow write is still running.
    await service.stop();

    expect(service.order, equals(['ratchet:start', 'ratchet:done']));
    final channel = await db.select(db.channels).getSingle();
    expect(channel.ratchetState, equals('slow'));
  });

  test('updates the sync service does not own are ignored', () async {
    service.start();

    // Owned by channel_health (UI) and GroupService respectively — they must
    // not reach a persistence handler and must not break the chain.
    client.stateController.add(
      OhFetchStatus(
        ohId: HEX.decode(ohIdHex),
        success: true,
        atMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    client.stateController.add(
      GroupHandshakeEvent(
        channelId: 'channel-1',
        isProposal: true,
        groupIdHex: 'ff' * 32,
      ),
    );
    await settle();

    expect(service.order, isEmpty);
  });
}
