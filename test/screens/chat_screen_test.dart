import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/group_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/screens/chat/chat_screen.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

/// Records what the chat screen hands to the outbox and swallows the send,
/// so the test can tell "the screen enqueued" from "the screen sent" (T112).
class _RecordingOutbox extends OutboxService {
  _RecordingOutbox(super.messages, super.client, super.groups);

  final List<({String conversationId, String senderId, String content})>
  enqueued = [];

  @override
  Future<int> enqueue({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    enqueued.add((
      conversationId: conversationId,
      senderId: senderId,
      content: content,
    ));
    return enqueued.length;
  }
}

void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;

  const conversationUuid = 'channel-1';
  const myUuid = 'me-uuid';

  setUp(() async {
    db = createTestDatabase();
    client = FakeRedPandaClient();

    await db
        .into(db.users)
        .insert(UsersCompanion.insert(uuid: myUuid, username: 'Me'));
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            conversationId: conversationUuid,
            label: 'Test Channel',
            encryptionKey: HEX.encode(List.generate(32, (i) => i)),
            authPublicKey: HEX.encode(List.generate(32, (i) => i + 1)),
          ),
        );
  });

  tearDown(() async {
    await client.disconnect();
    await db.close();
  });

  Future<void> insertMessage(String content, int status) async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            conversationId: conversationUuid,
            senderId: myUuid,
            content: content,
            timestamp: DateTime.now(),
            status: status,
            type: 0,
          ),
        );
  }

  Widget app() {
    return ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        redPandaClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(
        home: ChatScreen(conversationId: conversationUuid),
      ),
    );
  }

  // Disposes the widget tree and flushes drift's stream-close timer
  // (StreamQueryStore.markAsClosed schedules a zero-duration timer on
  // dispose, which would otherwise trip the pending-timer check).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Advance the fake clock so the zero-duration close timer fires.
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('ChatScreen message status icons (MS06 lifecycle)', () {
    testWidgets('pending message shows a clock icon', (tester) async {
      await insertMessage('pending msg', MessageStatus.pending);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text('pending msg'), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('sent message shows an upward arrow icon', (tester) async {
      await insertMessage('sent msg', MessageStatus.sent);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('routed message (R-ACK) shows a single checkmark', (
      tester,
    ) async {
      await insertMessage('routed msg', MessageStatus.routed);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byIcon(Icons.check), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('delivered message (Channel-ACK) shows a blue double check', (
      tester,
    ) async {
      await insertMessage('delivered msg', MessageStatus.delivered);

      await tester.pumpWidget(app());
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(Icons.done_all));
      expect(icon.color, equals(Colors.blue));

      await unmount(tester);
    });

    testWidgets('failed message shows a red X icon', (tester) async {
      await insertMessage('failed msg', MessageStatus.failed);

      await tester.pumpWidget(app());
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.color, equals(Colors.red));

      await unmount(tester);
    });

    testWidgets('received messages from the counterpart show no status icon', (
      tester,
    ) async {
      // Through the real incoming path, so the direction the repository
      // stamps is the one the screen reads.
      await MessageRepository(db).insertIncomingIfNew(
        messageId: 'aa' * 8,
        conversationId: conversationUuid,
        senderId: conversationUuid, // sent by the counterpart
        content: 'their msg',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text('their msg'), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(_alignmentOf(tester, 'their msg'), equals(Alignment.centerLeft));

      await unmount(tester);
    });

    // T114: direction is a stored fact now, not `senderId != conversationId`.
    // This row is exactly the case the old 1:1 heuristic got wrong — an
    // incoming message whose sender is NOT the conversation id (which is what
    // every group message looks like) — and it must still render as theirs.
    testWidgets('the stored direction decides the side, not the sender id', (
      tester,
    ) async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: conversationUuid,
              senderId: 'ee' * 32, // a member id, not the conversation id
              content: 'from a member',
              timestamp: DateTime.now(),
              status: MessageStatus.received,
              type: 0,
              direction: const Value(MessageDirection.incoming),
            ),
          );
      // …and the mirror image: an outgoing row whose sender id happens to be
      // the conversation id would have rendered as theirs before.
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: conversationUuid,
              senderId: conversationUuid,
              content: 'still mine',
              timestamp: DateTime.now(),
              status: MessageStatus.sent,
              type: 0,
              direction: const Value(MessageDirection.outgoing),
            ),
          );

      await tester.pumpWidget(app());
      await tester.pump();

      expect(
        _alignmentOf(tester, 'from a member'),
        equals(Alignment.centerLeft),
      );
      expect(_alignmentOf(tester, 'still mine'), equals(Alignment.centerRight));

      await unmount(tester);
    });
  });

  group('ChatScreen mailbox overflow warning (MS02)', () {
    testWidgets('shows a snackbar when this channel overflows', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      // Route an overflow event through the sync service to the UI provider.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      container.read(messageSyncServiceProvider).start();
      client.stateController.add(
        OhMailboxUpdate(
          ohId: List.generate(20, (i) => i),
          channelId: conversationUuid,
          lastCursor: 1,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch,
          mailboxOverflow: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Some older messages may have been lost (mailbox full).'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('ignores overflow events for other channels', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      container.read(messageSyncServiceProvider).start();
      client.stateController.add(
        OhMailboxUpdate(
          ohId: List.generate(20, (i) => i),
          channelId: 'some-other-channel',
          lastCursor: 1,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch,
          mailboxOverflow: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);

      await unmount(tester);
    });
  });

  group('ChatScreen sending (MS02)', () {
    testWidgets('sending inserts a pending message and marks it sent', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Hello!');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump();

      expect(client.sentMessages, hasLength(1));
      expect(client.sentMessages.single.content, equals('Hello!'));

      final row = await db.select(db.messages).getSingle();
      expect(row.status, equals(MessageStatus.sent));

      await unmount(tester);
    });

    testWidgets('failed send stays pending with a retry attempt recorded', (
      tester,
    ) async {
      client.sendError = StateError('no active peer');

      await tester.pumpWidget(app());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Will retry');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump();

      final row = await db.select(db.messages).getSingle();
      expect(row.status, equals(MessageStatus.pending));
      expect(row.retryCount, equals(1));
      expect(row.lastRetryAt, isNotNull);

      await unmount(tester);
    });
  });

  group('ChatScreen deposit rejections (MS02b)', () {
    testWidgets('QUOTA_EXCEEDED keeps pending and warns the user', (
      tester,
    ) async {
      client.sendError = DepositException(DepositStatus.quotaExceeded);

      await tester.pumpWidget(app());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Mailbox full');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump();

      final row = await db.select(db.messages).getSingle();
      expect(row.status, equals(MessageStatus.pending));
      expect(
        find.text("Recipient's mailbox is full — will retry later."),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('BAD_REQUEST marks the message failed and warns the user', (
      tester,
    ) async {
      client.sendError = DepositException(DepositStatus.badRequest);

      await tester.pumpWidget(app());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Too large');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump();

      final row = await db.select(db.messages).getSingle();
      expect(row.status, equals(MessageStatus.failed));
      expect(find.text('Message too large to deliver.'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('T112: the composer only enqueues', () {
    testWidgets('send hands the message to the outbox, it does not send', (
      tester,
    ) async {
      final outbox = _RecordingOutbox(
        MessageRepository(db),
        client,
        GroupRepository(db),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbProvider.overrideWithValue(db),
            redPandaClientProvider.overrideWithValue(client),
            outboxServiceProvider.overrideWithValue(outbox),
          ],
          child: const MaterialApp(
            home: ChatScreen(conversationId: conversationUuid),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'enqueue me');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump();

      expect(outbox.enqueued, hasLength(1));
      expect(outbox.enqueued.single.conversationId, equals(conversationUuid));
      expect(outbox.enqueued.single.senderId, equals(myUuid));
      expect(outbox.enqueued.single.content, equals('enqueue me'));
      expect(
        client.sentMessages,
        isEmpty,
        reason:
            'the send attempt (and its retry/backoff policy) belongs to the '
            'outbox — the screen used to run a second implementation of it',
      );

      await unmount(tester);
    });

    testWidgets('a failure in ANOTHER conversation shows no snackbar here', (
      tester,
    ) async {
      // The attempt stream carries every conversation's attempts; the screen
      // must filter to its own.
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              conversationId: 'other-channel',
              label: 'Other',
              encryptionKey: HEX.encode(List.generate(32, (i) => i)),
              authPublicKey: HEX.encode(List.generate(32, (i) => i + 1)),
            ),
          );
      client.sendError = DepositException(DepositStatus.quotaExceeded);

      await tester.pumpWidget(app());
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await container
          .read(outboxServiceProvider)
          .enqueue(
            conversationId: 'other-channel',
            senderId: myUuid,
            content: 'not mine',
          );
      await container.read(outboxServiceProvider).settled;
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);

      await unmount(tester);
    });

    testWidgets('a failed RETRY of an older message shows no snackbar', (
      tester,
    ) async {
      // Only the attempt the user just triggered is reported; the queue's
      // later attempts stay silent, exactly as when the composer did its own
      // send and the retry queue was mute.
      client.sendError = DepositException(DepositStatus.quotaExceeded);
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: conversationUuid,
              senderId: myUuid,
              content: 'older pending',
              timestamp: DateTime.now(),
              status: MessageStatus.pending,
              type: 0,
              retryCount: const Value(1),
            ),
          );

      await tester.pumpWidget(app());
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await container.read(outboxServiceProvider).runPass(ignoreBackoff: true);
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);

      await unmount(tester);
    });
  });

  group('T111: the chat screen does no network orchestration', () {
    testWidgets('build() registers no channel state and no OH top-up', (
      tester,
    ) async {
      await insertMessage('hello', MessageStatus.delivered);

      await tester.pumpWidget(app());
      await tester.pump();
      // A rebuild used to mean another partial re-registration.
      await tester.pump();

      expect(
        client.channelRegistrations,
        isEmpty,
        reason:
            'channel state has ONE restore entry point '
            '(MessageSyncService.registerChannel) — not build()',
      );
      expect(
        client.ohRedundancyCalls,
        isEmpty,
        reason: 'the worker owns its own mailbox redundancy (T42/T111)',
      );

      await unmount(tester);
    });

    testWidgets('sending a message still works without a registration', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'no registration needed');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump();

      expect(client.sentMessages.single.content, 'no registration needed');
      expect(client.channelRegistrations, isEmpty);

      await unmount(tester);
    });
  });
}

/// The side a message bubble is rendered on: the nearest [Align] above the
/// message text.
Alignment _alignmentOf(WidgetTester tester, String text) {
  final align = tester.widget<Align>(
    find.ancestor(of: find.text(text), matching: find.byType(Align)).first,
  );
  return align.alignment as Alignment;
}
