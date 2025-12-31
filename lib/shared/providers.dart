import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

final dbProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final redPandaClientProvider = Provider<RedPandaClient>((ref) {
  // Direct initialization is now fast (HashCash loop removed)
  final keys = KeyPair.generate();
  // final db = ref.read(dbProvider); // DB not yet supported in Isolate

  return RedPandaIsolateClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
    seeds: RedPandaLightClient.defaultSeeds,
    // peerRepository: DriftPeerRepository(db),
  );
});

final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final client = ref.watch(redPandaClientProvider);
  return client.connectionStatus;
});

final peerCountProvider = StreamProvider<int>((ref) {
  final client = ref.watch(redPandaClientProvider);
  return client.peerCountStream;
});

final activePeersProvider = StreamProvider<List<String>>((ref) {
  final client = ref.watch(redPandaClientProvider);
  if (client is RedPandaLightClient) {
    return client.activePeersStream;
  }
  return Stream.value([]);
});

final connectingPeersProvider = StreamProvider<List<String>>((ref) {
  final client = ref.watch(redPandaClientProvider);
  if (client is RedPandaLightClient) {
    return client.connectingPeersStream;
  }
  return Stream.value([]);
});
