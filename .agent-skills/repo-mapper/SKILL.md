---
name: Iterative Context Mapper
description: >
  Persistente Projekt-Map mit Agenten-generierten Zusammenfassungen.
  Die Map lebt als Markdown-Dateien unter map/ und wird vom Agenten
  selbst gepflegt – nicht durch ein Skript.
---

# Iterative Context Mapper

## Zweck

Diese Map gibt dir **sofort** Kontext über jede Datei und jeden Ordner
im Projekt, ohne dass du die Quelldateien öffnen musst.

Die Map liegt unter `.agent-skills/repo-mapper/map/` und spiegelt die
relevante Projektstruktur wider.

## Aufbau

```
map/
├── _index.md              ← Root-Zusammenfassung
├── lib/
│   ├── _index.md          ← Zusammenfassung von lib/
│   ├── screens/
│   │   ├── _index.md      ← Zusammenfassung von lib/screens/
│   │   └── chat.md        ← Detail-Summary für lib/screens/chat/
│   …
└── packages/
    └── redpanda_light_client/
        └── _index.md
```

### Regeln

* Jeder Ordner bekommt eine `_index.md`.
* Tiefe Blatt-Ordner (z. B. `lib/screens/chat/`) bekommen eine **Detail-Summary**
  mit Datei-für-Datei-Zusammenfassungen.
* Eltern-Ordner (z. B. `lib/screens/`) fassen die Kinder **kürzer** zusammen.
* Je höher in der Hierarchie, desto **stärker komprimiert** die Zusammenfassung.
* Die Root `_index.md` ist eine **High-Level-Übersicht** des gesamten Projekts
  (max. 15–20 Zeilen).

## Workflow – Lesen (Drill-Down)

1. Lies `.agent-skills/repo-mapper/map/_index.md`.
2. Entscheide, welcher Ordner relevant ist.
3. Öffne dessen `_index.md` für mehr Detail.
4. Wiederhole, bis du die Datei gefunden hast.

## Workflow – Map erzeugen / aktualisieren

> **Wichtig:** Du (der Agent) erzeugst die Map selbst. Es gibt kein Skript.
> Du liest die Quelldateien, fasst sie zusammen und schreibst die Map-Dateien.

### Schritt 1 – Ordnerstruktur ermitteln

Nutze `view` oder `glob` um die Verzeichnisse zu sehen.
Ignoriere dabei: `.git`, `node_modules`, `.dart_tool`, `build`, `dist`,
`.pub-cache`, `.pub`, `.venv`, `__pycache__`, `.idea`.

Scanne nur relevante Ordner: `lib/`, `packages/`, `integration_test/`,
sowie Root-Konfigurationsdateien.

Plattform-Ordner (`android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`)
nur als Einzeiler in der Root `_index.md` erwähnen – **nicht** tief scannen.

### Schritt 2 – Dateien lesen und zusammenfassen (Bottom-Up)

Arbeite **von den Blättern nach oben**:

1. **Datei lesen:** Öffne jede Quelldatei (z. B. `lib/screens/chat/chat_screen.dart`).
2. **Zusammenfassung schreiben:** Erstelle pro Datei einen kurzen Absatz:
   - Was macht die Datei?
   - Welche Klassen / Widgets / Funktionen / Providers sind enthalten?
   - Welche Abhängigkeiten / Imports sind relevant?
3. **Blatt-`_index.md` schreiben:** Sammle alle Datei-Zusammenfassungen eines
   Ordners in dessen `_index.md` unter `map/`.

### Schritt 3 – Eltern-Ordner zusammenfassen (Bubble-Up)

4. **Eltern-`_index.md`:** Fasse die Kind-`_index.md`-Dateien zu einer
   **kürzeren** Zusammenfassung zusammen.  
   Beispiel: `map/lib/screens/_index.md` enthält einen Einzeiler pro
   Screen-Unterordner statt alle Datei-Details.
5. **Wiederhole nach oben**, bis du bei `map/_index.md` (Root) ankommst.
   Die Root-Zusammenfassung ist **maximal 15–20 Zeilen**.

### Schritt 4 – Committe die Map

Committe alle `map/`-Dateien zusammen mit deinen Code-Änderungen.

### Wann aktualisieren?

* Wenn du eine Datei **erstellst, löschst, verschiebst oder inhaltlich
  wesentlich änderst**, aktualisiere die betroffene `_index.md` und alle
  Eltern bis zur Root.
* Für eine Komplett-Neugeneration: Lösche `map/` und führe Schritte 1–4 aus.

## Format der `_index.md`

```markdown
# 📂 ordner/

> Kurze Zusammenfassung (1-2 Sätze) was dieser Ordner beinhaltet.

## Unterordner

* 📁 **unter-ordner/** — Einzeiler was dort zu finden ist.

## Dateien

* 📄 **datei.dart** — Was die Datei macht, welche Klassen/Widgets/Providers.
```

## Beispiel

`map/lib/screens/chat/_index.md`:
```markdown
# 📂 lib/screens/chat/

> Chat-Funktionalität: Nachrichten senden/empfangen und QR-Code-Sharing.

## Dateien

* 📄 **chat_screen.dart** — Haupt-Chat-UI. ConsumerWidget mit Nachrichten-
  Liste, Eingabefeld und AppBar. Nutzt channelProvider und redPandaClientProvider.
* 📄 **share_qr_dialog.dart** — Dialog zum Teilen des eigenen Public Keys als
  QR-Code. Nutzt qr_flutter.
```

`map/lib/screens/_index.md`:
```markdown
# 📂 lib/screens/

> Alle App-Screens: Onboarding, Home, Chat, Channel-Verwaltung, Debug.

## Unterordner

* 📁 **chat/** — Chat-UI und QR-Code-Sharing.
* 📁 **channels/** — Screens zum Erstellen und Beitreten von Channels.
* 📁 **home/** — Hauptbildschirm mit Channel-Liste.
* 📁 **onboarding/** — Ersteinrichtung / Benutzername setzen.

## Dateien

* 📄 **debug_peer_stats_screen.dart** — Debug-Screen für Peer-Statistiken.
```
