# 📂 lib/screens/home/

> Hauptbildschirm der App mit Channel-Liste und Navigation.

## Dateien

* 📄 **home_screen.dart** — Haupt-Hub (`HomeScreen`, ConsumerWidget).
  Zeigt Channel-Liste via `channelsProvider` als ListView mit Avataren.
  AppBar mit `ConnectionStatusBadge` und Settings-Icon.
  Zwei FABs: QR-Scanner (Channel beitreten) und Plus (Channel erstellen).
  Navigiert zu `/chat/:uuid`, `/channels/join`, `/channels/create`.
