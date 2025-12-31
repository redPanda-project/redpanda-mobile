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
    await _db
        .into(_db.channels)
        .insert(
          db.ChannelsCompanion.insert(
            uuid: channel.id,
            label: channel.label,
            encryptionKey: HEX.encode(channel.encryptionKey),
            authenticationKey: HEX.encode(channel.authenticationKey),
            lastSeen: drift.Value(DateTime.now()),
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
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
    return Channel(
      label: data.label,
      encryptionKey: HEX.decode(data.encryptionKey),
      authenticationKey: HEX.decode(data.authenticationKey),
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
