# CLAUDE.md — Project Instructions

## Before Every Push

Run the **Pre-Push Validation** skill (`.claude/skills/pre-push-validation/SKILL.md`)
before every `report_progress` call. This mirrors the CI pipeline exactly and catches
formatting, analysis, and test failures before they reach GitHub Actions.

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

> No push is allowed without a successful run of all steps.
> On failure: fix the problem and re-run the validation.

## Flutter / Dart Versions

CI uses Flutter stable channel (`flutter-version: '3.x'`), currently resolving to
**Flutter 3.41.2 / Dart 3.11.0**. Use this exact version for formatting to avoid
style drift.
