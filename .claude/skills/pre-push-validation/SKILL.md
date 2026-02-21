---
name: Pre-Push Validation
description: >
  Runs all CI pipeline checks locally before code is pushed.
  This skill MUST be executed before every push – no push is allowed
  without a successful run.
---

# Pre-Push Validation

## Purpose

This skill mirrors exactly the steps of the GitHub Actions pipeline
(`flutter_ci.yml`). It ensures that **no code is pushed that would
break the pipeline**.

> **Rule:** Always run this validation **before** pushing or committing
> changes. Do not skip any step.

---

## Validation Steps

Execute the steps **in order**. On any failure, stop immediately,
fix the problem, and restart the validation from the beginning.

### 1 · Light Client Package (`packages/redpanda_light_client`)

```bash
# 1a) Install dependencies
cd packages/redpanda_light_client
flutter pub get

# 1b) Check formatting
dart format --output=none --set-exit-if-changed .

# 1c) Static analysis
flutter analyze

# 1d) Run tests
flutter test
```

### 2 · Main App (Project Root)

```bash
# 2a) Install dependencies
cd ../../  # Back to project root
flutter pub get

# 2b) Check formatting
dart format --output=none --set-exit-if-changed .

# 2c) Code generation (Drift, Freezed, etc.)
dart run build_runner build --delete-conflicting-outputs

# 2d) Static analysis
flutter analyze

# 2e) Run tests (if test/ directory exists)
if [ -d "test" ]; then flutter test; fi
```

---

## Error Handling

| Error | Action |
|-------|--------|
| Formatting fails | Run `dart format .`, then re-check |
| Analysis errors / warnings | Fix source code, re-run `flutter analyze` |
| Tests fail | Fix tests or adjust code, re-run `flutter test` |
| build_runner fails | Resolve conflicts in generated files, re-run generation |

## Checklist

Use this checklist to track progress:

- [ ] Light Client: `flutter pub get`
- [ ] Light Client: `dart format --output=none --set-exit-if-changed .`
- [ ] Light Client: `flutter analyze`
- [ ] Light Client: `flutter test`
- [ ] App: `flutter pub get`
- [ ] App: `dart format --output=none --set-exit-if-changed .`
- [ ] App: `dart run build_runner build --delete-conflicting-outputs`
- [ ] App: `flutter analyze`
- [ ] App: `flutter test` (if test/ exists)

**Only when all items are ✅ may you push.**
