import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/garlic/hop_selector.dart';
import 'package:redpanda_light_client/src/peer_repository.dart';

/// Adds a peer with the given identity to [repo]. [firstByte] controls the
/// KademliaId prefix used by the diversity heuristic; [suffix] (default:
/// [firstByte]) fills the remaining id bytes so distinct peers can share a
/// prefix without sharing the full id.
void addPeer(
  InMemoryPeerRepository repo,
  String address,
  int firstByte, {
  int? suffix,
  bool withEncryptionKey = true,
}) {
  final nodeId = List<int>.filled(20, (suffix ?? firstByte) & 0xff)
    ..[0] = firstByte;
  repo.updatePeer(
    address,
    nodeId: HEX.encode(nodeId),
    encryptionPublicKey: withEncryptionKey
        ? HEX.encode(List<int>.filled(32, firstByte))
        : null,
  );
}

void main() {
  late InMemoryPeerRepository repo;
  late HopSelector selector;

  setUp(() {
    repo = InMemoryPeerRepository();
    selector = HopSelector(repo);
  });

  test('selects the requested number of distinct hops', () {
    for (var i = 1; i <= 6; i++) {
      addPeer(repo, '10.0.0.$i:5000', i);
    }

    final hops = selector.selectHops(count: 3);
    expect(hops, hasLength(3));
    final ids = hops.map((h) => HEX.encode(h.nodeId)).toSet();
    expect(ids, hasLength(3), reason: 'hops must be distinct relays');
  });

  test('only peers with an encryption key qualify', () {
    addPeer(repo, '10.0.0.1:5000', 1);
    addPeer(repo, '10.0.0.2:5000', 2, withEncryptionKey: false);
    repo.updatePeer('10.0.0.3:5000'); // address only, no identity

    final hops = selector.selectHops(count: 3);
    expect(hops, hasLength(1));
    expect(hops.single.nodeId[0], 1);
  });

  test('excluded addresses and node ids never appear in the path', () {
    for (var i = 1; i <= 5; i++) {
      addPeer(repo, '10.0.0.$i:5000', i);
    }
    final excludedNodeId = HEX.encode(List<int>.filled(20, 2)..[0] = 2);

    for (var run = 0; run < 20; run++) {
      final hops = selector.selectHops(
        count: 3,
        excludeAddresses: {'10.0.0.1:5000'},
        excludeNodeIds: {excludedNodeId},
      );
      expect(hops, hasLength(3));
      for (final hop in hops) {
        expect(hop.nodeId[0], isNot(1), reason: 'excluded by address');
        expect(hop.nodeId[0], isNot(2), reason: 'excluded by node id');
      }
    }
  });

  test('returns fewer hops when not enough candidates exist', () {
    addPeer(repo, '10.0.0.1:5000', 1);
    addPeer(repo, '10.0.0.2:5000', 2);

    expect(selector.selectHops(count: 3), hasLength(2));
    expect(
      selector.selectHops(
        count: 3,
        excludeAddresses: {'10.0.0.1:5000', '10.0.0.2:5000'},
      ),
      isEmpty,
    );
  });

  test('the same node known under two addresses is used at most once', () {
    addPeer(repo, '10.0.0.1:5000', 7);
    addPeer(repo, 'alias.example:5000', 7); // same KademliaId
    addPeer(repo, '10.0.0.2:5000', 8);

    final hops = selector.selectHops(count: 3);
    expect(hops, hasLength(2));
  });

  test('prefers distinct KademliaId prefixes when possible', () {
    // Three candidates share prefix 0x01; two have distinct prefixes. A
    // diverse pick must include both distinct prefixes every time.
    addPeer(repo, '10.0.1.1:5000', 1, suffix: 11);
    addPeer(repo, '10.0.1.2:5000', 1, suffix: 12);
    addPeer(repo, '10.0.1.3:5000', 1, suffix: 13);
    addPeer(repo, '10.0.2.1:5000', 2);
    addPeer(repo, '10.0.3.1:5000', 3);

    for (var run = 0; run < 20; run++) {
      final prefixes = selector
          .selectHops(count: 3)
          .map((h) => h.nodeId[0])
          .toList();
      expect(prefixes, contains(2));
      expect(prefixes, contains(3));
      expect(prefixes, hasLength(3));
    }
  });

  test('candidateFilter pins the candidate set', () {
    for (var i = 1; i <= 6; i++) {
      addPeer(repo, '10.0.0.$i:5000', i);
    }
    final filtered = HopSelector(
      repo,
      candidateFilter: (peer) => peer.address.endsWith('1:5000'),
    );

    final hops = filtered.selectHops(count: 3);
    expect(hops, hasLength(1));
    expect(hops.single.nodeId[0], 1);
  });
}
