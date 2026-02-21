# 📂 packages/redpanda_light_client/lib/src/security/

> Verschlüsselungsschicht: ECDH-Schlüsselaustausch und AES-Cipher.

## Dateien

* 📄 **encryption_manager.dart** — Ableitung von AES/CTR-Cipher-Paaren aus
  ECDH-Shared-Secret und Zufallsbytes (`EncryptionManager`). Separate
  Send-/Receive-Cipher mit eigenen Keys und IVs. `encrypt()` / `decrypt()`.
