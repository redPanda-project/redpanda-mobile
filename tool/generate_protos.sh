#!/usr/bin/env bash
# Regenerate the Dart protobuf code from the vendored and the local schemas.
#
#   packages/redpanda_light_client/protos/*.proto   (vendored, see tool/sync_protos.sh)
#     -> packages/redpanda_light_client/lib/src/generated/*.pb{,enum,json}.dart
#   packages/redpanda_light_client/protos/client/*.proto
#       (client-to-client schemas OWNED by this repo, TD098/T142 — redpandaj
#        deliberately does not model them; edit them here)
#     -> packages/redpanda_light_client/lib/src/generated/client/*.pb{,enum,json}.dart
#
# The two sets stay separate on purpose: tool/sync_protos.sh and
# protos/UPSTREAM.lock only ever look at protos/*.proto (top level), so the
# local schemas under protos/client/ never trip the upstream hash guard.
#
# The generated files are committed so that neither CI nor a plain
# `flutter pub get` needs protoc. Never hand-edit them: the hand-maintained
# copies were exactly the T107 defect (generated code three milestones ahead of
# the .proto it claimed to come from). This script therefore also writes
# `lib/src/generated/CODEGEN.lock` (sha256 per generated file plus the tool
# versions), which `test/unit/vendored_protos_test.dart` verifies — so a
# hand-edit of the generated Dart fails CI the same way a hand-edit of a
# vendored .proto does.
#
# Requirements:
#   * protoc — on PATH, or $PROTOC, or ~/tools/protoc/bin/protoc.
#     These are proto3 schemas, so protoc >= 3.0 is required; any current
#     release (the 3.x line or the later 21+ versioning, e.g. 25.1) works.
#   * protoc_plugin — already a dev_dependency of the package, invoked through
#     `dart run protoc_plugin`, so its version is pinned by pubspec.lock.
#   * flutter/dart on PATH (local toolchain: export PATH=~/tools/flutter/bin:$PATH)
#
# Usage: tool/generate_protos.sh
set -euo pipefail

die() { echo "generate_protos: $*" >&2; exit 1; }

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
PROTO_DIR="$PKG_DIR/protos"
CLIENT_PROTO_DIR="$PROTO_DIR/client"
OUT_DIR="$PKG_DIR/lib/src/generated"
CODEGEN_LOCK="$OUT_DIR/CODEGEN.lock"

# See tool/sync_protos.sh — macOS has shasum, not sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$@"; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_of() { shasum -a 256 "$@"; }
else
  die "neither sha256sum nor shasum found — cannot write CODEGEN.lock"
fi

PROTOC="${PROTOC:-}"
if [ -z "$PROTOC" ]; then
  if command -v protoc >/dev/null 2>&1; then
    PROTOC="$(command -v protoc)"
  elif [ -x "$HOME/tools/protoc/bin/protoc" ]; then
    PROTOC="$HOME/tools/protoc/bin/protoc"
  else
    die "protoc not found — install it or set \$PROTOC"
  fi
fi
command -v dart >/dev/null 2>&1 || die "dart not on PATH (export PATH=~/tools/flutter/bin:\$PATH)"

ls "$PROTO_DIR"/*.proto >/dev/null 2>&1 || die "no vendored protos in $PROTO_DIR (run tool/sync_protos.sh)"
ls "$CLIENT_PROTO_DIR"/*.proto >/dev/null 2>&1 || die "no client protos in $CLIENT_PROTO_DIR"

cd "$PKG_DIR"
dart pub get > /dev/null

# protoc looks for `protoc-gen-dart` on PATH; route it at the pinned
# protoc_plugin from this package's pubspec.lock instead of a global install.
PLUGIN_DIR="$(mktemp -d)"
trap 'rm -rf "$PLUGIN_DIR"' EXIT
cat > "$PLUGIN_DIR/protoc-gen-dart" <<'PLUGIN'
#!/usr/bin/env bash
exec dart run protoc_plugin "$@"
PLUGIN
chmod +x "$PLUGIN_DIR/protoc-gen-dart"

mkdir -p "$OUT_DIR"
# Drop the previous output first: the generated files are committed, so a
# renamed or removed .proto would otherwise leave stale *.pb*.dart behind.
for d in "$OUT_DIR" "$OUT_DIR/client"; do
  rm -f "$d"/*.pb.dart "$d"/*.pbenum.dart "$d"/*.pbjson.dart \
        "$d"/*.pbserver.dart "$d"/*.pbgrpc.dart
done
rm -f "$CODEGEN_LOCK"

PROTOC_VERSION="$("$PROTOC" --version)"
PLUGIN_VERSION="$(awk '/^  protoc_plugin:/ { found = 1 } found && /^    version:/ { gsub(/"/, "", $2); print $2; exit }' "$PKG_DIR/pubspec.lock")"
echo "protoc: $PROTOC_VERSION"
echo "protoc_plugin: ${PLUGIN_VERSION:-unknown} (pubspec.lock)"

PATH="$PLUGIN_DIR:$PATH" "$PROTOC" \
  --proto_path="$PROTO_DIR" \
  --dart_out="$OUT_DIR" \
  "$PROTO_DIR"/*.proto

# Client schemas: compiled relative to protos/ so they land in
# lib/src/generated/client/ (protoc mirrors the proto path in the output).
(cd "$PROTO_DIR" && PATH="$PLUGIN_DIR:$PATH" "$PROTOC" \
  --proto_path=. \
  --dart_out="$OUT_DIR" \
  client/*.proto)

# protoc_plugin formats with its own bundled dart_style; re-format with the
# project's pinned Dart so `dart format --set-exit-if-changed` stays green and
# the hashes below match what CI sees.
dart format "$OUT_DIR" > /dev/null

{
  echo "# Generated protobuf Dart — DO NOT EDIT."
  echo "# Produced by tool/generate_protos.sh from packages/redpanda_light_client/protos/"
  echo "# (vendored *.proto -> ./, local client/*.proto -> client/)."
  echo "# Verified by test/unit/vendored_protos_test.dart: a hand-edit of the"
  echo "# generated code fails CI, which is how the pre-T107 drift stayed invisible."
  echo "# protoc: $PROTOC_VERSION"
  echo "# protoc_plugin: ${PLUGIN_VERSION:-unknown}"
  (cd "$OUT_DIR" && sha256_of $(find . -maxdepth 2 -name '*.dart' -type f | sed 's|^\./||' | LC_ALL=C sort))
} > "$CODEGEN_LOCK"

echo "generated:"
(cd "$OUT_DIR" && find . -maxdepth 2 -name '*.dart' -type f | sed 's|^\./||' | LC_ALL=C sort)
