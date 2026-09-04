import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/counterpart_oh.dart';
import 'package:redpanda/database/database.dart';
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
        )..where((t) => t.conversationId.equals(channelId))).write(
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
          )..where((t) => t.conversationId.equals(created.id))).getSingle();
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

    // TD118: `counterpartOhSet` is the counterpart's full known mailbox set
    // and the single-target `counterpartOh*` columns mirror its FIRST entry
    // (see the column docs in database.dart). `addChannel` used to write
    // only the three primary columns and never the set, so the primary
    // could stop being the head of the set. Both writers now derive all
    // four columns in `counterpartOhColumns`.
    group('counterpart mailbox invariant (TD118)', () {
      OHDescriptor mailbox(String endpoint, int seed) => OHDescriptor(
        serverEndpoint: endpoint,
        handleId: List.generate(20, (i) => (i + seed) & 0xff),
        authPublicKey: List.generate(32, (i) => (i + seed) & 0xff),
      );

      Future<void> expectPrimaryIsHeadOfSet(String conversationId) async {
        final row = await (db.select(
          db.channels,
        )..where((t) => t.conversationId.equals(conversationId))).getSingle();
        final set = decodeCounterpartOhSet(row.counterpartOhSet);
        expect(set, isNotNull, reason: 'the set must be written too');
        expect(row.counterpartOhEndpoint, equals(set!.first.serverEndpoint));
        expect(row.counterpartOhId, equals(HEX.encode(set.first.handleId)));
        expect(
          row.counterpartOhPublicKey,
          equals(HEX.encode(set.first.authPublicKey)),
        );
      }

      test(
        'a fresh add stores the QR mailbox as the head of the set',
        () async {
          final descriptor = mailbox('node-1:59558', 1);
          final channel = (await Channel.generate(
            'With OH',
          )).copyWith(counterpartOhDescriptor: descriptor);

          await repo.addChannel(channel);

          await expectPrimaryIsHeadOfSet(channel.id);
          final row = await (db.select(
            db.channels,
          )..where((t) => t.conversationId.equals(channel.id))).getSingle();
          expect(decodeCounterpartOhSet(row.counterpartOhSet), hasLength(1));
        },
      );

      // Review finding (T124): rows written BEFORE the fix have the three
      // primary columns filled and `counterpartOhSet` still NULL — that was
      // exactly TD118. A re-scan must not throw the only mailbox such a row
      // ever knew away just because it never made it into a set.
      test(
        'a re-scan keeps the primary of a row that has no set yet',
        () async {
          final created = await Channel.generate('Pre-fix row');
          await repo.addChannel(created);

          final old = mailbox('node-1:59558', 1);
          await (db.update(
            db.channels,
          )..where((t) => t.conversationId.equals(created.id))).write(
            ChannelsCompanion(
              counterpartOhEndpoint: drift.Value(old.serverEndpoint),
              counterpartOhId: drift.Value(HEX.encode(old.handleId)),
              counterpartOhPublicKey: drift.Value(
                HEX.encode(old.authPublicKey),
              ),
            ),
          );

          final fresh = mailbox('node-2:59558', 2);
          final rescanned = (await Channel.fromJson(
            created.toJson(),
          )).copyWith(counterpartOhDescriptor: fresh);
          expect(await repo.addChannel(rescanned), isFalse);

          await expectPrimaryIsHeadOfSet(created.id);
          final row = await (db.select(
            db.channels,
          )..where((t) => t.conversationId.equals(created.id))).getSingle();
          expect(
            decodeCounterpartOhSet(
              row.counterpartOhSet,
            )!.map((d) => d.serverEndpoint),
            equals(['node-2:59558', 'node-1:59558']),
          );
        },
      );

      test(
        'a re-scan promotes the new mailbox and keeps the known ones',
        () async {
          final created = await Channel.generate('Multi OH');
          await repo.addChannel(created);

          // What an `oh_update` announce left behind: two known mailboxes,
          // the first mirrored into the primary columns.
          final known = [
            mailbox('node-1:59558', 1),
            mailbox('node-2:59558', 2),
          ];
          await (db.update(
            db.channels,
          )..where((t) => t.conversationId.equals(created.id))).write(
            ChannelsCompanion(
              counterpartOhEndpoint: drift.Value(known.first.serverEndpoint),
              counterpartOhId: drift.Value(HEX.encode(known.first.handleId)),
              counterpartOhPublicKey: drift.Value(
                HEX.encode(known.first.authPublicKey),
              ),
              counterpartOhSet: drift.Value(
                jsonEncode([for (final d in known) d.toJsonMap()]),
              ),
            ),
          );

          // A QR code naming the second mailbox: it becomes the primary ...
          final rescanned = (await Channel.fromJson(
            created.toJson(),
          )).copyWith(counterpartOhDescriptor: known[1]);
          expect(await repo.addChannel(rescanned), isFalse);

          await expectPrimaryIsHeadOfSet(created.id);
          final row = await (db.select(
            db.channels,
          )..where((t) => t.conversationId.equals(created.id))).getSingle();
          final set = decodeCounterpartOhSet(row.counterpartOhSet)!;
          expect(row.counterpartOhEndpoint, equals('node-2:59558'));
          // ... and the other known mailbox is kept, not dropped.
          expect(
            set.map((d) => d.serverEndpoint),
            equals(['node-2:59558', 'node-1:59558']),
          );
        },
      );
    });

    test('watchChannels emits the current channel list', () async {
      await repo.addChannel(await Channel.generate('Streamed'));

      final channels = await repo.watchChannels().first;
      expect(channels, hasLength(1));
      expect(channels.single.label, equals('Streamed'));
    });
  });
}
