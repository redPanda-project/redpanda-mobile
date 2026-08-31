# CLAUDE.md — Project Instructions

## Before Every Push

Run `tool/pre_push_validation.sh` (the **Pre-Push Validation** skill,
`.claude/skills/pre-push-validation/SKILL.md`) before every `report_progress` call.
It mirrors the CI pipeline step by step (the node-backed E2E suites are opt-in
via `--with-e2e` — **required** when `packages/redpanda_light_client/lib` or
`test/e2e` changed, since CI always runs them) and catches formatting, analysis,
and test failures before they reach GitHub Actions. A pass is exit code 0 **and**
the last line `PRE_PUSH_VALIDATION_OK` — never reconstruct the steps as an
ad-hoc `cmd | tail && echo OK` chain, and never pipe the script itself into
`tail`: a pipe swallows the failing exit code (TD048). The script prints the
local toolchain version; that, not the pinned version text further down (stale
until T98), is what your formatting ran on.

## Key Rules

- **dart format**: CI checks ALL files in `packages/redpanda_light_client/` and the
  project root — not just changed files. Always format entire directories.
- **flutter analyze**: Treats `info` level lint issues as errors (exit code 1).
- **Protobuf classes**: Every `GeneratedMessage` subclass needs `clone()` and
  `copyWith()` methods annotated with `@$core.Deprecated`.
- **build_runner**: App uses Drift ORM. Run `dart run build_runner build
  --delete-conflicting-outputs` before analyze to regenerate `database.g.dart`.

## Validation Steps Summary

1. **Light Client** (`packages/redpanda_light_client`):
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `flutter analyze` → `flutter test --exclude-tags e2e` → `flutter test --tags e2e --concurrency=1` (E2E: `--with-e2e`)

2. **Main App** (project root):
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze` → `flutter test`

> No push is allowed without a successful run of all steps
> (`tool/pre_push_validation.sh` exits 0 and prints `PRE_PUSH_VALIDATION_OK`).
> On failure: fix the problem and re-run the validation.

## Flutter / Dart Versions

CI uses Flutter stable channel (`flutter-version: '3.x'`), currently resolving to
**Flutter 3.47.1 / Dart 3.13.1**. Use this exact version for formatting to avoid
style drift. Both manifests declare `environment.sdk: ^3.12.0` (matching
`pubspec.lock`'s `sdks.dart: >=3.12.0 <4.0.0`), so a toolchain below Dart 3.12
cannot resolve this repo at all.
