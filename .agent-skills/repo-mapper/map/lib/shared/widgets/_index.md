# 📂 lib/shared/widgets/

> Wiederverwendbare UI-Komponenten.

## Dateien

* 📄 **connection_status_badge.dart** — Netzwerkstatus-Badge
  (`ConnectionStatusBadge`, ConsumerWidget). Zeigt Icon + Farbe + Tooltip
  je nach Verbindungsstatus (connected/connecting/offline).
  Peer-Count-Badge bei aktiver Verbindung. Navigiert bei Tap zu `/debug-stats`.
  Nutzt `connectionStatusProvider`, `peerCountProvider`.
