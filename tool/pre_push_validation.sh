#!/usr/bin/env bash
# Pre-push validation — mirrors .github/workflows/flutter_ci.yml step by step.
#
# Usage:  tool/pre_push_validation.sh [--with-e2e] [--skip-tests]
#
#   --with-e2e    also run the node-backed E2E suites (needs a redpanda.jar
#                 under references/redPandaj/target, ~20 min) — CI always runs
#                 them, locally they are opt-in.
#   --skip-tests  formatting + analysis + build_runner only (quick loop while
#                 iterating; NOT sufficient before a push).
#
# Exit code is non-zero on the first failing step; the LAST line of output is
# either "PRE_PUSH_VALIDATION_OK" or "PRE_PUSH_VALIDATION_FAILED: <step>".
# Never pipe this script's inner commands through `tail`/`grep` in an ad-hoc
# shell chain — that is exactly how a failing `dart format --set-exit-if-changed`
# was reported as OK on 2026-08-18 (TD048): `cmd | tail` returns tail's status.
set -euo pipefail

WITH_E2E=0
SKIP_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --with-e2e)   WITH_E2E=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PKG_DIR="$REPO_ROOT/packages/redpanda_light_client"
CURRENT_STEP="(startup)"

on_error() {
  echo
  echo "PRE_PUSH_VALIDATION_FAILED: $CURRENT_STEP" >&2
  exit 1
}
trap on_error ERR

step() {
  CURRENT_STEP="$1"
  echo
  echo "=== $CURRENT_STEP ==="
}

command -v flutter >/dev/null 2>&1 || {
  echo "flutter not on PATH (local toolchain: export PATH=~/tools/flutter/bin:\$PATH)" >&2
  exit 2
}
command -v dart >/dev/null 2>&1 || { echo "dart not on PATH" >&2; exit 2; }

echo "Toolchain: $(flutter --version 2>/dev/null | head -1)"
echo "           $(dart --version 2>&1)"
echo "CI resolves flutter-version '3.x' on the stable channel = latest stable;"
echo "if your local Dart differs, formatting results may drift from CI (T98)."

# --- Light client package ---------------------------------------------------
cd "$PKG_DIR"

step "1. pub get (light client)"
flutter pub get

step "2. dart format --set-exit-if-changed (light client)"
dart format --output=none --set-exit-if-changed .

step "3. flutter analyze (light client)"
flutter analyze

if [ "$SKIP_TESTS" -eq 0 ]; then
  step "4. flutter test --exclude-tags e2e (light client)"
  flutter test --exclude-tags e2e

  if [ "$WITH_E2E" -eq 1 ]; then
    step "4b. flutter test --tags e2e --concurrency=1 (light client)"
    flutter test --tags e2e --concurrency=1
  else
    echo "(E2E suites skipped — pass --with-e2e to run them like CI does)"
  fi
else
  echo "(tests skipped via --skip-tests)"
fi

# --- App ---------------------------------------------------------------------
cd "$REPO_ROOT"

step "5. pub get (app)"
flutter pub get

step "6. dart format --set-exit-if-changed (app)"
dart format --output=none --set-exit-if-changed .

step "7. build_runner (app)"
dart run build_runner build --delete-conflicting-outputs

step "8. flutter analyze (app)"
flutter analyze

if [ "$SKIP_TESTS" -eq 0 ]; then
  step "9. flutter test (app)"
  if [ -d test ]; then
    flutter test
  else
    echo "No test directory found, skipping tests."
  fi
fi

echo
echo "PRE_PUSH_VALIDATION_OK"
