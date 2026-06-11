import 'package:flutter_test/flutter_test.dart';
import 'package:redpanda/database/database.dart' hide Channel;
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late DriftChannelRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = DriftChannelRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DriftChannelRepository', () {
    test('addChannel and getChannels round-trip a plain channel', () async {
      final channel = Channel.generate('My Channel');

      await repo.addChannel(channel);
      final channels = await repo.getChannels();

      expect(channels, hasLength(1));
      expect(channels.single.label, equals('My Channel'));
      expect(channels.single.encryptionKey, equals(channel.encryptionKey));
      expect(channels.single.peerOhDescriptor, isNull);
    });

    test('round-trips the peer OH descriptor', () async {
      final descriptor = OHDescriptor(
        serverEndpoint: 'node-1:59558',
        handleId: List.generate(20, (i) => i),
        authPublicKey: List.generate(65, (i) => i),
      );
      final channel = Channel.generate(
        'With OH',
      ).copyWith(peerOhDescriptor: descriptor);

      await repo.addChannel(channel);
      final restored = (await repo.getChannels()).single;

      expect(restored.peerOhDescriptor, isNotNull);
      expect(restored.peerOhDescriptor!.serverEndpoint, equals('node-1:59558'));
      expect(restored.peerOhDescriptor!.handleId, equals(descriptor.handleId));
      expect(
        restored.peerOhDescriptor!.authPublicKey,
        equals(descriptor.authPublicKey),
      );
    });

    test('addChannel upserts on the same channel id', () async {
      final channel = Channel.generate('Original');
      await repo.addChannel(channel);
      await repo.addChannel(channel);

      expect(await repo.getChannels(), hasLength(1));
    });

    test('watchChannels emits the current channel list', () async {
      await repo.addChannel(Channel.generate('Streamed'));

      final channels = await repo.watchChannels().first;
      expect(channels, hasLength(1));
      expect(channels.single.label, equals('Streamed'));
    });
  });
}
