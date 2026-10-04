#!/usr/bin/env bash
# Checks that the repo-mapper map (.claude/skills/repo-mapper/map) names no
# dead paths (TD100/T130). map/<dir>/_index.md describes <dir>, so
#   - every "📄 **name**" / "📁 **name/**" / "📁 **[name/](…)**" entry must exist in <dir>,
#   - every markdown link to a *.md file must point at an existing map file,
#   - every backticked relative path containing a "/" and a file extension
#     must exist relative to <dir>, one of its parents, or the repo root.
# It does NOT check that the map lists every file (that is a curation job).
# Exit 0 = clean, 1 = dead paths found (listed on stderr).
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
MAP="$REPO_ROOT/.claude/skills/repo-mapper/map"
[ -d "$MAP" ] || { echo "repo map not found: $MAP" >&2; exit 1; }

dead=0
report() { echo "DEAD in ${1#"$REPO_ROOT"/}: $2" >&2; dead=1; }

# exists_upwards <dir> <relpath>: true if <relpath> exists below <dir> or any parent up to the repo root.
exists_upwards() {
  local d="$1"
  while :; do
    [ -e "$d/$2" ] && return 0
    [ "$d" = "$REPO_ROOT" ] && return 1
    d="$(dirname "$d")"
  done
}

while IFS= read -r index; do
  map_dir="$(dirname "$index")"
  rel="${map_dir#"$MAP"}"
  code_dir="$REPO_ROOT$rel"

  # Entry names: "* 📄 **name**", "* 📁 **name/**", "* 📁 **[name/](link)**".
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ -e "$code_dir/$name" ] || report "$index" "entry '$name' (no $code_dir/$name)"
  done < <(sed -nE 's/^[[:space:]]*\*[[:space:]]*(📄|📁)[[:space:]]*\*\*\[?([^]*()]+)\]?(\([^)]*\))?\*\*.*/\2/p' "$index")

  # Links to other map files.
  while IFS= read -r link; do
    [ -e "$map_dir/$link" ] || report "$index" "link '$link'"
  done < <(grep -oE '\]\([^)]+\.md\)' "$index" | sed -E 's/^\]\((.*)\)$/\1/' || true)

  # Backticked relative paths like `tool/sync_protos.sh` (routes such as `/chat/:id` are skipped).
  while IFS= read -r p; do
    exists_upwards "$code_dir" "$p" || report "$index" "path \`$p\`"
  done < <(grep -oE '`[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/[A-Za-z0-9_-]+\.[A-Za-z0-9]+`' "$index" | tr -d '`' || true)
done < <(find "$MAP" -name '_index.md' | sort)

if [ "$dead" -ne 0 ]; then
  echo "repo map has dead paths — update .claude/skills/repo-mapper/map (see its SKILL.md)" >&2
  exit 1
fi
echo "repo map: no dead paths"
