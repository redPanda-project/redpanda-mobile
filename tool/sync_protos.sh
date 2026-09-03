#!/usr/bin/env bash
# Vendor the protobuf schemas from redpandaj into the Dart light client.
#
# redpandaj (`src/main/proto/*.proto`) is the SINGLE source of truth for the
# wire schemas — the Dart copies under
# `packages/redpanda_light_client/protos/` are vendored artefacts, never edited
# by hand (DDD review 2026-08-31 §6 P0 / T107: the old hand-maintained copy had
# drifted three milestones behind the generated code).
#
# Usage:
#   tool/sync_protos.sh                      # sync from a local redpandaj checkout
#   tool/sync_protos.sh --source DIR         # ... from an explicit checkout
#   tool/sync_protos.sh --ref REF            # ... from GitHub at tag/branch/commit REF
#   tool/sync_protos.sh --check              # verify only, write nothing
#   tool/sync_protos.sh --check --no-upstream  # only the offline integrity check
#
# Source resolution order (unless --ref forces a download):
#   --source DIR  >  $REDPANDAJ_DIR  >  <repo>/../redpandaj  >  GitHub (main)
#
# Two independent checks, both run by --check:
#   (A) integrity — the vendored files still hash to protos/UPSTREAM.lock.
#       Offline, always runs. Catches hand-edits of the vendored copies.
#   (B) freshness — the vendored files still equal the upstream source.
#       Needs a source (local checkout or network); skipped with a notice if
#       neither is reachable. `--no-upstream` skips it explicitly.
#
# After a sync that changed anything, regenerate the Dart code:
#   tool/generate_protos.sh
set -euo pipefail

REPO="redPanda-project/redpandaj"
UPSTREAM_PROTO_DIR="src/main/proto"
PROTO_FILES=(commands.proto outbound.proto)

CHECK_ONLY=0
SKIP_UPSTREAM=0
SOURCE_DIR=""
REF=""

die() { echo "sync_protos: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check)       CHECK_ONLY=1 ;;
    --no-upstream) SKIP_UPSTREAM=1 ;;
    --source)      shift; [ $# -gt 0 ] || die "--source needs a directory"; SOURCE_DIR="$1" ;;
    --ref)         shift; [ $# -gt 0 ] || die "--ref needs a git ref"; REF="$1" ;;
    -h|--help)     sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; exit 0 ;;
    *)             die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

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
VENDOR_DIR="$REPO_ROOT/packages/redpanda_light_client/protos"
LOCK="$VENDOR_DIR/UPSTREAM.lock"

[ -d "$VENDOR_DIR" ] || die "vendor directory not found: $VENDOR_DIR"

# --- (A) integrity: vendored files vs. the checked-in hashes ----------------
check_integrity() {
  [ -f "$LOCK" ] || die "missing $LOCK — run tool/sync_protos.sh to create it"
  local f
  for f in "${PROTO_FILES[@]}"; do
    [ -f "$VENDOR_DIR/$f" ] || die "vendored proto missing: protos/$f"
    grep -q "  $f\$" "$LOCK" || die "protos/$f has no entry in UPSTREAM.lock"
  done
  if ! (cd "$VENDOR_DIR" && sha256sum --quiet -c "$(basename "$LOCK")"); then
    die "vendored protos do not match UPSTREAM.lock — they were edited by hand.
     The schemas are owned by $REPO; edit them there, then re-run
     tool/sync_protos.sh && tool/generate_protos.sh"
  fi
  echo "protos: integrity OK (${#PROTO_FILES[@]} files match UPSTREAM.lock)"
}

# --- source resolution ------------------------------------------------------
STAGE=""
# Must return 0: this runs as the EXIT trap, whose status can override the
# script's own exit code.
cleanup() { [ -n "$STAGE" ] && rm -rf "$STAGE"; return 0; }
trap cleanup EXIT

SOURCE_DESC=""

stage_from_dir() {
  local dir="$1" f sha branch dirty=""
  for f in "${PROTO_FILES[@]}"; do
    [ -f "$dir/$UPSTREAM_PROTO_DIR/$f" ] || return 1
  done
  STAGE="$(mktemp -d)"
  for f in "${PROTO_FILES[@]}"; do cp "$dir/$UPSTREAM_PROTO_DIR/$f" "$STAGE/$f"; done
  if sha="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"; then
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    git -C "$dir" diff --quiet -- "$UPSTREAM_PROTO_DIR" 2>/dev/null || dirty=" DIRTY"
    UPSTREAM_COMMIT="$sha"
    SOURCE_DESC="$dir @ ${sha:0:12} ($branch)$dirty"
  else
    UPSTREAM_COMMIT="unknown"
    SOURCE_DESC="$dir (not a git checkout)"
  fi
  return 0
}

stage_from_github() {
  local ref="${1:-main}" f
  command -v gh >/dev/null 2>&1 || return 1
  local sha
  sha="$(gh api "repos/$REPO/commits/$ref" --jq .sha 2>/dev/null)" || return 1
  STAGE="$(mktemp -d)"
  for f in "${PROTO_FILES[@]}"; do
    gh api "repos/$REPO/contents/$UPSTREAM_PROTO_DIR/$f?ref=$sha" \
       -H 'Accept: application/vnd.github.raw' > "$STAGE/$f" || return 1
  done
  UPSTREAM_COMMIT="$sha"
  SOURCE_DESC="github:$REPO @ ${sha:0:12} (ref $ref)"
  return 0
}

resolve_source() {
  if [ -n "$REF" ]; then
    stage_from_github "$REF" && return 0
    return 1
  fi
  local candidates=()
  [ -n "$SOURCE_DIR" ] && candidates+=("$SOURCE_DIR")
  [ -n "${REDPANDAJ_DIR:-}" ] && candidates+=("$REDPANDAJ_DIR")
  candidates+=("$REPO_ROOT/../redpandaj")
  local c
  for c in "${candidates[@]}"; do
    [ -d "$c" ] || continue
    stage_from_dir "$c" && return 0
  done
  [ -n "$SOURCE_DIR" ] && die "no protos under $SOURCE_DIR/$UPSTREAM_PROTO_DIR"
  stage_from_github main && return 0
  return 1
}

write_lock() {
  {
    echo "# Vendored protobuf schemas — DO NOT EDIT."
    echo "# Source of truth: $REPO $UPSTREAM_PROTO_DIR/"
    echo "# Sync: tool/sync_protos.sh   Verify: tool/sync_protos.sh --check"
    echo "# Codegen after a sync: tool/generate_protos.sh"
    echo "# upstream-commit: $UPSTREAM_COMMIT"
    (cd "$VENDOR_DIR" && sha256sum "${PROTO_FILES[@]}")
  } > "$LOCK"
}

if [ "$CHECK_ONLY" -eq 1 ]; then
  check_integrity
  if [ "$SKIP_UPSTREAM" -eq 1 ]; then
    echo "protos: upstream comparison skipped (--no-upstream)"
    exit 0
  fi
  if ! resolve_source; then
    echo "protos: upstream comparison SKIPPED — no redpandaj checkout and no network/gh." >&2
    echo "        Integrity against UPSTREAM.lock passed; freshness unverified." >&2
    exit 0
  fi
  drift=0
  for f in "${PROTO_FILES[@]}"; do
    if ! diff -u "$VENDOR_DIR/$f" "$STAGE/$f" > /dev/null; then
      echo "protos: DRIFT in $f (vendored vs. $SOURCE_DESC)" >&2
      diff -u "$VENDOR_DIR/$f" "$STAGE/$f" >&2 || true
      drift=1
    fi
  done
  if [ "$drift" -ne 0 ]; then
    die "vendored protos differ from upstream.
     Fix: tool/sync_protos.sh && tool/generate_protos.sh, then commit both."
  fi
  echo "protos: in sync with $SOURCE_DESC"
  exit 0
fi

resolve_source || die "no proto source found (tried --source/\$REDPANDAJ_DIR/../redpandaj/GitHub)"
changed=0
for f in "${PROTO_FILES[@]}"; do
  if ! cmp -s "$VENDOR_DIR/$f" "$STAGE/$f" 2>/dev/null; then changed=1; fi
  cp "$STAGE/$f" "$VENDOR_DIR/$f"
done
write_lock
echo "protos: synced from $SOURCE_DESC"
if [ "$changed" -ne 0 ]; then
  echo "protos: schemas CHANGED — run tool/generate_protos.sh and commit the regenerated Dart."
else
  echo "protos: no schema change."
fi
