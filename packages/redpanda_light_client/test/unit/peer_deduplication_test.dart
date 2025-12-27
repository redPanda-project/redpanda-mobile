import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/client_impl.dart';

// Mock Socket
class MockSocket implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  bool isClosed = false;

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  void add(List<int> data) {}

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
  bool setOption(SocketOption option, bool enabled) { return true; }
  
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Peer Deduplication', () {
    late RedPandaLightClient client;
    final List<String> connectionAttempts = [];
    
    // Configurable factory behavior
    Future<Socket> Function(String, int)? customFactory;

    Future<Socket> mockSocketFactory(String host, int port) async {
       if (customFactory != null) {
         return customFactory!(host, port);
       }
       connectionAttempts.add('$host:$port');
       return MockSocket();
    }

    setUp(() {
      connectionAttempts.clear();
      customFactory = null;
    });

    // Test: Adding duplicate IP (localhost vs 127.0.0.1) should not trigger new connection
    test('Does not connect to same peer twice via alias (localhost/127.0.0.1)', () async {
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: ['localhost:5000'], // Start with localhost
        socketFactory: mockSocketFactory,
      );

      await client.connect();
      
      // Allow initial connection
      await Future.delayed(Duration(milliseconds: 100));
      expect(connectionAttempts, contains('localhost:5000'));
      int initialCount = connectionAttempts.length;

      // Add alias
      await client.addPeer('127.0.0.1:5000');
      
      // Wait for routine tick (if active) or immediate reaction
      // Routine runs every 3s, but we can't wait that long easily in unit test without FakeAsync.
      // However, addPeer might trigger check?
      // Let's assume the routine runs eventually. 
      // Current impl: addPeer adds to _knownAddresses. Routine iterates _knownAddresses.
      
      // We manually simulate the problem:
      // If we wait 3.1 seconds, the routine WILL run. 
      // But let's check if the logic supports deduplication at all.
      // We expect the client to resolve localhost -> 127.0.0.1 and realize it's already connected.
      
      // Since we mock socket, we can't easily rely on real DNS resolution inside the client unless we mock that too.
      // But standard `InternetAddress.lookup` is static.
      // We might need to abstract DNS resolution or use `InternetAddress.loopbackIPv4` logic.
      
      // For this test, let's see if it blindly tries to connect to 127.0.0.1 even if localhost is connected.
      
      // Force a manual triggering of the connection check if possible? 
      // No public API for that. define short timer? No param.
      
      // Wait for 3.5s (Test might be slow)
      // Or we can rely on immediate behavior if refactored.
      // Let's wait.
       await Future.delayed(Duration(milliseconds: 3500));
       
       // If deduplication works, we should NOT see '127.0.0.1:5000' in attempts if map already has 'localhost:5000' 
       // AND we resolved them to same IP.
       
       // FAILURE CONDITION: functionality NOT implemented yet.
       // It currently compares Strings. 'localhost:5000' != '127.0.0.1:5000'.
       // It will assume 127.0.0.1 is not connected.
       // It will try to connect.
       
       // If logic works effectively, we should NOT see duplicates.
       // However, we are writing a TDD test that confirms the BUG exists first (RED), then we fix it (GREEN).
       // The bug is: it connects to 127.0.0.1 even if localhost connected.
       // So we expect connectionAttempts TO contain 127.0.0.1:5000.
       
       // NOTE: For TDD, I will assert that it DOES contain it (proving the bug), 
       // then I will FLIP the assertion to 'does NOT contain' when I implement the fix.
       // OR even better: I write the "correct" test (should NOT contain) and see it FAIL.
       
       expect(connectionAttempts, isNot(contains('127.0.0.1:5000')), reason: "Should not connect to 127.0.0.1 if localhost is already connected");
    });
  });
}
