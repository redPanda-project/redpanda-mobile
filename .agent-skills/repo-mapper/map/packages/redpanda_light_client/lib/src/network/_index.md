# 📂 packages/redpanda_light_client/lib/src/network/

> Netzwerkschicht: TCP-Verbindungen und Peer-Protokoll.

## Dateien

* 📄 **active_peer.dart** — Verwaltung einer einzelnen Peer-Verbindung
  (`ActivePeer`). TCP-Handshake (Magic "k3gV"), Public-Key-Austausch,
  Encryption-Aktivierung (ECDH + AES/CTR), Ping/Pong-Latenzmessung,
  Peer-Listen-Austausch. Parst Protobuf-Command-Payloads (Kademlia,
  Flaschenpost, GarlicMessage).
