import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

final dbProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final redPandaClientProvider = Provider<RedPandaClient>((ref) {
  // Direct initialization is now fast (HashCash loop removed)
  final keys = KeyPair.generate();

  return RedPandaLightClient(
    selfNodeId: NodeId.fromPublicKey(keys),
    selfKeys: keys,
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
