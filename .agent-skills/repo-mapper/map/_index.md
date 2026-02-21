# 📂 RedPanda Mobile

> Dezentrale, verschlüsselte Chat-App (Flutter). Peer-to-Peer-Kommunikation
> über Kademlia-DHT mit Ende-zu-Ende-Verschlüsselung (ECDH + AES-256).

## Unterordner

* 📁 **[lib/](lib/_index.md)** — Flutter-App: Screens, DB, Repositories, Providers, Routing.
* 📁 **[packages/](packages/_index.md)** — `redpanda_light_client` – P2P-Netzwerk-Stack (Kademlia, TCP, Krypto).

## Plattformen

* `android/` — Android-Build-Konfiguration (Gradle, Manifest).
* `ios/` — iOS-Build-Konfiguration (Xcode, CocoaPods).
* `web/` — Web-Build (PWA-Manifest, Drift-Worker, sqlite3.wasm).
* `linux/`, `macos/`, `windows/` — Desktop-Build-Konfigurationen (CMake/Xcode).

## Konfiguration

* 📄 **pubspec.yaml** — Flutter-Projekt `redpanda`. Key-Dependencies: Riverpod,
  GoRouter, Drift, qr_flutter, mobile_scanner, redpanda_light_client.
* 📄 **analysis_options.yaml** — Dart-Linting-Regeln.

## Architektur

Riverpod für State-Management, GoRouter für Navigation, Drift-ORM für
SQLite-Persistenz. Das `redpanda_light_client`-Paket läuft in einem
Hintergrund-Isolate und stellt Streams für Verbindungsstatus und Peer-Count
bereit.
