#!/usr/bin/env bash
# Checks that the repo-mapper map (.claude/skills/repo-mapper/map) names no
# dead paths (TD100/T130). map/<dir>/_index.md describes <dir>, so
#   - every "* 📄 **name**" / "* 📁 **name/**" / "* 📁 **[name/](…)**" entry must be
#     tracked by git under <dir> (git, not the working tree: an untracked or
#     ignored leftover must not hide a dead entry; also case-exact on macOS),
#   - every 📄/📁 bullet must have that shape (anything else would go unchecked),
#   - every markdown link to a *.md file must point at an existing map file,
#   - every backticked relative path with a "/" and a file extension must be
#     tracked relative to <dir> or the repo root.
# Not checked: backticked bare file names without "/", and whether the map
# lists every file (that is curation, see SKILL.md).
# Exit 0 = clean, 1 = dead paths found (listed on stderr).
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
MAP="$REPO_ROOT/.claude/skills/repo-mapper/map"
[ -d "$MAP" ] || { echo "repo map not found: $MAP" >&2; exit 1; }

dead=0
report() { echo "DEAD in ${1#"$REPO_ROOT"/}: $2" >&2; dead=1; }

# tracked <repo-relative path>: a tracked file, or a directory containing one.
tracked() {
  [ -n "$(git -C "$REPO_ROOT" ls-files -- ":(literal)${1%/}")" ]
}

# grep that treats "no match" (1) as success but still fails on errors (2).
grep_ok() { grep "$@" || [ $? -eq 1 ]; }

# No mapfile/arrays: must run under macOS' stock bash 3.2 too.
index_list="$(find "$MAP" -name '_index.md' | sort)"
[ -n "$index_list" ] || { echo "no _index.md under $MAP" >&2; exit 1; }
count=0

entry_re='^[[:space:]]*\*[[:space:]]*(📄|📁)[[:space:]]*\*\*\[?([^]*()]+)\]?(\([^)]*\))?\*\*.*'

while IFS= read -r index; do
  count=$((count + 1))
  map_dir="$(dirname "$index")"
  rel="${map_dir#"$MAP"}"; rel="${rel#/}"
  prefix="${rel:+$rel/}"

  while IFS= read -r name; do
    tracked "$prefix$name" || report "$index" "entry '$name' (not tracked: $prefix$name)"
  done < <(sed -nE "s/$entry_re/\2/p" "$index")

  bullets="$(grep_ok -cE '(📄|📁)' "$index")"
  shaped="$(grep_ok -cE "$entry_re" "$index")"
  [ "$bullets" -eq "$shaped" ] \
    || report "$index" "$((bullets - shaped)) 📄/📁 line(s) not in the '* 📄 **name**' shape, so unchecked"

  while IFS= read -r link; do
    [ -e "$map_dir/$link" ] || report "$index" "link '$link'"
  done < <(grep_ok -oE '\]\([^)]+\.md\)' "$index" | sed -E 's/^\]\((.*)\)$/\1/')

  # Backticked relative paths like `tool/sync_protos.sh` (routes such as `/chat/:id` are skipped).
  while IFS= read -r p; do
    tracked "$prefix$p" || tracked "$p" || report "$index" "path \`$p\`"
  done < <(grep_ok -oE '`[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/[A-Za-z0-9_-]+\.[A-Za-z0-9]+`' "$index" | tr -d '`')
done <<< "$index_list"

if [ "$dead" -ne 0 ]; then
  echo "repo map has dead paths — update .claude/skills/repo-mapper/map (see its SKILL.md)" >&2
  exit 1
fi
echo "repo map: no dead paths ($count index files)"
