# 📂 lib/shared/

> Geteilte Provider-Registry und wiederverwendbare Widgets.

## Unterordner

* 📁 **[widgets/](widgets/_index.md)** — Wiederverwendbare UI-Komponenten (ConnectionStatusBadge).

## Dateien

* 📄 **providers.dart** — Zentrale Riverpod-Provider-Registry. Exponiert:
  `dbProvider` (AppDatabase Singleton), `redPandaClientProvider`
  (RedPandaIsolateClient), `connectionStatusProvider` (Stream),
  `peerCountProvider` (Stream), `activePeersProvider` (Stream),
  `connectingPeersProvider` (Stream). Alle greifen auf den RedPanda Light Client zu.
