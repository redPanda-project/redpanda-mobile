---
name: Pre-Push Validation
description: >
  Mirrors the Flutter CI pipeline exactly. Run this before every push to
  catch formatting, analysis, and test failures locally — avoiding red CI runs.
---

# Pre-Push Validation

## Purpose

This skill reproduces every step of `.github/workflows/flutter_ci.yml`
so failures are caught **before** pushing to GitHub.

## When to Run

Run this skill **before every `report_progress`** (which commits and pushes).
If any step fails, fix the issue before pushing.

## Pipeline Steps

Execute these steps **in order**. Stop on the first failure.

### 0. Environment Setup

Flutter must be available. The CI uses `flutter-version: '3.x'` on the
`stable` channel (currently resolves to **Flutter 3.41.2 / Dart 3.11.0**).

```bash
# If flutter is not already on PATH:
curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.2-stable.tar.xz \
  | tar xJ -C /opt/
export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"
```

### 1. Install Dependencies (Light Client)

```bash
cd packages/redpanda_light_client
flutter pub get
```

### 2. Check Formatting (Light Client)

```bash
cd packages/redpanda_light_client
dart format --output=none --set-exit-if-changed .
```

> **Important:** This checks ALL files in the directory, not just changed files.
> If any file has formatting issues (including pre-existing ones from main),
> this step fails.

### 3. Analyze (Light Client)

```bash
cd packages/redpanda_light_client
flutter analyze
```

> **Important:** `flutter analyze` treats `info` level issues as errors
> (exit code 1). Common issues:
> - `unnecessary_string_interpolations` — use `'ab' * 20` not `'${'ab' * 20}'`
> - `non_abstract_class_inherits_abstract_member` — protobuf classes need `clone()` and `copyWith()`
> - `use_super_parameters` — use `super.v` instead of positional → `super(v, n)`

### 4. Run Tests (Light Client)

```bash
cd packages/redpanda_light_client
flutter test
```

> E2E tests with `@Tags(['e2e'])` are skipped if the backend JAR is not present.

### 5. Install Dependencies (App)

```bash
cd <repo_root>
flutter pub get
```

### 6. Check Formatting (App)

```bash
cd <repo_root>
dart format --output=none --set-exit-if-changed .
```

### 7. Generate Code (App)

```bash
cd <repo_root>
dart run build_runner build --delete-conflicting-outputs
```

> This regenerates `database.g.dart` and other generated files. If the generated
> output differs from what's committed, the next analyze step may fail.

### 8. Analyze (App)

```bash
cd <repo_root>
flutter analyze
```

### 9. Run Tests (App)

```bash
cd <repo_root>
if [ -d "test" ]; then flutter test; else echo "No test directory, skipping."; fi
```

## Quick-Run Script

Copy-paste this to run all steps at once:

```bash
export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"
REPO_ROOT="/home/runner/work/redpanda-mobile/redpanda-mobile"

set -e  # Stop on first error

echo "=== 1. pub get (light client) ==="
cd "$REPO_ROOT/packages/redpanda_light_client" && flutter pub get

echo "=== 2. dart format (light client) ==="
dart format --output=none --set-exit-if-changed .

echo "=== 3. flutter analyze (light client) ==="
flutter analyze

echo "=== 4. flutter test (light client) ==="
flutter test

echo "=== 5. pub get (app) ==="
cd "$REPO_ROOT" && flutter pub get

echo "=== 6. dart format (app) ==="
dart format --output=none --set-exit-if-changed .

echo "=== 7. build_runner (app) ==="
dart run build_runner build --delete-conflicting-outputs

echo "=== 8. flutter analyze (app) ==="
flutter analyze

echo "=== 9. flutter test (app) ==="
if [ -d "test" ]; then flutter test; else echo "No tests."; fi

echo "✅ All checks passed!"
```

## Common Failure Patterns

| Symptom | Fix |
|---------|-----|
| `dart format` shows changed files | Run `dart format .` in the affected directory |
| `unnecessary_string_interpolations` | Replace `'${expr}'` with `expr` when expr is already a String |
| `non_abstract_class_inherits_abstract_member` | Add `clone()` and `copyWith()` to protobuf `GeneratedMessage` subclasses |
| `use_super_parameters` | Use `super.paramName` instead of positional forwarding |
| `build_runner` output differs | Commit the regenerated `.g.dart` files |
