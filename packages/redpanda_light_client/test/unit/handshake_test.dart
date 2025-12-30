import "package:redpanda_light_client/src/network/active_peer.dart";
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockSocket extends Mock implements Socket {}

void main() {
  late MockSocket mockSocket;
  late StreamController<Uint8List> socketStreamController;
  late NodeId selfNodeId;
  late KeyPair selfKeys;

  setUp(() {
    registerFallbackValue(SocketOption.tcpNoDelay);
    registerFallbackValue(Uint8List(0));

    mockSocket = MockSocket();
    socketStreamController = StreamController<Uint8List>();

    when(
      () => mockSocket.listen(
        any(),
        onError: any(named: 'onError'),
        onDone: any(named: 'onDone'),
        cancelOnError: any(named: 'cancelOnError'),
      ),
    ).thenAnswer((invocation) {
      final onData =
          invocation.positionalArguments[0] as void Function(Uint8List);
      socketStreamController.stream.listen(onData);
      return MockStreamSubscription();
    });

    when(() => mockSocket.setOption(any(), any())).thenReturn(true);
    when(() => mockSocket.add(any())).thenReturn(null);
    when(() => mockSocket.destroy()).thenReturn(null);

    selfKeys = KeyPair.generate();
    selfNodeId = NodeId(Uint8List(20));
  });

  tearDown(() {
    socketStreamController.close();
  });

  test('Handshake identifies as Light Client (ActivePeer)', () async {
    final activePeer = ActivePeer(
      address: 'localhost:1234',
      selfNodeId: selfNodeId,
      selfKeys: selfKeys,
      socketFactory: (h, p) async => mockSocket,
      onStatusChange: (_) {},
      onDisconnect: () {},
    );

    await activePeer.connect();

    // Verify sent bytes
    final captured = verify(() => mockSocket.add(captureAny())).captured;

    // Find the handshake buffer
    // Handshake: MAGIC(4) + VER(1) + CLIENT_TYPE(1) + NODEID(20) + PORT(4)
    // Client Type should be 1 (Light Client)

    bool handshakeFound = false;
    for (final c in captured) {
      if (c is List<int>) {
        // Check if it looks like a handshake
        if (c.length >= 30) {
          // Magic 'k3gV' is [107, 51, 103, 86]
          if (c[0] == 107 && c[1] == 51) {
            // Byte 0-3: Magic
            // Byte 4: Version (22)
            // Byte 5: Type. Should be 1.
            expect(
              c[5],
              equals(160),
              reason: "Handshake byte at index 5 must be 160 (Light Client)",
            );
            handshakeFound = true;
          }
        }
      }
    }
    expect(handshakeFound, isTrue, reason: "Handshake payload not found");
  });
}

class MockStreamSubscription extends Mock
    implements StreamSubscription<Uint8List> {}
