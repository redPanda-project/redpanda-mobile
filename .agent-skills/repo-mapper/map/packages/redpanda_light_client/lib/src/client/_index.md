# 📂 packages/redpanda_light_client/lib/src/client/

> Kernimplementierung des RedPanda Light Clients und Isolate-Proxy.

## Dateien

* 📄 **redpanda_light_client.dart** — Hauptimplementierung (`RedPandaLightClient`).
  Verwaltet Peer-Verbindungen mit Backoff-Strategie, Connection-Pooling
  (3 Core-Slots + 2 Roaming), latenzbasiertes Peer-Ranking.
  Mobile-Lifecycle-Hooks (onPause/onResume), Peer-Discovery,
  Stream-basierte Status-/PeerCount-Updates.

* 📄 **isolate_client.dart** — Isolate-Proxy (`RedPandaIsolateClient`).
  Implementiert `RedPandaClient`, leitet alle Operationen an ein
  Hintergrund-Isolate weiter via SendPort/ReceivePort. Verhindert UI-Jank.

* 📄 **isolate_protocol.dart** — Nachrichtenprotokoll für Isolate-Kommunikation.
  Command-Klassen: `CmdInit`, `CmdConnect`, `CmdAddPeer`, `CmdLifecyclePause`,
  `CmdLifecycleResume`, `CmdSendMessage`.
  Event-Klassen: `EventConnectionStatus`, `EventPeerCount`, `EventLog`.
