# 📂 lib/services/

> App-Services: Outbox, Persistenz-Kanal, Gruppen, Kanal-Gesundheit, Foreground-Service, Peer-Persistenz.

## Dateien

* 📄 **drift_peer_repository.dart** — Drift-basierte Implementierung von
  `PeerRepository`. Hält In-Memory-Cache von `PeerStats`, berechnet
  exponentiellen gleitenden Durchschnitt für Latenz. Methoden: `updatePeer()`
  (Upsert mit Latenz-Berechnung), `getBestPeers()` (sortiert nach Score),
  `load()` (Cache aus DB hydratisieren), `addAll()` (Bulk-Add).

* 📄 **channel_health.dart** — `ChannelFetchInfo` + `channelFetchInfoProvider`: letzter Fetch-Zustand je Kanal (in-memory).

* 📄 **field_logging.dart** — `FieldLogging`: Opt-in-Feldtest-Logging (T17).

* 📄 **foreground_service.dart** — `ForegroundReceptionService`: Android-Foreground-Service für Empfang im Hintergrund (T16).

* 📄 **group_service.dart** — `GroupService`: MS08-Gruppenlebenszyklus (erstellen, einladen, …).

* 📄 **message_sync_service.dart** — `MessageSyncService`: der eine Persistenz-Kanal für `stateUpdates`/eingehende Nachrichten (T110).

* 📄 **outbox_service.dart** — `OutboxService`: einziger Send-Pfad mit Retry/Backoff, Fehler-Policy und ACK-Übergängen (T112; ersetzt `SendRetryQueue`).
