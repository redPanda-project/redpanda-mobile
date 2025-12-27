import 'package:test/test.dart';
import 'redpanda_node_launcher.dart';
import 'dart:io';

void main() {
  group('E2E Node Launcher', () {
    late RedPandaNodeLauncher launcher;
    final port = 50001;

    setUp(() {
      launcher = RedPandaNodeLauncher(port: port);
    });

    tearDown(() async {
      await launcher.stop();
    });

    test('starts and stops the java process', () async {
      await launcher.start();

      // Verify port is open (simple socket connect)
      final socket = await Socket.connect('127.0.0.1', port);
      expect(socket, isNotNull);
      await socket.close();
    });
  });
}
