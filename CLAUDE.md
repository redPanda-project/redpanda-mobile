# CLAUDE.md — Project Instructions

## Before Every Push

Run `tool/pre_push_validation.sh` (the **Pre-Push Validation** skill,
`.claude/skills/pre-push-validation/SKILL.md`) before every `report_progress` call.
It mirrors the CI pipeline exactly and catches formatting, analysis, and test
failures before they reach GitHub Actions. Its exit code / last line
(`PRE_PUSH_VALIDATION_OK`) is the only valid verdict — never reconstruct the
steps as an ad-hoc `cmd | tail && echo OK` chain, a pipe swallows the failing
exit code (TD048).

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
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `flutter analyze` → `flutter test`

2. **Main App** (project root):
   `flutter pub get` → `dart format --output=none --set-exit-if-changed .` → `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze` → `flutter test`

> No push is allowed without a successful run of all steps
> (`tool/pre_push_validation.sh` exits 0 and prints `PRE_PUSH_VALIDATION_OK`).
> On failure: fix the problem and re-run the validation.

## Flutter / Dart Versions

CI uses Flutter stable channel (`flutter-version: '3.x'`), currently resolving to
**Flutter 3.41.2 / Dart 3.11.0**. Use this exact version for formatting to avoid
style drift.
