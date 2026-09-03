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
#   tool/sync_protos.sh                        # sync from a local redpandaj checkout
#   tool/sync_protos.sh --source DIR           # ... from an explicit checkout
#   tool/sync_protos.sh --ref REF              # ... from GitHub at tag/branch/commit REF
#   tool/sync_protos.sh --check                # verify only, write nothing
#   tool/sync_protos.sh --check --no-upstream  # only the offline integrity check
#
# Source resolution order (unless --ref forces a download):
#   --source DIR  >  $REDPANDAJ_DIR  >  <repo>/../redpandaj  >  GitHub (main)
#
# The set of vendored files is DISCOVERED from the source, not hard-coded, so a
# schema added or removed upstream shows up as drift instead of being missed.
#
# Two independent checks, both run by --check:
#   (A) integrity — the vendored files are exactly the ones listed in
#       protos/UPSTREAM.lock and still hash to it. Offline, always runs.
#       Catches hand-edits of the vendored copies.
#   (B) freshness — the vendored files still equal the upstream source.
#       Needs a source (local checkout or network); skipped with a notice if
#       neither is reachable. `--no-upstream` skips it explicitly.
#
# After a sync that changed anything, regenerate the Dart code:
#   tool/generate_protos.sh
set -euo pipefail

REPO="redPanda-project/redpandaj"
UPSTREAM_PROTO_DIR="src/main/proto"

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

# GNU coreutils ships `sha256sum`, macOS only `shasum`. Both print
# "<hash>  <name>"; `sha256sum -c` is deliberately NOT used because its
# --quiet/--ignore-missing flags are GNU-only.
if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$@"; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_of() { shasum -a 256 "$@"; }
else
  die "neither sha256sum nor shasum found — cannot hash the vendored protos"
fi

# Sorted basenames of the *.proto files in a directory (empty if there are none).
protos_in() {
  find "$1" -maxdepth 1 -name '*.proto' -type f -exec basename {} \; | LC_ALL=C sort
}
# Sorted file names recorded in UPSTREAM.lock.
lock_names() {
  awk '/^#/ { next } NF >= 2 { print $2 }' "$LOCK" | LC_ALL=C sort
}
lock_hash_of() {
  awk -v want="$1" '/^#/ { next } NF >= 2 && $2 == want { print $1; exit }' "$LOCK"
}

# --- (A) integrity: vendored files vs. the checked-in hashes ----------------
check_integrity() {
  [ -f "$LOCK" ] || die "missing $LOCK — run tool/sync_protos.sh to create it"
  local listed on_disk f expected actual
  listed="$(lock_names)"
  on_disk="$(protos_in "$VENDOR_DIR")"
  [ -n "$listed" ] || die "UPSTREAM.lock lists no protos"
  if [ "$listed" != "$on_disk" ]; then
    echo "sync_protos: UPSTREAM.lock lists:" >&2
    printf '  %s\n' $listed >&2
    echo "sync_protos: protos/ contains:" >&2
    printf '  %s\n' $on_disk >&2
    die "the vendored set and UPSTREAM.lock disagree — re-run tool/sync_protos.sh"
  fi
  while IFS= read -r f; do
    expected="$(lock_hash_of "$f")"
    actual="$(cd "$VENDOR_DIR" && sha256_of "$f" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || die "protos/$f does not match UPSTREAM.lock
     (expected $expected, got $actual) — it was edited by hand.
     The schemas are owned by $REPO; edit them there, then re-run
     tool/sync_protos.sh && tool/generate_protos.sh"
  done <<< "$listed"
  echo "protos: integrity OK ($(printf '%s\n' "$listed" | wc -l | tr -d ' ') files match UPSTREAM.lock)"
}

# --- source resolution ------------------------------------------------------
STAGE=""
# Must return 0: this runs as the EXIT trap, whose status can override the
# script's own exit code.
cleanup() { [ -n "$STAGE" ] && rm -rf "$STAGE"; return 0; }
trap cleanup EXIT

SOURCE_DESC=""
UPSTREAM_COMMIT=""

stage_from_dir() {
  local dir="$1" sha branch dirty=""
  [ -d "$dir/$UPSTREAM_PROTO_DIR" ] || return 1
  [ -n "$(protos_in "$dir/$UPSTREAM_PROTO_DIR")" ] || return 1
  STAGE="$(mktemp -d)"
  cp "$dir/$UPSTREAM_PROTO_DIR"/*.proto "$STAGE/"
  if sha="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"; then
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    git -C "$dir" diff --quiet -- "$UPSTREAM_PROTO_DIR" 2>/dev/null || dirty=" DIRTY"
    UPSTREAM_COMMIT="$sha"
    SOURCE_DESC="$dir @ ${sha:0:12} ($branch)$dirty"
  else
    # No SHA to pin. Fine for --check (which only compares content), fatal for a
    # sync — see the guard before write_lock below.
    UPSTREAM_COMMIT=""
    SOURCE_DESC="$dir (not a git checkout)"
  fi
  return 0
}

stage_from_github() {
  local ref="${1:-main}" sha names f
  command -v gh >/dev/null 2>&1 || return 1
  sha="$(gh api "repos/$REPO/commits/$ref" --jq .sha 2>/dev/null)" || return 1
  names="$(gh api "repos/$REPO/contents/$UPSTREAM_PROTO_DIR?ref=$sha" \
             --jq '.[] | select(.type == "file") | .name' 2>/dev/null \
           | grep '\.proto$' | LC_ALL=C sort)" || return 1
  [ -n "$names" ] || return 1
  STAGE="$(mktemp -d)"
  while IFS= read -r f; do
    gh api "repos/$REPO/contents/$UPSTREAM_PROTO_DIR/$f?ref=$sha" \
       -H 'Accept: application/vnd.github.raw' > "$STAGE/$f" || return 1
  done <<< "$names"
  UPSTREAM_COMMIT="$sha"
  SOURCE_DESC="github:$REPO @ ${sha:0:12} (ref $ref)"
  return 0
}

resolve_source() {
  if [ -n "$REF" ]; then
    stage_from_github "$REF" && return 0
    return 1
  fi
  local candidates=() c
  [ -n "$SOURCE_DIR" ] && candidates+=("$SOURCE_DIR")
  [ -n "${REDPANDAJ_DIR:-}" ] && candidates+=("$REDPANDAJ_DIR")
  candidates+=("$REPO_ROOT/../redpandaj")
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
    (cd "$VENDOR_DIR" && sha256_of $(protos_in "$VENDOR_DIR"))
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
  vendored="$(protos_in "$VENDOR_DIR")"
  upstream="$(protos_in "$STAGE")"
  if [ "$vendored" != "$upstream" ]; then
    echo "protos: the vendored set differs from $SOURCE_DESC" >&2
    echo "  vendored: $(printf '%s ' $vendored)" >&2
    echo "  upstream: $(printf '%s ' $upstream)" >&2
    drift=1
  fi
  while IFS= read -r f; do
    [ -f "$STAGE/$f" ] || continue
    if ! diff -u "$VENDOR_DIR/$f" "$STAGE/$f" > /dev/null; then
      echo "protos: DRIFT in $f (vendored vs. $SOURCE_DESC)" >&2
      diff -u "$VENDOR_DIR/$f" "$STAGE/$f" >&2 || true
      drift=1
    fi
  done <<< "$vendored"
  if [ "$drift" -ne 0 ]; then
    die "vendored protos differ from upstream.
     Fix: tool/sync_protos.sh && tool/generate_protos.sh, then commit both."
  fi
  echo "protos: in sync with $SOURCE_DESC"
  exit 0
fi

resolve_source || die "no proto source found (tried --source/\$REDPANDAJ_DIR/../redpandaj/GitHub)"
# A lock without a real commit SHA is rejected by vendored_protos_test.dart, so
# refuse to write one instead of producing a lock that fails CI.
[ -n "$UPSTREAM_COMMIT" ] || die "$SOURCE_DESC has no commit to pin.
     Use a real redpandaj clone, or --ref <tag|branch|sha> to fetch from GitHub."

before="$(cd "$VENDOR_DIR" && sha256_of $(protos_in "$VENDOR_DIR") 2>/dev/null || true)"
rm -f "$VENDOR_DIR"/*.proto
cp "$STAGE"/*.proto "$VENDOR_DIR/"
write_lock
after="$(cd "$VENDOR_DIR" && sha256_of $(protos_in "$VENDOR_DIR"))"

echo "protos: synced from $SOURCE_DESC"
if [ "$before" != "$after" ]; then
  echo "protos: schemas CHANGED — run tool/generate_protos.sh and commit the regenerated Dart."
else
  echo "protos: no schema change."
fi
