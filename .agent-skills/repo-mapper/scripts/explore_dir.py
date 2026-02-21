#!/usr/bin/env python3
"""Iterative Context Mapper – explores a directory one level at a time.

Usage:
    python scripts/explore_dir.py [path]

If *path* is omitted the current working directory is used.
Output is Markdown-formatted so an agent (or human) can easily navigate.
"""

import os
import sys

# Directories that are always skipped (boilerplate / generated content).
IGNORED_DIRS = {
    ".git",
    "node_modules",
    "venv",
    ".venv",
    "__pycache__",
    "dist",
    "build",
    ".idea",
}

MAX_DEPTH = 1  # 0 = target dir only, 1 = one level deeper


def explore(base_path: str, max_depth: int = MAX_DEPTH) -> None:
    """Print the contents of *base_path* up to *max_depth* levels deep."""
    base_path = os.path.normpath(base_path)

    if not os.path.isdir(base_path):
        print(f"Error: '{base_path}' is not a valid directory.")
        sys.exit(1)

    print(f"## Contents of `{base_path}/`\n")

    _walk(base_path, base_path, current_depth=0, max_depth=max_depth)


def _walk(root: str, current: str, current_depth: int, max_depth: int) -> None:
    """Recursively list *current* up to *max_depth* levels below *root*."""
    try:
        entries = sorted(os.listdir(current))
    except PermissionError:
        print(f"{'  ' * current_depth}* ⛔ Permission denied: `{current}`")
        return

    indent = "  " * current_depth

    for entry in entries:
        full_path = os.path.join(current, entry)

        if os.path.isdir(full_path):
            if entry in IGNORED_DIRS:
                continue
            # Show the folder and a hint how to drill down.
            dir_rel = os.path.relpath(full_path, start=".")
            print(
                f"{indent}* 📁 {entry}/ "
                f"(Führe `python .agent-skills/repo-mapper/scripts/explore_dir.py {dir_rel}/` "
                f"aus, um tiefer zu gehen)"
            )
            if current_depth < max_depth:
                _walk(root, full_path, current_depth + 1, max_depth)
        else:
            # Render the file as a clickable Markdown link.
            file_rel = os.path.relpath(full_path, start=".")
            print(f"{indent}* 📄 [{entry}](./{file_rel})")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    explore(target)
