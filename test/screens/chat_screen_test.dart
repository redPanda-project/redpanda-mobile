import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/screens/chat/chat_screen.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart' hide Channel;

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late FakeRedPandaClient client;

  const channelUuid = 'channel-1';
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
            uuid: channelUuid,
            label: 'Test Channel',
            encryptionKey: HEX.encode(List.generate(32, (i) => i)),
            authenticationKey: HEX.encode(List.generate(32, (i) => i + 1)),
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
            conversationId: channelUuid,
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
      child: const MaterialApp(home: ChatScreen(peerUuid: channelUuid)),
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

  group('ChatScreen message status icons (MS02)', () {
    testWidgets('pending message shows a clock icon', (tester) async {
      await insertMessage('pending msg', MessageStatus.pending);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text('pending msg'), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('sent message shows a checkmark icon', (tester) async {
      await insertMessage('sent msg', MessageStatus.sent);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byIcon(Icons.check), findsOneWidget);

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

    testWidgets('received messages from the peer show no status icon', (
      tester,
    ) async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: channelUuid,
              senderId: channelUuid, // sent by the peer
              content: 'their msg',
              timestamp: DateTime.now(),
              status: MessageStatus.received,
              type: 0,
            ),
          );

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text('their msg'), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);

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
      client.updateController.add(
        OhMailboxUpdate(
          ohId: List.generate(20, (i) => i),
          channelId: channelUuid,
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
      client.updateController.add(
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
}
