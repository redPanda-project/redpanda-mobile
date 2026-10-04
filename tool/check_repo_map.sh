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
# Not checked: backticked bare file names without "/", globs (`dir/*.ext`), paths with a suffix
# such as `lib/x.dart:12`, and whether the map lists every file (curation,
# see SKILL.md).
# Exit 0 = clean, 1 = dead paths found (listed on stderr).
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
MAP="$REPO_ROOT/.claude/skills/repo-mapper/map"
[ -d "$MAP" ] || { echo "repo map not found: $MAP" >&2; exit 1; }

dead=0
report() { echo "DEAD in ${1#"$REPO_ROOT"/}: $2" >&2; dead=1; }

# kind <repo-relative path>: prints "file" for a tracked file, "dir" for a
# directory containing tracked files, nothing otherwise. Uses the index (git,
# not the working tree: untracked/ignored leftovers must not hide a dead entry;
# also case-exact on macOS) AND the working tree (a file deleted with plain
# `rm` is still in the index).
kind() {
  local p="${1%/}" out
  case "$p" in ''|.|..|./*|../*|*/.|*/..|*/./*|*/../*) return 0 ;; esac
  [ -e "$REPO_ROOT/$p" ] || return 0
  out="$(git -C "$REPO_ROOT" ls-files -- ":(literal)$p")"
  [ -n "$out" ] || return 0
  if [ "$out" = "$p" ]; then echo file; else echo dir; fi
}

# grep that treats "no match" (1) as success but still fails on errors (2).
grep_ok() { grep "$@" || [ $? -eq 1 ]; }

# No mapfile/arrays: must run under macOS' stock bash 3.2 too. Every list is
# captured into a variable first (so set -e sees sed/grep failures, which a
# `< <(…)` process substitution would swallow) and then read via a here-string
# (which also covers a last line without a trailing newline).
index_list="$(find "$MAP" -name '_index.md' | sort)"
[ -n "$index_list" ] || { echo "no _index.md under $MAP" >&2; exit 1; }
count=0

entry_re='^[[:space:]]*\*[[:space:]]*(📄|📁)[[:space:]]*\*\*\[?([^]*()]+)\]?(\([^)]*\))?\*\*.*'

while IFS= read -r index; do
  count=$((count + 1))
  map_dir="$(dirname "$index")"
  rel="${map_dir#"$MAP"}"; rel="${rel#/}"
  prefix="${rel:+$rel/}"

  # Entries: "<emoji> <name>"; 📄 must be a tracked file, 📁 a tracked directory.
  entries="$(sed -nE "s/$entry_re/\1 \2/p" "$index")"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    icon="${entry%% *}"; name="${entry#* }"
    k="$(kind "$prefix$name")"
    case "$icon:$k" in
      📄:file|📁:dir) ;;
      *) report "$index" "entry $icon '$name' (${k:-not tracked}: $prefix$name)" ;;
    esac
  done <<< "$entries"

  # Every 📄/📁 occurrence must be a parsed entry (one per line), or it went unchecked.
  bullets="$(grep_ok -oE '(📄|📁)' "$index" | wc -l | tr -d ' ')"
  shaped="$(grep_ok -cE "$entry_re" "$index")"
  [ "$bullets" -eq "$shaped" ] \
    || report "$index" "$((bullets - shaped)) 📄/📁 occurrence(s) not in the one-per-line '* 📄 **name**' shape, so unchecked"

  # Links to other map files (anchors stripped).
  links="$(grep_ok -oE '\]\([^)#]+\.md(#[^)]*)?\)' "$index" | sed -E 's/^\]\(([^)#]*).*$/\1/')"
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    [ -e "$map_dir/$link" ] || report "$index" "link '$link'"
  done <<< "$links"

  # Backticked relative paths like `tool/sync_protos.sh` (routes such as `/chat/:id` are skipped).
  paths="$(grep_ok -oE '`[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/[A-Za-z0-9_-]+\.[A-Za-z0-9]+`' "$index" | tr -d '`')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -n "$(kind "$prefix$p")" ] || [ -n "$(kind "$p")" ] || report "$index" "path \`$p\`"
  done <<< "$paths"
done <<< "$index_list"

if [ "$dead" -ne 0 ]; then
  echo "repo map has dead paths — update .claude/skills/repo-mapper/map (see its SKILL.md)" >&2
  exit 1
fi
echo "repo map: no dead paths ($count index files)"
