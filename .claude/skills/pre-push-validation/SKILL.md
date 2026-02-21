---
name: Pre-Push Validation
description: >
  Führt alle CI-Pipeline-Checks lokal aus, bevor Code gepusht wird.
  Diese Skill MUSS vor jedem Push ausgeführt werden – ohne erfolgreichen
  Durchlauf darf kein Push erfolgen.
---

# Pre-Push Validation

## Zweck

Dieser Skill spiegelt exakt die Schritte der GitHub-Actions-Pipeline
(`flutter_ci.yml`) wider. Er stellt sicher, dass **kein Code gepusht wird,
der die Pipeline brechen würde**.

> **Regel:** Führe diese Validierung **immer** aus, bevor du Änderungen
> pushst oder committest. Überspringe keinen Schritt.

---

## Validierungsschritte

Führe die Schritte **der Reihe nach** aus. Brich bei einem Fehler sofort ab,
behebe das Problem und starte die Validierung erneut.

### 1 · Light-Client-Paket (`packages/redpanda_light_client`)

```bash
# 1a) Abhängigkeiten installieren
cd packages/redpanda_light_client
flutter pub get

# 1b) Formatierung prüfen
dart format --output=none --set-exit-if-changed .

# 1c) Statische Analyse
flutter analyze

# 1d) Tests ausführen
flutter test
```

### 2 · Haupt-App (Projekt-Root)

```bash
# 2a) Abhängigkeiten installieren
cd ../../  # Zurück zum Projekt-Root
flutter pub get

# 2b) Formatierung prüfen
dart format --output=none --set-exit-if-changed .

# 2c) Code-Generierung (Drift, Freezed, etc.)
dart run build_runner build --delete-conflicting-outputs

# 2d) Statische Analyse
flutter analyze

# 2e) Tests ausführen (falls test/ Ordner existiert)
if [ -d "test" ]; then flutter test; fi
```

---

## Fehlerbehandlung

| Fehler | Aktion |
|--------|--------|
| Formatierung schlägt fehl | `dart format .` ausführen, dann erneut prüfen |
| Analyse-Fehler / Warnungen | Quellcode korrigieren, erneut `flutter analyze` |
| Tests schlagen fehl | Tests reparieren oder Code anpassen, erneut `flutter test` |
| build_runner schlägt fehl | Konflikte in generierten Dateien lösen, erneut generieren |

## Ablauf als Checkliste

Nutze diese Checkliste, um den Fortschritt zu verfolgen:

- [ ] Light Client: `flutter pub get`
- [ ] Light Client: `dart format --output=none --set-exit-if-changed .`
- [ ] Light Client: `flutter analyze`
- [ ] Light Client: `flutter test`
- [ ] App: `flutter pub get`
- [ ] App: `dart format --output=none --set-exit-if-changed .`
- [ ] App: `dart run build_runner build --delete-conflicting-outputs`
- [ ] App: `flutter analyze`
- [ ] App: `flutter test` (falls test/ vorhanden)

**Erst wenn alle Punkte ✅ sind, darf gepusht werden.**
