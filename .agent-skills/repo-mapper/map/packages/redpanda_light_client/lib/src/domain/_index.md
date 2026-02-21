# 📂 packages/redpanda_light_client/lib/src/domain/

> Domain-Objekte: Channel und verschlüsselte Nachrichten.

## Dateien

* 📄 **channel.dart** — Repräsentiert einen sicheren Kommunikationskanal (`Channel`).
  Shared AES-256 Encryption- und Authentication-Keys. Serialisierbar zu/von JSON
  für QR-Code-Sharing. Channel-ID wird via SHA256-Hash der Keys berechnet.

* 📄 **garlic_message_wrapper.dart** — Wrapper für verschlüsselte GarlicMessage-Protos.
  Verwendet ECDH + AES/CTR/NoPadding für Payload-Verschlüsselung, ECDSA zum Signieren.
  `create()` verschlüsselt, `decrypt()` entschlüsselt auf Empfängerseite.
