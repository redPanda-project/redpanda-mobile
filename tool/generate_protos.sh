#!/usr/bin/env bash
# Regenerate the Dart protobuf code from the vendored schemas.
#
#   packages/redpanda_light_client/protos/*.proto   (vendored, see tool/sync_protos.sh)
#     -> packages/redpanda_light_client/lib/src/generated/*.pb{,enum,json}.dart
#
# The generated files are committed so that neither CI nor a plain
# `flutter pub get` needs protoc. Never hand-edit them: the hand-maintained
# copies were exactly the T107 defect (generated code three milestones ahead of
# the .proto it claimed to come from).
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
OUT_DIR="$PKG_DIR/lib/src/generated"

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
echo "protoc: $("$PROTOC" --version)"
PATH="$PLUGIN_DIR:$PATH" "$PROTOC" \
  --proto_path="$PROTO_DIR" \
  --dart_out="$OUT_DIR" \
  "$PROTO_DIR"/*.proto

# protoc_plugin formats with its own bundled dart_style; re-format with the
# project's pinned Dart so `dart format --set-exit-if-changed` stays green.
dart format "$OUT_DIR" > /dev/null

echo "generated:"
ls -1 "$OUT_DIR"
