import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';
import '../helpers/wait_for.dart';

/// T110 — ordering invariants of the single persistence channel.
///
/// Before T110 the sync service held four separate future chains (ratchet,
/// garlic, node scores, group state) plus fire-and-forget writes for mailbox,
/// own-OH, counterpart-OH and ACK updates. The chains are now ONE, which must
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
    super.outbox,
    this.order,
  );

  /// Write-order log, one entry per handler entry/exit.
  final List<String> order;

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
  Future<void> handleMailboxUpdate(OhMailboxUpdate update) async {
    order.add('mailbox:start');
    await super.handleMailboxUpdate(update);
    order.add('mailbox:done');
  }
}

/// T112: the Channel-ACK write lives in the outbox now, so the write-order
/// log has to be shared between the two — the invariant under test is that
/// the persistence chain applies them in emission order, no matter which
/// class owns the individual write.
class _RecordingOutbox extends OutboxService {
  _RecordingOutbox(super.messages, super.client, super.groups, this.order);

  final List<String> order;

  @override
  Future<void> onChannelAck(ChannelAckUpdate update) async {
    order.add('channelAck:start');
    await super.onChannelAck(update);
    order.add('channelAck:done');
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
    final order = <String>[];
    service = _RecordingSyncService(
      client,
      messages,
      OutboundHandleRepository(db),
      db,
      GroupRepository(db),
      _RecordingOutbox(messages, client, GroupRepository(db), order),
      order,
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
            conversationId: uuid,
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

  /// Waits until the write-order log holds [entries] entries, i.e. until the
  /// last write the test emitted has finished: every handler logs its exit
  /// only after its write committed, and the chain is serial.
  ///
  /// Was `settle()` — "the log stayed unchanged for 150 ms". A scheduling
  /// stall of that length between two chained writes looked exactly like a
  /// finished chain, so under full-suite load I1 asserted before the third
  /// `ratchet:done` and went red (TD121). Waiting for the concrete count has
  /// no such window; the timeout is only the failure deadline. The exact
  /// order assertions that follow still catch any surplus entry.
  Future<void> waitForLog(int entries) => waitFor(
    () => service.order.length >= entries,
    timeout: const Duration(seconds: 10),
    description: '$entries write-order entries',
  );

  test('I1: same-kind writes land in emission order, newest wins', () async {
    await insertChannel('channel-1');
    service.start();

    for (var i = 1; i <= 3; i++) {
      client.stateController.add(
        RatchetStateUpdate(channelId: 'channel-1', stateJson: 'state-$i'),
      );
    }
    await waitForLog(6);

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
    await waitForLog(4);

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
    await waitForLog(4);

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
    await waitForLog(2);

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
    // No wait: stop() is called while the slow write is still running.
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
    // Asserting that NOTHING happens: a fixed window is the right tool here
    // (a slow host only weakens the check, it cannot turn it red).
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(service.order, isEmpty);
  });
}
