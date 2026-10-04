# 📂 packages/redpanda_light_client/lib/src/

> Gesamte Quellcode-Bibliothek des Light Clients: Netzwerk, Krypto, Datenmodelle.

## Unterordner

* 📁 **[client/](client/_index.md)** — Client-Implementierung und Isolate-Proxy.
* 📁 **[crypto/](crypto/_index.md)** — Kanal-/Gruppen-Krypto (Envelopes v3/v4, Ratchet, Rendezvous, OH-Keypair).
* 📁 **[domain/](domain/_index.md)** — Domain-Objekte (Channel, OH-Deskriptoren, ACKs, StateUpdate-Events).
* 📁 **[garlic/](garlic/_index.md)** — Garlic-Builder, Hop-Auswahl, Node-Scoring, Reverse-Garlic-Blocks, Tag-Stores.
* 📁 **[generated/](generated/_index.md)** — Generierter Protobuf-Code.
* 📁 **[mock/](mock/_index.md)** — Mock-Client für Tests.
* 📁 **[models/](models/_index.md)** — Datenmodelle (NodeId, Peer, KeyPair, ConnectionStatus).
* 📁 **[logging/](logging/_index.md)** — `RpLog`-Logger.
* 📁 **[network/](network/_index.md)** — TCP-Peer-Verbindungen und Protokoll.
* 📁 **[security/](security/_index.md)** — Transport-Verschlüsselung (AES-256-GCM-Framing).
* 📁 **[streams/](streams/_index.md)** — Stream-Hilfen (`seededStream()`).

## Dateien

* 📄 **client_facade.dart** — Abstraktes Interface (`RedPandaClient`) mit der
  öffentlichen API: `connectionStatus`-Stream, `peerCountStream`, `connect()`,
  `disconnect()`, `addPeer()`, `sendMessage()`.

* 📄 **peer_repository.dart** — Abstraktes Repository für Peer-Persistenz
  (`PeerRepository`). `InMemoryPeerRepository`-Implementierung mit
  Scoring-Algorithmus (bevorzugt niedrige Latenz, hohe Zuverlässigkeit, Aktualität).
