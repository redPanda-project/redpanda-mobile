# 📂 lib/database/

> Drift-ORM-Datenbankschema und generierter Code.

## Dateien

* 📄 **database.dart** — Datenbank-Schema (`AppDatabase`, Drift).
  4 Tabellen: `Users` (uuid, username, avatarUrl, publicKey),
  `Channels` (uuid, label, encryptionKey, authenticationKey, lastSeen),
  `Messages` (conversationId, senderId, content, timestamp, status, type),
  `Peers` (address, nodeId, averageLatencyMs, successCount, failureCount, lastSeen).
  Schema-Version 5 mit Migrations-Logik. SQLite-Backend mit Web-Support.

* 📄 **database.g.dart** — Von Drift generierter Code (Companion-Klassen,
  Queries). Nicht manuell bearbeiten.
