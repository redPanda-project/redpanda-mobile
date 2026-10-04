# 📂 packages/redpanda_light_client/lib/src/garlic/

> Garlic-Routing: Flaschenpost-v2-Pakete, Hop-Auswahl, Node-Scoring, Reverse-Garlic und ACK-Tags.

## Dateien

* 📄 **ack_tag_store.dart** — `AckTagStore`: offene R-ACK-Session-Tags → Nachricht (MS06).

* 📄 **garlic_builder.dart** — `GarlicBuilder`, `GarlicHop`: baut 3-Layer-Flaschenpost-v2-Pakete (fix 2048 B, MS04).

* 📄 **hop_selector.dart** — `HopSelector`: wählt Relay-Hops mit Ausschlüssen und Präfix-Diversität (MS04).

* 📄 **node_scorer.dart** — `NodeScorer`, `NodeScore`: Zuverlässigkeits-Scoring aus R-ACK-Feedback (MS06).

* 📄 **return_path.dart** — `ReturnPathBlock`: Rückpfad-Block eines `CMD_DELIVER_ACKED` (MS06).

* 📄 **rgb_builder.dart** — `RgbBuilder`: baut Reverse Garlic Blocks zum eigenen OH (MS05).

* 📄 **session_tag_store.dart** — `SessionTagStore`: Session-Tag → Kanal für Reverse-Garlic-Replies (MS05).
