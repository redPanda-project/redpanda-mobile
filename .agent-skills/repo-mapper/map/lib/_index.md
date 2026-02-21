# 📂 lib/

> Flutter-App-Code: Screens, Datenbank, Repositories, Services und Shared-Komponenten.
> State-Management via Riverpod, Navigation via GoRouter, Persistenz via Drift.

## Unterordner

* 📁 **[database/](database/_index.md)** — Drift-ORM-Schema (Users, Channels, Messages, Peers).
* 📁 **[repositories/](repositories/_index.md)** — Repository-Pattern für Channel-Zugriff.
* 📁 **[screens/](screens/_index.md)** — Alle App-Screens (Home, Chat, Channels, Onboarding, Debug).
* 📁 **[services/](services/_index.md)** — Drift-basierte PeerRepository-Implementierung.
* 📁 **[shared/](shared/_index.md)** — Provider-Registry und wiederverwendbare Widgets.

## Dateien

* 📄 **main.dart** — App-Einstiegspunkt. Erstellt `MyApp` mit `ProviderScope`,
  verbindet RedPandaClient beim Start, verwaltet App-Lifecycle (Pause/Resume).
  Material 3 Theme mit Pink-Seed-Color.

* 📄 **router.dart** — GoRouter-Konfiguration mit 6 Routen: `/onboarding`, `/`
  (Home), `/chat/:uuid`, `/debug-stats`, `/channels/create`, `/channels/join`.
  Redirect-Logik: erzwingt Onboarding falls kein User existiert.
