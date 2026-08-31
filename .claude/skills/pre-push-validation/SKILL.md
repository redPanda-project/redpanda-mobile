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
(`export PATH=~/tools/flutter/bin:$PATH`).

**The local Flutter must match the CI pin exactly.** CI pins one exact version
via `flutter-version:` in `.github/workflows/flutter_ci.yml`; that pin is the
source of truth for this repo (see `CLAUDE.md` → *Flutter / Dart Versions*).
`tool/pre_push_validation.sh` enforces this in step 0: it reads the pin out of
the workflow, prints both versions and aborts with
`PRE_PUSH_VALIDATION_FAILED: local Flutter <x> != CI pin <y>` (exit 2) on a
mismatch. To check by hand, read the version out of the workflow rather than
from memory:

```bash
grep -m1 "flutter-version:" .github/workflows/flutter_ci.yml
flutter --version | head -1   # must report the same version
```

If they differ, this validation is worthless — `dart format` output changes
between Dart releases, so a mismatched toolchain either reformats unrelated
files locally or lets CI reformat them for you. Do **not** `flutter upgrade` to
fix a mismatch: that moves the local side away from the pin. Install the pinned
version, or bump the pin deliberately in its own PR (workflow + `CLAUDE.md` +
this file, plus any repo-wide reformat).

The E2E suites additionally need Java 21 (`~/tools/jdk`, CI: Temurin 21) and a
backend JAR (see `--with-e2e` below).

### 1 · Light Client Package (`packages/redpanda_light_client`)

```bash
# 1a) Install dependencies
cd packages/redpanda_light_client
flutter pub get

# 1b) Check formatting
dart format --output=none --set-exit-if-changed .

# 1c) Static analysis
flutter analyze

# 1d) Unit tests (everything except the node-backed E2E suites)
flutter test --exclude-tags e2e

# 1e) E2E suites — CI always runs these, serially; locally via --with-e2e
flutter test --tags e2e --concurrency=1
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
export PATH=~/tools/flutter/bin:$PATH   # must match the CI pin (see step 0)
tool/pre_push_validation.sh             # full run (E2E suites opt-in: --with-e2e)
```

The script runs the steps above in CI order with `set -euo pipefail`, stops at
the first failure and prints exactly one verdict as its last line:
`PRE_PUSH_VALIDATION_OK` or `PRE_PUSH_VALIDATION_FAILED: <step>` (usage and
toolchain errors also print a `FAILED:` line and exit 2). A pass is **exit 0
AND the `OK` line** — check both.

> **Why a script (TD048, 2026-08-18):** an ad-hoc chain like
> `dart format --set-exit-if-changed . | tail -3 && echo OK` reports OK even
> when `dart format` fails, because a pipeline returns the status of its LAST
> command (`tail`). Same for `cmd 2>&1 | grep …` — and the same trap applies
> to the script itself: `tool/pre_push_validation.sh | tail -1; echo $?`
> prints `tail`'s status. If you need the output in a file, use
>
> ```bash
> tool/pre_push_validation.sh 2>&1 | tee validation.log; rc=${PIPESTATUS[0]}
> ```
>
> and judge by `$rc` plus the last line of `validation.log`.

Flags: `--with-e2e` also runs the node-backed E2E suites (`--tags e2e
--concurrency=1`, like CI). CI **always** runs them; locally they are opt-in
because they take ~20 min — so a default run ends with a `WARNING: E2E suites
NOT run` line before the `OK`. **Pass `--with-e2e` before pushing anything that
touches `packages/redpanda_light_client/lib` or `test/e2e`.** It needs Java 21
and a non-empty backend JAR at `references/redPandaj/target/redpanda.jar` or
`redpandaj/target/redpanda.jar` (the script fails fast if either is missing,
because the suites would otherwise *skip*, not fail); CI always downloads the
latest redpandaj release — keep the local JAR current with
`gh release download latest --repo redPanda-project/redpandaj --pattern redpanda.jar --dir references/redPandaj/target`.
`--skip-tests` is a quick format/analyze/build_runner loop while iterating
and is **not** sufficient before a push.

A newer local Flutter may rewrite `analysis_options.yaml` / `pubspec.lock`
during `pub get`/`analyze` (TD050); the script lists such newly dirtied files at
the end — do not commit them by accident, and never `git checkout --` them
together with real changes.

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
- [ ] Light Client: `flutter test --exclude-tags e2e`
- [ ] Light Client: `flutter test --tags e2e --concurrency=1` (`--with-e2e`; required for lib/ or test/e2e changes)
- [ ] App: `flutter pub get`
- [ ] App: `dart format --output=none --set-exit-if-changed .`
- [ ] App: `dart run build_runner build --delete-conflicting-outputs`
- [ ] App: `flutter analyze`
- [ ] App: `flutter test` (if test/ exists)

**Only when all items are ✅ may you push.**
