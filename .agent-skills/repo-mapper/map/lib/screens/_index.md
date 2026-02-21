# 📂 lib/screens/

> Alle App-Screens: Onboarding, Home, Chat, Channel-Verwaltung, Debug.

## Unterordner

* 📁 **[chat/](chat/_index.md)** — Chat-UI und QR-Code-Sharing.
* 📁 **[channels/](channels/_index.md)** — Screens zum Erstellen und Beitreten von Channels.
* 📁 **[home/](home/_index.md)** — Hauptbildschirm mit Channel-Liste.
* 📁 **[onboarding/](onboarding/_index.md)** — Ersteinrichtung / Benutzername setzen.

## Dateien

* 📄 **debug_peer_stats_screen.dart** — Debug-Screen (`DebugPeerStatsScreen`,
  ConsumerWidget) für Peer-Netzwerk-Statistiken. Zeigt alle Peers mit Latenz,
  Erfolgs-/Fehlerrate und Score. Farbcodierung nach Verbindungsstatus.
  Nutzt `activePeersProvider`, `connectingPeersProvider`, `dbProvider`.
  Enthält `_StatBadge`-Hilfswidget für Metriken.
