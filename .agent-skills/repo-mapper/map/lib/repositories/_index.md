# 📂 lib/repositories/

> Datenzugriffsschicht (Repository-Pattern) für Domain-Objekte.

## Dateien

* 📄 **channel_repository.dart** — Channel-Repository (`ChannelRepository`
  Interface + `DriftChannelRepository` Implementierung). Mappt Domain-`Channel`
  zu/von Drift-Modellen, konvertiert Encryption-Keys zu/von Hex.
  Bietet `getChannels()`, `addChannel()`, `watchChannels()`.
  Exponiert `channelRepositoryProvider` und `channelsProvider` (StreamProvider).
