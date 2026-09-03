import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/message_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/services/outbox_service.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/fake_redpanda_client.dart';
import '../helpers/test_database.dart';

void main() {
  group('provider graph', () {
    late ProviderContainer container;
    late FakeRedPandaClient client;

    setUp(() {
      client = FakeRedPandaClient();
      container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(createTestDatabase()),
          redPandaClientProvider.overrideWithValue(client),
        ],
      );
    });

    tearDown(() async {
      final db = container.read(dbProvider);
      container.dispose();
      await client.disconnect();
      await db.close();
    });

    test('MS02 service providers build against the client and database', () {
      expect(
        container.read(messageRepositoryProvider),
        isA<MessageRepository>(),
      );
      expect(
        container.read(outboundHandleRepositoryProvider),
        isA<OutboundHandleRepository>(),
      );
      expect(container.read(outboxServiceProvider), isA<OutboxService>());
      expect(
        container.read(messageSyncServiceProvider),
        isA<MessageSyncService>(),
      );
      expect(
        container.read(channelRepositoryProvider),
        isA<ChannelRepository>(),
      );
    });

    test('stream providers expose client streams', () async {
      // Keep the stream providers alive while awaiting their first value.
      final subs = [
        container.listen(connectionStatusProvider, (_, _) {}),
        container.listen(peerCountProvider, (_, _) {}),
        container.listen(pendingMessageCountProvider, (_, _) {}),
        container.listen(peerStatsSnapshotProvider, (_, _) {}),
        container.listen(activePeersProvider, (_, _) {}),
        container.listen(connectingPeersProvider, (_, _) {}),
        container.listen(incomingMessagesProvider, (_, _) {}),
        container.listen(mailboxOverflowProvider, (_, _) {}),
        container.listen(channelsProvider, (_, _) {}),
      ];

      expect(
        await container.read(connectionStatusProvider.future),
        equals(ConnectionStatus.connected),
      );
      expect(await container.read(peerCountProvider.future), equals(1));
      expect(
        await container.read(pendingMessageCountProvider.future),
        equals(0),
      );
      expect(await container.read(channelsProvider.future), isEmpty);

      for (final sub in subs) {
        sub.close();
      }
    });
  });
}
