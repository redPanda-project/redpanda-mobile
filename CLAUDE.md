# Agent-Regeln für RedPanda Mobile

## Pflicht: Pre-Push Validation

**Vor jedem Push** muss der Agent die vollständige Pre-Push-Validation
durchführen. Die Schritte sind in
`.claude/skills/pre-push-validation/SKILL.md` dokumentiert.

Kurzfassung der Pflichtschritte:

1. **Light Client** (`packages/redpanda_light_client`):
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `flutter analyze` → `flutter test`

2. **Haupt-App** (Projekt-Root):
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze` → `flutter test`

> Ohne erfolgreichen Durchlauf aller Schritte darf **kein Push** erfolgen.
> Bei Fehlern: Problem beheben und Validierung wiederholen.
