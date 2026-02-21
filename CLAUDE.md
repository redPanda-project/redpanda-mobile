# Agent Rules for RedPanda Mobile

## Required: Pre-Push Validation

**Before every push** the agent must run the full pre-push validation.
The steps are documented in
`.claude/skills/pre-push-validation/SKILL.md`.

Summary of required steps:

1. **Light Client** (`packages/redpanda_light_client`):
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `flutter analyze` → `flutter test`

2. **Main App** (project root):
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze` → `flutter test`

> No push is allowed without a successful run of all steps.
> On failure: fix the problem and re-run the validation.
