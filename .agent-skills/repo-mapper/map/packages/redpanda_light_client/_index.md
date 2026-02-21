# 📂 packages/redpanda_light_client/

> Eigenständiges Dart-Paket: P2P-Netzwerk-Client mit Kademlia-DHT, TCP-Verbindungen,
> ECDH/AES-Verschlüsselung und Protobuf-Protokoll.

## Unterordner

* 📁 **[lib/](lib/_index.md)** — Quellcode: Client, Domain-Modelle, Netzwerk, Krypto.

## Wichtige Dateien

* 📄 **pubspec.yaml** — Paket `redpanda_light_client`. Dependencies: `protobuf`,
  `pointycastle`, `asn1lib`.
* 📄 **protos/commands.proto** — Protobuf-Definitionen: Kademlia-Messages
  (Get/Store/Answer), Peer-Listen, Ping/Pong, Flaschenpost, GarlicMessage
  (verschlüsseltes Routing).
* 📄 **gen_dart.sh** — Script zur Protobuf-Code-Generierung.

## Tests

Unit-Tests: Handshake, Backoff, Peer-Deduplication, Peer-Liste, Connection-Logik,
Encryption, Channel, Multi-Peer.
E2E-Tests: Client-Connect, Ping-Pong, Launcher.
