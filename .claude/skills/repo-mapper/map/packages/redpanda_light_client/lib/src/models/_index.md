# 📂 packages/redpanda_light_client/lib/src/models/

> Datenmodelle für Netzwerk-Identitäten, Verbindungsstatus und Kryptografie.

## Dateien

* 📄 **node_id.dart** — 160-Bit Kademlia-DHT-Identifier (`NodeId`).
  Ableitbar aus Public Key via SHA256. Hex-/Base58-Encoding, Random-Generierung.

* 📄 **connection_status.dart** — Enum: `disconnected`, `connecting`, `connected`, `offline`.

* 📄 **peer.dart** — Datenmodell für einen Remote-Node (`Peer`): nodeId, IP,
  Port, optionales KeyPair, Verbindungsstatus, lastSeen. Enthält `copyWith()`.

* 📄 **peer_stats.dart** — Peer-Metriken (`PeerStats`): Adresse, Latenz,
  Success/Failure-Counts, lastSeen. Scoring-Formel balanciert Latenz,
  Zuverlässigkeit und Zeit-Decay (halbiert nach 24h, 90% nach 1 Woche).

* 📄 **key_pair.dart** — Node-Identität (`KeyPair`, MS03): Dual-Keypair mit
  strikter Schlüsseltrennung (Ed25519 zum Signieren, X25519 für Key-Agreement),
  analog zum Backend-`NodeId`.

* 📄 **discovered_peer.dart** — `DiscoveredPeer`: Peer-Eintrag aus dem `SendPeerList`-Austausch (MS04).

* 📄 **peer_stats_snapshot.dart** — `PeerStatsSnapshot`: Momentaufnahme aller bekannten Peers und ihrer Verbindungszustände.
