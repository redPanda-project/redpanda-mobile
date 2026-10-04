# 📂 packages/redpanda_light_client/lib/src/crypto/

> Kanal-, Gruppen- und OH-Kryptografie (Ed25519/X25519/HKDF/AES-256-GCM), Ratchet und T44-Rendezvous.

## Dateien

* 📄 **channel_message.dart** — `ChannelMessage`: innerer Klartext eines Message-Format-v2-Payloads (proto3-kompatibler Codec).

* 📄 **channel_rendezvous.dart** — `ChannelRendezvous`, `RendezvousEntry`, `SignedRendezvousRecord`: T44-Channel-Rendezvous-DHT-Primitive (Gegenstück zu `ChannelDht` im Backend).

* 📄 **crypto_utils.dart** — `CryptoUtils` + Keypair-Bytes-Typen: Ed25519, X25519, HKDF-SHA256, AES-256-GCM (`cryptography`-Package).

* 📄 **group_control.dart** — `GroupControl`, `KeyRotation`, `GroupInfoUpdate`, `GroupHandshake`: proto3-kompatible Codecs der MS08-Control-Plane.

* 📄 **group_crypto.dart** — `GroupCryptoSession`: Epochen, Chains, Gruppen-Envelopes v5/v6 (MS08).

* 📄 **message_crypto_v3.dart** — `MessageCryptoV3`: Kanal-Envelope v3 (MS03, AES-256-GCM, AAD = Channel-ID).

* 📄 **message_crypto_v4.dart** — `MessageCryptoV4`, `RatchetHeader`: Kanal-Envelope v4 mit Double Ratchet (MS03b).

* 📄 **oh_keypair.dart** — `OHKeypair`: Ed25519-Keypair zum Signieren von OH-Register/Fetch/Ack (MS03).

* 📄 **ratchet.dart** — `RatchetSession`, `RatchetStateUpdate`: Double-Ratchet-Zustand je Kanal (MS03b).

* 📄 **rendezvous_manager.dart** — `RendezvousManager`: T44-Rendezvous-Zustand und Record-Builder (Publish/Refresh/Recovery).
