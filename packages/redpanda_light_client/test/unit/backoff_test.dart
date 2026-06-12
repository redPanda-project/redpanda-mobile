import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class FakeSocket extends Fake implements Socket {
  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return StreamController<Uint8List>().stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(List<int> data) {}

  @override
  void destroy() {}

  @override
  Future<void> close() async {}
}

void main() {
  group('RedPandaLightClient Backoff', () {
    late RedPandaLightClient client;
    late NodeId nodeId;
    late KeyPair keyPair;
    int connectionAttempts = 0;

    setUp(() async {
      nodeId = NodeId(Uint8List.fromList(List.filled(20, 1)));
      keyPair = await KeyPair.generate();
      connectionAttempts = 0;
    });

    Future<Socket> failingSocketFactory(String host, int port) async {
      connectionAttempts++;
      throw SocketException('Connection rejected');
    }

    test('should apply exponential backoff on repeated failures', () async {
      client = RedPandaLightClient(
        selfNodeId: nodeId,
        selfKeys: keyPair,
        seeds: ['127.0.0.1:9000'],
        socketFactory: failingSocketFactory,
      );

      // Start connection routine
      client.connect();

      // Initial check runs immediately
      await Future.delayed(Duration(milliseconds: 100));
      expect(
        connectionAttempts,
        1,
        reason: 'Should attempt connection immediately',
      );

      // First backoff should be around 2 seconds
      // Wait 1 second - should NOT have retried yet
      await Future.delayed(Duration(seconds: 1));
      expect(
        connectionAttempts,
        1,
        reason: 'Should wait for backoff before retrying',
      );

      // Wait another 1.5 seconds (total 2.5s) - should have retried
      await Future.delayed(Duration(milliseconds: 1500));
      // Note: The timer in client is 3 seconds periodic.
      // If backoff is 2s, the NEXT timer tick after 2s will retry.
      // Timer ticks at: 0s (run), 3s, 6s, 9s...
      // IF logic is: timer runs _runConnectionCheck -> checks backoff.
      // T=0: Fail. Backoff set to T+2s.
      // T=3: Timer tick. Now > T+2s. Should retry.

      // So looking at the implementation details, the retry is driven by the periodic timer (3s).
      // If we implement backoff, we skip 'retry' if backoff time hasn't passed.

      // T=0: Attempt 1. Fail. Next retry @ T+2s.
      // T=3: Timer tick. T=3 > T+2. Attempt 2. Fail. Next retry @ T+3 + 4s = T+7s.

      // Wait for first tick (3s) + slight buffer
      await Future.delayed(Duration(seconds: 3, milliseconds: 100));
      expect(connectionAttempts, 2, reason: 'Should retry at T=3s (Attempt 2)');

      // T=6: Timer tick. T=6 < T+7. Should Skip.
      await Future.delayed(Duration(seconds: 3));
      expect(
        connectionAttempts,
        2,
        reason: 'Should skip retry at T=6s due to backoff to T=7s',
      );

      // T=9: Timer tick. T=9 > T+7. Attempt 3. Fail. Next retry @ T+9 + 8s = T+17s.
      await Future.delayed(Duration(seconds: 3));
      expect(connectionAttempts, 3, reason: 'Should retry at T=9s (Attempt 3)');

      // Stop client to cancel timer
      await client.disconnect();
    });
  });
}
