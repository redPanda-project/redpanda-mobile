---
name: Pre-Push Validation
description: >
  Mirrors the Flutter CI pipeline exactly. Run this before every push to
  catch formatting, analysis, and test failures locally — avoiding red CI runs.
  No push is allowed without a successful run.
---

# Pre-Push Validation

## Purpose

This skill reproduces every step of `.github/workflows/flutter_ci.yml`
so failures are caught **before** pushing to GitHub.

> **Rule:** Always run this validation **before** pushing or committing
> changes. Do not skip any step.

## When to Run

Run this skill **before every `report_progress`** (which commits and pushes).
If any step fails, fix the issue before pushing.

---

## Pipeline Steps

Execute these steps **in order**. On any failure, stop immediately,
fix the problem, and restart the validation from the beginning.

### 0. Environment Setup

Flutter must be on `PATH`. Locally the toolchain lives in `~/tools/flutter`
(`export PATH=~/tools/flutter/bin:$PATH`). CI uses `flutter-version: '3.x'` on
the `stable` channel, i.e. whatever the **latest stable** is at run time — keep
the local Flutter on current stable (`flutter upgrade`) so `dart format` agrees
with CI (formatter output changes between Dart minor versions).

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

> **Important:** Formatting checks ALL files in the directory, not just changed files.
> If any file has formatting issues (including pre-existing ones from main),
> this step fails — and it must be allowed to: never wrap it in a pipe or
> `|| true` (see Quick-Run Script).

> **Important:** `flutter analyze` treats `info` level issues as errors
> (exit code 1). Common issues:
> - `unnecessary_string_interpolations` — use `'ab' * 20` not `'${'ab' * 20}'`
> - `non_abstract_class_inherits_abstract_member` — protobuf classes need `clone()` and `copyWith()`
> - `use_super_parameters` — use `super.v` instead of positional → `super(v, n)`

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
if [ -d "test" ]; then flutter test; else echo "No test directory, skipping."; fi
```

> This regenerates `database.g.dart` and other generated files. If the generated
> output differs from what's committed, the next analyze step may fail.

---

## Quick-Run Script

**Use the checked-in script — do not hand-roll a shell chain:**

```bash
export PATH=~/tools/flutter/bin:$PATH   # local toolchain; CI installs its own
tool/pre_push_validation.sh             # full run (E2E suites opt-in: --with-e2e)
```

The script runs the steps above in CI order with `set -euo pipefail`, stops at
the first failure and prints exactly one verdict as its last line:
`PRE_PUSH_VALIDATION_OK` or `PRE_PUSH_VALIDATION_FAILED: <step>`. Its exit code
is the verdict; nothing else is.

> **Why a script (TD048, 2026-08-18):** an ad-hoc chain like
> `dart format --set-exit-if-changed . | tail -3 && echo OK` reports OK even
> when `dart format` fails, because a pipeline returns the status of its LAST
> command (`tail`). Same for `cmd 2>&1 | grep …`. If you must post-process
> output, run the script and read its final line — never pipe the individual
> steps.

Flags: `--with-e2e` also runs the node-backed E2E suites exactly as CI does
(needs `references/redPandaj/target/redpanda.jar`); `--skip-tests` is a quick
format/analyze/build_runner loop while iterating and is **not** sufficient
before a push.

---

## Common Failure Patterns

| Symptom | Fix |
|---------|-----|
| `dart format` shows changed files | Run `dart format .` in the affected directory |
| `unnecessary_string_interpolations` | Replace `'${expr}'` with `expr` when expr is already a String |
| `non_abstract_class_inherits_abstract_member` | Add `clone()` and `copyWith()` to protobuf `GeneratedMessage` subclasses |
| `use_super_parameters` | Use `super.paramName` instead of positional forwarding |
| `build_runner` output differs | Commit the regenerated `.g.dart` files |
| Analysis errors / warnings | Fix source code, re-run `flutter analyze` |
| Tests fail | Fix tests or adjust code, re-run `flutter test` |

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
