# 📂 packages/redpanda_light_client/lib/src/

> Gesamte Quellcode-Bibliothek des Light Clients: Netzwerk, Krypto, Datenmodelle.

## Unterordner

* 📁 **[client/](client/_index.md)** — Client-Implementierung und Isolate-Proxy.
* 📁 **[domain/](domain/_index.md)** — Domain-Objekte (Channel, GarlicMessage).
* 📁 **[generated/](generated/_index.md)** — Generierter Protobuf-Code.
* 📁 **[mock/](mock/_index.md)** — Mock-Client für Tests.
* 📁 **[models/](models/_index.md)** — Datenmodelle (NodeId, Peer, KeyPair, ConnectionStatus).
* 📁 **[network/](network/_index.md)** — TCP-Peer-Verbindungen und Protokoll.
* 📁 **[security/](security/_index.md)** — ECDH-Verschlüsselung und AES-Cipher.

## Dateien

* 📄 **client_facade.dart** — Abstraktes Interface (`RedPandaClient`) mit der
  öffentlichen API: `connectionStatus`-Stream, `peerCountStream`, `connect()`,
  `disconnect()`, `addPeer()`, `sendMessage()`.

* 📄 **peer_repository.dart** — Abstraktes Repository für Peer-Persistenz
  (`PeerRepository`). `InMemoryPeerRepository`-Implementierung mit
  Scoring-Algorithmus (bevorzugt niedrige Latenz, hohe Zuverlässigkeit, Aktualität).
