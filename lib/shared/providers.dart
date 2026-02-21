import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

final dbProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final redPandaClientProvider = Provider<RedPandaClient>((ref) {
  return RedPandaIsolateClient(seeds: RedPandaLightClient.defaultSeeds);
});

final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final client = ref.watch(redPandaClientProvider);
  return client.connectionStatus;
});

final peerCountProvider = StreamProvider<int>((ref) {
  final client = ref.watch(redPandaClientProvider);
  return client.peerCountStream;
});

final peerStatsSnapshotProvider = StreamProvider<PeerStatsSnapshot>((ref) {
  final client = ref.watch(redPandaClientProvider);
  return client.peerStatsStream;
});

final activePeersProvider = Provider<List<String>>((ref) {
  final snapshot = ref.watch(peerStatsSnapshotProvider);
  return snapshot.value?.activePeerAddresses.toList() ?? [];
});

final connectingPeersProvider = Provider<List<String>>((ref) {
  final snapshot = ref.watch(peerStatsSnapshotProvider);
  return snapshot.value?.connectingPeerAddresses.toList() ?? [];
});
