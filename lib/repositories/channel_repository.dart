import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda/database/database.dart' as db;
import 'package:drift/drift.dart' as drift;
import 'package:hex/hex.dart';
import 'package:redpanda/shared/providers.dart';

abstract class ChannelRepository {
  Future<void> addChannel(Channel channel);
  Future<List<Channel>> getChannels();
  Stream<List<Channel>> watchChannels();
}

class DriftChannelRepository implements ChannelRepository {
  final db.AppDatabase _db;

  DriftChannelRepository(this._db);

  @override
  Future<void> addChannel(Channel channel) async {
    final companion = db.ChannelsCompanion.insert(
      uuid: channel.id,
      label: channel.label,
      encryptionKey: HEX.encode(channel.encryptionKey),
      channelSecret: drift.Value(HEX.encode(channel.channelSecret)),
      authPrivateKey: drift.Value(
        channel.authPrivateKey != null
            ? HEX.encode(channel.authPrivateKey!)
            : null,
      ),
      authPublicKey: HEX.encode(channel.authPublicKey),
      peerOhEndpoint: drift.Value(channel.peerOhDescriptor?.serverEndpoint),
      peerOhId: drift.Value(
        channel.peerOhDescriptor != null
            ? HEX.encode(channel.peerOhDescriptor!.handleId)
            : null,
      ),
      peerOhPublicKey: drift.Value(
        channel.peerOhDescriptor != null
            ? HEX.encode(channel.peerOhDescriptor!.authPublicKey)
            : null,
      ),
      lastSeen: drift.Value(DateTime.now()),
    );

    await _db
        .into(_db.channels)
        .insert(companion, mode: drift.InsertMode.insertOrReplace);
  }

  @override
  Future<List<Channel>> getChannels() async {
    final channelDataList = await _db.select(_db.channels).get();
    return channelDataList.map(_mapToDomain).toList();
  }

  @override
  Stream<List<Channel>> watchChannels() {
    return _db.select(_db.channels).watch().map((rows) {
      return rows.map(_mapToDomain).toList();
    });
  }

  Channel _mapToDomain(db.Channel data) {
    OHDescriptor? ohDescriptor;
    if (data.peerOhEndpoint != null &&
        data.peerOhId != null &&
        data.peerOhPublicKey != null) {
      ohDescriptor = OHDescriptor(
        serverEndpoint: data.peerOhEndpoint!,
        handleId: HEX.decode(data.peerOhId!),
        authPublicKey: HEX.decode(data.peerOhPublicKey!),
      );
    }

    return Channel(
      label: data.label,
      // v4 channels always persist the secret; the `??` only guards the
      // impossible legacy-row case (v3 rows are wiped by the v17 migration).
      channelSecret: data.channelSecret != null
          ? HEX.decode(data.channelSecret!)
          : const <int>[],
      encryptionKey: HEX.decode(data.encryptionKey),
      authPrivateKey: data.authPrivateKey != null
          ? HEX.decode(data.authPrivateKey!)
          : null,
      authPublicKey: HEX.decode(data.authPublicKey),
      peerOhDescriptor: ohDescriptor,
    );
  }
}

final channelRepositoryProvider = Provider<ChannelRepository>((ref) {
  final db = ref.watch(dbProvider);
  return DriftChannelRepository(db);
});

final channelsProvider = StreamProvider<List<Channel>>((ref) {
  final repo = ref.watch(channelRepositoryProvider);
  return repo.watchChannels();
});
