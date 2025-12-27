import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/client_impl.dart';

// Mock Socket
class MockSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  final List<int> sentData = [];
  bool isClosed = false;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(List<int> data) {
    sentData.addAll(data);
  }

  @override
  void destroy() {
    isClosed = true;
    _controller.close();
  }

  @override
  Future<void> close() async {
    isClosed = true;
    _controller.close();
  }

  @override
  bool setOption(SocketOption option, bool enabled) {
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Multi-Peer Connection Routine', () {
    late RedPandaLightClient client;
    final List<String> connectionAttempts = [];

    Future<Socket> mockSocketFactory(String host, int port) async {
      connectionAttempts.add('$host:$port');
      return MockSocket();
    }

    setUp(() {
      connectionAttempts.clear();
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: ['localhost:1001', 'localhost:1002'],
        socketFactory:
            mockSocketFactory, // Does not exist yet, will fail compilation
      );
    });

    // Test 1: Connects to all seeds on startup
    test('Connects to all seeds initially', () async {
      await client.connect();
      // Allow async loop to trigger
      await Future.delayed(Duration(milliseconds: 100));

      expect(connectionAttempts, contains('localhost:1001'));
      expect(connectionAttempts, contains('localhost:1002'));
      expect(connectionAttempts.length, greaterThanOrEqualTo(2));
    });

    // Test 2: Periodically retries FAILED connections
    test('Periodically retries FAILED connections', () async {
      // Create client that fails connections initially
      int callCount = 0;
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(KeyPair.generate()),
        selfKeys: KeyPair.generate(),
        seeds: ['localhost:1001'],
        socketFactory: (h, p) async {
          callCount++;
          if (callCount == 1) {
            throw "Connection Refused";
          }
          connectionAttempts.add('$h:$p');
          return MockSocket();
        },
      );

      await client.connect();
      expect(connectionAttempts, isEmpty);

      // Wait for routine (3s+)
      await Future.delayed(Duration(milliseconds: 3500));

      expect(connectionAttempts, contains('localhost:1001'));
    });

    // Test 3: Connects to new peers added to list
    test('Connects to new peers added to list', () async {
      // Re-init client to avoid leaks from previous tests if setup not perfect
      // But we use setUp, so 'client' is fresh, BUT we need custom factory for above test.
      // Setup provides default client. We can just use it.
      await client.connect();
      await Future.delayed(Duration(milliseconds: 100)); // First run

      connectionAttempts.clear();

      // Add new peer
      await client.addPeer('localhost:1003');

      // Wait for next tick (max 3s)
      await Future.delayed(Duration(milliseconds: 3500));

      expect(connectionAttempts, contains('localhost:1003'));
    });
  });
}
