# 📂 lib/

> Flutter-App-Code: Screens, Datenbank, Repositories, Services und Shared-Komponenten.
> State-Management via Riverpod, Navigation via GoRouter, Persistenz via Drift.

## Unterordner

* 📁 **domain/** — App-Domänenregeln (`message_direction.dart`, `message_lifecycle.dart`).
* 📁 **[database/](database/_index.md)** — Drift-ORM-Schema (Users, Channels, Messages, Peers).
* 📁 **[repositories/](repositories/_index.md)** — Repository-Pattern für Channels, Messages, Gruppen, eigene OHs.
* 📁 **[screens/](screens/_index.md)** — Alle App-Screens (Home, Chat, Channels, Onboarding, Debug).
* 📁 **[services/](services/_index.md)** — Outbox (Send-/Retry-Pfad), Persistenz-Kanal, Gruppen, Foreground-Service, Peer-Repository.
* 📁 **[shared/](shared/_index.md)** — Provider-Registry und wiederverwendbare Widgets.

## Dateien

* 📄 **main.dart** — App-Einstiegspunkt. Erstellt `MyApp` mit `ProviderScope`,
  verbindet RedPandaClient beim Start, verwaltet App-Lifecycle (Pause/Resume).
  Material 3 Theme mit Pink-Seed-Color.

* 📄 **router.dart** — GoRouter-Konfiguration mit 6 Routen: `/onboarding`, `/`
  (Home), `/chat/:uuid`, `/debug-stats`, `/channels/create`, `/channels/join`.
  Redirect-Logik: erzwingt Onboarding falls kein User existiert.
