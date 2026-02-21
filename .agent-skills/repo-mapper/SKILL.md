---
name: Iterative Context Mapper
description: >
  Hilft dem Agenten, ein Projekt Ebene für Ebene zu verstehen, ohne das
  Kontextfenster zu sprengen. Gibt immer nur den Inhalt eines einzelnen
  Verzeichnisses (plus eine Ebene tiefer) aus.
---

# Iterative Context Mapper

## Wann diesen Skill nutzen?

Nutze diesen Skill **immer**, wenn du die Ordnerstruktur eines Projekts
verstehen musst – zum Beispiel, bevor du eine Datei suchst, bearbeitest oder
eine neue Komponente anlegst.

> **Wichtig:** Lies niemals den gesamten Dateibaum auf einmal ein.
> Arbeite dich stattdessen **iterativ** (Drill-Down-Prinzip) Ebene für Ebene
> in die Ordnerstruktur vor.

## Workflow

1. **Starte immer im Root-Verzeichnis**, indem du das Skript ohne Parameter
   aufrufst:

   ```bash
   python .agent-skills/repo-mapper/scripts/explore_dir.py
   ```

2. **Analysiere die Ausgabe.** Entscheide logisch, welcher Ordner für deine
   aktuelle Aufgabe relevant ist.

3. **Rufe das Skript erneut auf**, diesmal mit dem Pfad des relevanten Ordners,
   um tiefer in den Baum zu gelangen (Drill-Down):

   ```bash
   python .agent-skills/repo-mapper/scripts/explore_dir.py src/components/
   ```

4. **Wiederhole das**, bis du die exakten Dateien gefunden hast, die du lesen
   oder bearbeiten musst.

## Ausgabeformat

* Ordner werden als Navigationspunkte dargestellt – die Ausgabe zeigt dir
  direkt den Befehl, um tiefer zu gehen.
* Dateien werden als Markdown-Links ausgegeben.
* Boilerplate-Ordner (`.git`, `node_modules`, `__pycache__` usw.) werden
  automatisch herausgefiltert.
