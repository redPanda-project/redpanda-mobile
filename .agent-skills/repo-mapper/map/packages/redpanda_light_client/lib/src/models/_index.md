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

* 📄 **key_pair.dart** — EC-Schlüsselpaar (`KeyPair`) auf brainpoolp256r1.
  Generierung via `KeyPair.generate()`, Public Key als unkomprimierte Bytes
  (0x04 + X + Y). Private Key für Signing/ECDH.
