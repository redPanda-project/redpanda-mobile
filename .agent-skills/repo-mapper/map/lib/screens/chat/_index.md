# 📂 lib/screens/chat/

> Chat-Funktionalität: Nachrichten senden/empfangen und Channel-Sharing per QR-Code.

## Dateien

* 📄 **chat_screen.dart** — Haupt-Chat-UI (`ChatScreen`, ConsumerStatefulWidget).
  Zeigt Nachrichten-Liste mit Auto-Scroll, Eingabefeld und Senden-Button.
  Nutzt `messagesStreamProvider`, `channelProvider`, `dbProvider`.
  AppBar mit Channel-Info und QR-Sharing-Button.

* 📄 **share_qr_dialog.dart** — Dialog-Widget (`ShareChannelDialog`, StatelessWidget)
  zum Anzeigen eines QR-Codes für Channel-Sharing. Zeigt QR-Code via `qr_flutter`
  und den rohen Channel-Code als selektierbaren Text.
