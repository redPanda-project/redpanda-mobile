# 📂 packages/redpanda_light_client/lib/src/domain/

> Domain-Objekte des Light Clients: Channel, OH-Deskriptoren, ACKs, Gruppen und die
> typisierten `StateUpdate`-Events (T110).

## Dateien

* 📄 **channel.dart** — Repräsentiert einen sicheren Kommunikationskanal (`Channel`).
  Shared AES-256 Encryption- und Authentication-Keys. Serialisierbar zu/von JSON
  für QR-Code-Sharing. Channel-ID wird via SHA256-Hash der Keys berechnet.

* 📄 **channel_doctor_report.dart** — `ChannelDoctorReport`/`DoctorStage`/`DoctorStatus`: Ampel-Ergebnis des Verbindungs-Doctors (T25).

* 📄 **counterpart_oh_update.dart** — `CounterpartOhUpdate`: authentifizierte In-Band-Ankündigung neuer Gegenüber-OHs (T21/T42).

* 📄 **decrypted_message.dart** — `DecryptedMessage`: aus einer OH-Mailbox geholte, entschlüsselte Nachricht.

* 📄 **garlic_session_update.dart** — `GarlicSessionUpdate`: Reverse-Garlic-Session-Snapshot eines Kanals (MS05).

* 📄 **group_state.dart** — `GroupMemberInfo`, `GroupRegistration`, `GroupStateUpdate`, `GroupHandshakeEvent` (MS08).

* 📄 **loopback_result.dart** — `LoopbackResult`: Ergebnis des Loopback-Selbsttests (T20).

* 📄 **oh_descriptor.dart** — `OHDescriptor`: Endpoint + oh_id + Public Key eines Outbound Handles.

* 📄 **oh_fetch_status.dart** — `OhFetchStatus`: Ergebnis eines Mailbox-Fetch-Versuchs.

* 📄 **oh_mailbox_update.dart** — `OhMailboxUpdate`: Cursor-/Expiry-Änderung eines eigenen OHs.

* 📄 **oh_registration.dart** — `OHRegistration`: registrierter eigener Outbound Handle.

* 📄 **rendezvous_state_update.dart** — `RendezvousStateUpdate`: T44-Rendezvous-Merge-Zustand eines Kanals.

* 📄 **reverse_garlic_block.dart** — `ReverseGarlicBlock`: Reply-Pfad-Deskriptor (MS05) inkl. proto3-Codec.

* 📄 **routing_ack.dart** — `RoutingAck`, `RoutingAckUpdate`, `ChannelAckUpdate` (MS06).

* 📄 **send_exceptions.dart** — `DepositException`, `RateLimitException`, `UnknownCounterpartException` (MS02b).

* 📄 **state_update.dart** — `StateUpdate`-Basistyp des einen State-Kanals (`stateUpdates`), dazu `NodeScoreUpdate`, `OwnOhSetUpdate`.
