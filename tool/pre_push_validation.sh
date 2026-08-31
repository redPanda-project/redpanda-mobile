#!/usr/bin/env bash
# Pre-push validation — mirrors .github/workflows/flutter_ci.yml step by step.
#
# Usage:  tool/pre_push_validation.sh [--with-e2e] [--skip-tests]
#
#   --with-e2e    also run the node-backed E2E suites (CI ALWAYS runs them;
#                 locally they are opt-in because they take ~20 min and need
#                 a backend JAR + Java 21). Required before pushing anything
#                 that touches packages/redpanda_light_client/lib or test/e2e.
#   --skip-tests  formatting + analysis + build_runner only (quick loop while
#                 iterating; NOT sufficient before a push). Cannot be combined
#                 with --with-e2e.
#
# Verdict contract: the LAST line of output is exactly one of
#   PRE_PUSH_VALIDATION_OK
#   PRE_PUSH_VALIDATION_FAILED: <step>
# and the exit code is 0 only for OK (usage/toolchain errors exit 2, a failing
# step exits with that step's status). Check BOTH — and never do
# `tool/pre_push_validation.sh | tail -1; echo $?`: a pipeline returns the
# status of its last command (tail), which is exactly how a failing
# `dart format --set-exit-if-changed` was reported as OK on 2026-08-18 (TD048).
# Safe pattern for capturing output:
#   tool/pre_push_validation.sh 2>&1 | tee validation.log; rc=${PIPESTATUS[0]}

if [ -z "${BASH_VERSION:-}" ]; then
  echo "PRE_PUSH_VALIDATION_FAILED: must run under bash (sh/dash lacks pipefail)" >&2
  exit 2
fi
set -euo pipefail

fail_usage() {
  echo "PRE_PUSH_VALIDATION_FAILED: $1" >&2
  exit 2
}

WITH_E2E=0
SKIP_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --with-e2e)   WITH_E2E=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    -h|--help)    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail_usage "unknown argument: $arg (see --help)" ;;
  esac
done
if [ "$WITH_E2E" -eq 1 ] && [ "$SKIP_TESTS" -eq 1 ]; then
  fail_usage "--with-e2e and --skip-tests contradict each other"
fi

# Resolve symlinks without `readlink -f` (absent on macOS/BSD).
resolve_path() {
  local p="$1" t
  while [ -L "$p" ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
  done
  printf '%s\n' "$p"
}
SCRIPT_PATH="$(resolve_path "$0")"
REPO_ROOT="$(git -C "$(dirname "$SCRIPT_PATH")" rev-parse --show-toplevel)"
PKG_DIR="$REPO_ROOT/packages/redpanda_light_client"
CURRENT_STEP="(startup)"

on_error() {
  local rc=$?
  echo
  echo "PRE_PUSH_VALIDATION_FAILED: $CURRENT_STEP" >&2
  exit "$rc"
}
trap on_error ERR

step() {
  CURRENT_STEP="$1"
  echo
  echo "=== $CURRENT_STEP ==="
}

# --- Toolchain --------------------------------------------------------------
command -v flutter >/dev/null 2>&1 \
  || fail_usage "flutter not on PATH (local toolchain: export PATH=~/tools/flutter/bin:\$PATH)"
command -v dart >/dev/null 2>&1 || fail_usage "dart not on PATH"

# No `cmd | head -1` here: under pipefail a SIGPIPE from the producer would
# fail the whole run. Capture, then print the first line.
step "0. toolchain"
FLUTTER_VER="$(flutter --version)"
echo "${FLUTTER_VER%%$'\n'*}"
dart --version
# The toolchain version is NOT duplicated here — it is read out of the CI
# workflow, which is the single source of truth (T98). A local Flutter that
# differs from the pin makes this whole validation meaningless: `dart format`
# changes its output between Dart releases, so it would either reformat
# untouched files locally or let CI reformat them after the push.
CI_WORKFLOW="$REPO_ROOT/.github/workflows/flutter_ci.yml"
PINNED_FLUTTER="$(sed -n "s/^[[:space:]]*flutter-version:[[:space:]]*['\"]\{0,1\}\([0-9][^'\" ]*\)['\"]\{0,1\}[[:space:]]*$/\1/p" "$CI_WORKFLOW" | head -1)"
[ -n "$PINNED_FLUTTER" ] \
  || fail_usage "cannot read the flutter-version pin from $CI_WORKFLOW (T98)"
LOCAL_FLUTTER="$(flutter --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$LOCAL_FLUTTER" ] \
  || LOCAL_FLUTTER="$(printf '%s' "${FLUTTER_VER%%$'\n'*}" | awk '{print $2}')"
echo "CI pin (flutter_ci.yml): $PINNED_FLUTTER — local: $LOCAL_FLUTTER"
[ "$LOCAL_FLUTTER" = "$PINNED_FLUTTER" ] \
  || fail_usage "local Flutter $LOCAL_FLUTTER != CI pin $PINNED_FLUTTER. Install the pinned version — do NOT 'flutter upgrade' (that moves you further off the pin). To move the pin, bump it in both workflows + CLAUDE.md + the pre-push-validation skill in one PR (T98)."

if [ "$WITH_E2E" -eq 1 ]; then
  command -v java >/dev/null 2>&1 \
    || fail_usage "--with-e2e needs java on PATH (CI: Temurin 21; local: export PATH=~/tools/jdk/bin:\$PATH)"
  JAVA_VER="$(java -version 2>&1)"
  echo "${JAVA_VER%%$'\n'*}"
  JAR=""
  for cand in "$REPO_ROOT/references/redPandaj/target/redpanda.jar" "$REPO_ROOT/redpandaj/target/redpanda.jar"; do
    if [ -s "$cand" ]; then JAR="$cand"; break; fi
  done
  # The E2E suites SKIP (not fail) when the JAR is missing, so an absent JAR
  # would otherwise yield a hollow PRE_PUSH_VALIDATION_OK.
  [ -n "$JAR" ] || fail_usage "--with-e2e needs a non-empty backend JAR at references/redPandaj/target/redpanda.jar (or redpandaj/target/redpanda.jar); CI downloads the latest redpandaj release: gh release download latest --repo redPanda-project/redpandaj --pattern redpanda.jar --dir references/redPandaj/target"
  echo "E2E backend JAR: $JAR ($(wc -c < "$JAR" | tr -d ' ') bytes)"
  ls -l "$JAR"
  echo "NOTE: CI always uses the LATEST redpandaj release; make sure this JAR is current."
fi

TREE_BEFORE="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)"

# --- Light client package ---------------------------------------------------
step "cd packages/redpanda_light_client"
cd "$PKG_DIR"

step "1. pub get (light client)"
flutter pub get

step "2. dart format --set-exit-if-changed (light client)"
dart format --output=none --set-exit-if-changed .

step "3. flutter analyze (light client)"
flutter analyze

E2E_NOTE=""
if [ "$SKIP_TESTS" -eq 0 ]; then
  step "4. flutter test --exclude-tags e2e (light client)"
  flutter test --exclude-tags e2e

  if [ "$WITH_E2E" -eq 1 ]; then
    step "4b. flutter test --tags e2e --concurrency=1 (light client)"
    flutter test --tags e2e --concurrency=1
  else
    E2E_NOTE="E2E suites NOT run (CI runs them) — pass --with-e2e for CI parity"
  fi
else
  E2E_NOTE="tests skipped via --skip-tests — NOT sufficient before a push"
fi

# --- App ---------------------------------------------------------------------
step "cd repo root"
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

# --- Side effects ------------------------------------------------------------
TREE_AFTER="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)"
if [ "$TREE_BEFORE" != "$TREE_AFTER" ]; then
  echo
  echo "NOTE: this run changed tracked files (toolchain rewrite, see TD050) — review before committing:"
  diff <(echo "$TREE_BEFORE") <(echo "$TREE_AFTER") | grep '^>' | sed 's/^> /  /' || true
fi

echo
[ -z "$E2E_NOTE" ] || echo "WARNING: $E2E_NOTE"
echo "PRE_PUSH_VALIDATION_OK"
