/// A peer entry parsed from a `SendPeerList` exchange (MS04).
///
/// Besides the address, the node may include its identity: the 20-byte
/// KademliaId (derived from the 64-byte `node_id` public export) and the
/// 32-byte X25519 encryption public key needed to use the peer as a garlic
/// hop. Both are hex-encoded; either may be null for legacy entries.
class DiscoveredPeer {
  final String address;
  final String? nodeId;
  final String? encryptionPublicKey;

  const DiscoveredPeer({
    required this.address,
    this.nodeId,
    this.encryptionPublicKey,
  });
}
