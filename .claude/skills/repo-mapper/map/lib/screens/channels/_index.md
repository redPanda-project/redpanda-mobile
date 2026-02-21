# 📂 lib/screens/channels/

> Screens zum Erstellen und Beitreten von verschlüsselten Channels via QR-Code.

## Dateien

* 📄 **create_channel_screen.dart** — Channel-Erstellung (`CreateChannelScreen`,
  ConsumerStatefulWidget). Benutzer gibt Channel-Name ein → generiert
  AES-256-Keys via `Channel.generate()` → zeigt QR-Code mit Channel-JSON.
  Nutzt `channelRepositoryProvider`, `qr_flutter`, `go_router`.

* 📄 **join_channel_screen.dart** — Channel-Beitritt (`JoinChannelScreen`,
  ConsumerStatefulWidget). Öffnet Kamera via `MobileScanner`, scannt QR-Code,
  dekodiert JSON zu `Channel`-Objekt, speichert via `channelRepositoryProvider`.
  Navigiert nach Erfolg zurück zur Home-Seite.
