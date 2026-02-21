# 📂 lib/services/

> Service-Implementierungen für Datenpersistenz.

## Dateien

* 📄 **drift_peer_repository.dart** — Drift-basierte Implementierung von
  `PeerRepository`. Hält In-Memory-Cache von `PeerStats`, berechnet
  exponentiellen gleitenden Durchschnitt für Latenz. Methoden: `updatePeer()`
  (Upsert mit Latenz-Berechnung), `getBestPeers()` (sortiert nach Score),
  `load()` (Cache aus DB hydratisieren), `addAll()` (Bulk-Add).
