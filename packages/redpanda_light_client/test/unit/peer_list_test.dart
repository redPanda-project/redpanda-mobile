import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:redpanda_light_client/src/client_impl.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';
import 'package:redpanda_light_client/src/generated/commands.pb.dart';
import 'package:test/test.dart';

// ignore: depend_on_referenced_packages
import 'package:mocktail/mocktail.dart';

class MockSocket extends Mock implements Socket {}

void main() {
  late MockSocket mockSocket;
  late StreamController<Uint8List> socketStreamController;
  late ActivePeer activePeer;
  late NodeId selfNodeId;
  late KeyPair selfKeys;

  setUp(() {
    registerFallbackValue(SocketOption.tcpNoDelay);
    registerFallbackValue(Uint8List(0)); // Just in case

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
      return socketStreamController.stream.listen(onData);
    });

    when(() => mockSocket.setOption(any(), any())).thenReturn(true);
    when(() => mockSocket.add(any())).thenReturn(null);
    when(() => mockSocket.destroy()).thenReturn(null);

    // Use the KeyPair.generate() factory which creates a valid dummy pair
    selfKeys = KeyPair.generate();
    selfNodeId = NodeId(Uint8List(20)); // Dummy NodeId
  });

  tearDown(() {
    socketStreamController.close();
  });

  test('ActivePeer handles SEND_PEERLIST command correctly', () async {
    final receivedPeers = Completer<List<String>>();

    activePeer = ActivePeer(
      address: 'localhost:1234',
      selfNodeId: selfNodeId,
      selfKeys: selfKeys,
      socketFactory: (h, p) async => mockSocket,
      onStatusChange: (_) {},
      onDisconnect: () {},
      onPeersReceived: (peers) {
        receivedPeers.complete(peers);
      },
    );

    await activePeer.connect();

    // 1. Send Handshake Response (to verify connection)
    // Server sends: MAGIC(4) + VER(1) + 0xFF(1) + NodeId(20) + Port(4)
    final handshakeResponse = BytesBuilder();
    handshakeResponse.add("k3gV".codeUnits);
    handshakeResponse.addByte(22);
    handshakeResponse.addByte(0xFF);
    handshakeResponse.add(Uint8List(20)); // Peer NodeId
    handshakeResponse.add(Uint8List(4)); // Port

    socketStreamController.add(handshakeResponse.toBytes());

    // Allow loop to process
    await Future.delayed(Duration(milliseconds: 100));

    expect(activePeer.isHandshakeVerified, isTrue);

    // 2. Send SEND_PEERLIST command
    // Create Proto
    final sendPeerList = SendPeerList();
    sendPeerList.peers.add(
      PeerInfoProto()
        ..ip = '192.168.1.50'
        ..port = 5000,
    );
    sendPeerList.peers.add(
      PeerInfoProto()
        ..ip = '10.0.0.5'
        ..port = 6000,
    );

    final protoBytes = sendPeerList.writeToBuffer();

    final commandBuilder = BytesBuilder();
    commandBuilder.addByte(8); // SEND_PEERLIST

    final lengthData = ByteData(4);
    lengthData.setInt32(0, protoBytes.length, Endian.big);
    commandBuilder.add(lengthData.buffer.asUint8List());

    commandBuilder.add(protoBytes);

    socketStreamController.add(commandBuilder.toBytes());

    final peers = await receivedPeers.future;
    expect(peers.length, 2);
    expect(peers, contains('192.168.1.50:5000'));
    expect(peers, contains('10.0.0.5:6000'));
  });

  test('ActivePeer sends REQUEST_PEERLIST command', () async {
    activePeer = ActivePeer(
      address: 'localhost:1234',
      selfNodeId: selfNodeId,
      selfKeys: selfKeys,
      socketFactory: (h, p) async => mockSocket,
      onStatusChange: (_) {},
      onDisconnect: () {},
    );

    await activePeer.connect();
    // Verify handshake logic is bypassed or just inject message directly?
    // We want to test requestPeerList which calls _sendData

    // We can just call the method directly
    activePeer.requestPeerList();

    // Capture what was sent to socket
    // verify(() => mockSocket.add(any())).called(greaterThan(0));
    // But we need to inspect arguments.

    final captured = verify(() => mockSocket.add(captureAny())).captured;
    // captured might contain connection setup, handshake etc?
    // We expect [7] (REQUEST_PEERLIST)

    // Find the one that is [7]
    bool foundStart = false;
    for (final c in captured) {
      if (c is List<int> || c is Uint8List) {
        final list = c as List<int>;
        if (list.length == 1 && list[0] == 7) {
          foundStart = true;
          break;
        }
      }
    }
    expect(foundStart, isTrue, reason: "Should send REQUEST_PEERLIST (7)");
  });
}
