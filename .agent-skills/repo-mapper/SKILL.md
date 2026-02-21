---
name: Iterative Context Mapper
description: >
  Persistente Projekt-Map, die als Markdown-Dateien im Skill-Verzeichnis
  gespeichert wird. Agenten navigieren iterativ durch die Map-Dateien und
  aktualisieren sie, wenn sich die Projektstruktur ändert.
---

# Iterative Context Mapper

## Wann diesen Skill nutzen?

Nutze diesen Skill **immer**, wenn du die Ordnerstruktur des Projekts
verstehen musst – zum Beispiel, bevor du eine Datei suchst, bearbeitest oder
eine neue Komponente anlegst.

> **Wichtig:** Lies niemals den gesamten Dateibaum auf einmal ein.
> Arbeite dich stattdessen **iterativ** (Drill-Down-Prinzip) Ebene für Ebene
> durch die Map-Dateien in `map/`.

## Aufbau der Map

Die Map liegt unter `.agent-skills/repo-mapper/map/` und spiegelt die
Projektstruktur wider. Jeder Ordner enthält eine `_index.md` mit:

* **Unterordner** – mit relativem Link zur jeweiligen `_index.md`
* **Dateien** – Auflistung aller Dateien **mit destillierten Zusammenfassungen**
  (Klassen, Funktionen, Doc-Kommentare, Zweck der Datei)

Beispiel:

```
map/
├── _index.md          ← Root-Verzeichnis
├── lib/
│   ├── _index.md      ← lib/
│   ├── screens/
│   │   └── _index.md  ← lib/screens/
│   └── …
└── …
```

## Workflow – Lesen (Drill-Down)

1. **Starte immer bei der Root-Map:**

   Lies `.agent-skills/repo-mapper/map/_index.md`.

2. **Analysiere die Ausgabe.** Entscheide logisch, welcher Unterordner für
   deine aktuelle Aufgabe relevant ist.

3. **Öffne die `_index.md` des relevanten Unterordners**, z. B.:

   Lies `.agent-skills/repo-mapper/map/lib/screens/_index.md`.

4. **Wiederhole das**, bis du die exakten Dateien gefunden hast, die du lesen
   oder bearbeiten musst.

## Workflow – Aktualisieren

Wenn du Dateien hinzufügst, löschst oder verschiebst, **musst** du die Map
aktualisieren:

```bash
python .agent-skills/repo-mapper/scripts/update_map.py
```

Das Skript löscht die alte Map und generiert sie komplett neu.
Committe die aktualisierten Map-Dateien zusammen mit deinen Code-Änderungen.

## Filterung

Boilerplate-Ordner werden automatisch ausgeblendet:
`.git`, `node_modules`, `venv`, `.venv`, `__pycache__`, `dist`, `build`,
`.idea`, `.dart_tool`, `.pub-cache`, `.pub`.

## Destillierte Datei-Informationen

Jede Datei in der Map enthält automatisch extrahierte Informationen:

* **Dart:** Klassen, Mixins, Enums, Providers, Top-Level-Funktionen, Doc-Kommentare
* **Python:** Docstrings, Klassen, Funktionen
* **YAML:** Paketname (pubspec), Top-Level-Keys
* **Markdown:** Erste Überschrift
* **Proto:** Messages und Services
* **Config-Dateien:** Typ und Zweck (Gradle, XML, JSON, CMake, …)

So kannst du auf einen Blick sehen, was jede Datei enthält, **ohne sie öffnen
zu müssen**.
