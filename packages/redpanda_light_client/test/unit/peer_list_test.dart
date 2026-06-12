import "package:redpanda_light_client/src/network/active_peer.dart";
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/models/discovered_peer.dart';
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

  setUp(() async {
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
    selfKeys = await KeyPair.generate();
    selfNodeId = NodeId(Uint8List(20)); // Dummy NodeId
  });

  tearDown(() {
    socketStreamController.close();
  });

  test('ActivePeer handles SEND_PEERLIST command correctly', () async {
    final receivedPeers = Completer<List<DiscoveredPeer>>();

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
    // Create Proto. One legacy entry (address only), one MS04 entry with a
    // 64-byte node_id export and the explicit X25519 encryption key.
    final export = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final explicitKey = List<int>.filled(32, 0xAB);

    final sendPeerList = SendPeerList();
    sendPeerList.peers.add(
      PeerInfoProto()
        ..ip = '192.168.1.50'
        ..port = 5000,
    );
    sendPeerList.peers.add(
      PeerInfoProto()
        ..ip = '10.0.0.5'
        ..port = 6000
        ..nodeId = (NodeIdProto()..publicKeyBytes = export)
        ..encryptionPublicKey = explicitKey,
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

    final legacy = peers.firstWhere((p) => p.address == '192.168.1.50:5000');
    expect(legacy.nodeId, isNull);
    expect(legacy.encryptionPublicKey, isNull);

    final ms04 = peers.firstWhere((p) => p.address == '10.0.0.5:6000');
    // KademliaId = SHA256(verifyKey)[0..20] of the export's first 32 bytes.
    expect(ms04.nodeId, equals(NodeId.fromPublicKeyBytes(export).toHex()));
    // The explicit field 4 wins over the export's bytes 32..63.
    expect(ms04.encryptionPublicKey, equals(HEX.encode(explicitKey)));
  });

  test('SEND_PEERLIST falls back to export bytes 32..63 for the encryption '
      'key when field 4 is missing', () async {
    final receivedPeers = Completer<List<DiscoveredPeer>>();

    activePeer = ActivePeer(
      address: 'localhost:1234',
      selfNodeId: selfNodeId,
      selfKeys: selfKeys,
      socketFactory: (h, p) async => mockSocket,
      onStatusChange: (_) {},
      onDisconnect: () {},
      onPeersReceived: receivedPeers.complete,
    );

    await activePeer.connect();

    final handshakeResponse = BytesBuilder();
    handshakeResponse.add("k3gV".codeUnits);
    handshakeResponse.addByte(22);
    handshakeResponse.addByte(0xFF);
    handshakeResponse.add(Uint8List(20));
    handshakeResponse.add(Uint8List(4));
    socketStreamController.add(handshakeResponse.toBytes());
    await Future.delayed(Duration(milliseconds: 100));

    final export = Uint8List.fromList(List<int>.generate(64, (i) => 64 - i));
    final sendPeerList = SendPeerList();
    sendPeerList.peers.add(
      PeerInfoProto()
        ..ip = '10.0.0.7'
        ..port = 7000
        ..nodeId = (NodeIdProto()..publicKeyBytes = export),
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
    expect(peers, hasLength(1));
    expect(
      peers.single.encryptionPublicKey,
      equals(HEX.encode(export.sublist(32, 64))),
    );
  });

  test('ActivePeer sends REQUEST_PEERLIST command', () async {
    // Collect writes as they happen so the test can wait deterministically
    // for the async tx chain instead of using a fixed delay.
    final sent = <List<int>>[];
    when(() => mockSocket.add(any())).thenAnswer((invocation) {
      sent.add(List<int>.from(invocation.positionalArguments[0] as List<int>));
    });

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

    // Sends go through the async tx chain — poll until the REQUEST_PEERLIST
    // byte shows up (deterministic, no fixed delay).
    bool foundRequest() =>
        sent.any((c) => c.length == 1 && c[0] == 7); // REQUEST_PEERLIST
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!foundRequest()) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future.delayed(const Duration(milliseconds: 5));
    }
    expect(foundRequest(), isTrue, reason: "Should send REQUEST_PEERLIST (7)");
  });
}
