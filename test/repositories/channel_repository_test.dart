import 'package:drift/drift.dart' as drift;
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
      final channel = await Channel.generate('My Channel');

      await repo.addChannel(channel);
      final channels = await repo.getChannels();

      expect(channels, hasLength(1));
      expect(channels.single.label, equals('My Channel'));
      expect(channels.single.encryptionKey, equals(channel.encryptionKey));
      expect(channels.single.counterpartOhDescriptor, isNull);
    });

    test('round-trips the counterpart OH descriptor', () async {
      final descriptor = OHDescriptor(
        serverEndpoint: 'node-1:59558',
        handleId: List.generate(20, (i) => i),
        authPublicKey: List.generate(32, (i) => i),
      );
      final channel = (await Channel.generate(
        'With OH',
      )).copyWith(counterpartOhDescriptor: descriptor);

      await repo.addChannel(channel);
      final restored = (await repo.getChannels()).single;

      expect(restored.counterpartOhDescriptor, isNotNull);
      expect(
        restored.counterpartOhDescriptor!.serverEndpoint,
        equals('node-1:59558'),
      );
      expect(
        restored.counterpartOhDescriptor!.handleId,
        equals(descriptor.handleId),
      );
      expect(
        restored.counterpartOhDescriptor!.authPublicKey,
        equals(descriptor.authPublicKey),
      );
    });

    test('addChannel upserts on the same channel id', () async {
      final channel = await Channel.generate('Original');
      expect(await repo.addChannel(channel), isTrue);
      expect(await repo.addChannel(channel), isFalse);

      expect(await repo.getChannels(), hasLength(1));
    });

    // H8: re-scanning a QR code for an already-joined channel must not reset
    // the on-device state the Channel value object does not carry.
    group('re-adding an existing channel', () {
      /// Simulates a live channel: ratchet state, a pending reverse-garlic
      /// block and a discovered counterpart mailbox set on top of the stored row.
      Future<void> markAsLive(String channelId) async {
        await (db.update(
          db.channels,
        )..where((t) => t.uuid.equals(channelId))).write(
          const ChannelsCompanion(
            ratchetState: drift.Value('{"rootKey":"deadbeef"}'),
            pendingRgb: drift.Value('cafe'),
            counterpartOhSet: drift.Value('[{"ep":"node-1:59558"}]'),
            counterpartOhEndpoint: drift.Value('node-1:59558'),
            counterpartOhId: drift.Value('aa'),
            counterpartOhPublicKey: drift.Value('bb'),
          ),
        );
      }

      test(
        'preserves ratchet state, pending RGB and counterpart OH set',
        () async {
          final created = await Channel.generate('Live');
          await repo.addChannel(created);
          await markAsLive(created.id);

          // Exactly what the scanner produces from the channel's own QR code.
          final rescanned = await Channel.fromJson(created.toJson());
          expect(rescanned.id, equals(created.id));
          expect(await repo.addChannel(rescanned), isFalse);

          final row = await (db.select(
            db.channels,
          )..where((t) => t.uuid.equals(created.id))).getSingle();
          expect(row.ratchetState, equals('{"rootKey":"deadbeef"}'));
          expect(row.pendingRgb, equals('cafe'));
          expect(row.counterpartOhSet, equals('[{"ep":"node-1:59558"}]'));
          expect(row.counterpartOhEndpoint, equals('node-1:59558'));
          expect(row.counterpartOhId, equals('aa'));
          expect(row.counterpartOhPublicKey, equals('bb'));
          expect(await repo.getChannels(), hasLength(1));
        },
      );

      test('preserves the creator role marker', () async {
        final created = await Channel.generate('Mine');
        await repo.addChannel(created);
        expect(created.isCreator, isTrue);

        // Scanning our own QR yields a joiner-shaped Channel (no private key).
        final rescanned = await Channel.fromJson(created.toJson());
        expect(rescanned.isCreator, isFalse);
        await repo.addChannel(rescanned);

        expect((await repo.getChannels()).single.isCreator, isTrue);
      });

      test(
        'adopts a counterpart OH descriptor learned after the first add',
        () async {
          final created = await Channel.generate('Late OH');
          await repo.addChannel(created);

          final descriptor = OHDescriptor(
            serverEndpoint: 'node-2:59558',
            handleId: List.generate(20, (i) => i),
            authPublicKey: List.generate(32, (i) => i),
          );
          final rescanned = (await Channel.fromJson(
            created.toJson(),
          )).copyWith(counterpartOhDescriptor: descriptor);
          expect(await repo.addChannel(rescanned), isFalse);

          final restored = (await repo.getChannels()).single;
          expect(
            restored.counterpartOhDescriptor!.serverEndpoint,
            'node-2:59558',
          );
          expect(
            restored.counterpartOhDescriptor!.handleId,
            descriptor.handleId,
          );
        },
      );

      test('a fresh channel is still inserted alongside', () async {
        await repo.addChannel(await Channel.generate('First'));
        expect(await repo.addChannel(await Channel.generate('Second')), isTrue);

        expect(await repo.getChannels(), hasLength(2));
      });
    });

    test('watchChannels emits the current channel list', () async {
      await repo.addChannel(await Channel.generate('Streamed'));

      final channels = await repo.watchChannels().first;
      expect(channels, hasLength(1));
      expect(channels.single.label, equals('Streamed'));
    });
  });
}
