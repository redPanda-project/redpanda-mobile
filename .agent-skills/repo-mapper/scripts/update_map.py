#!/usr/bin/env python3
"""update_map.py – Generates / updates the persistent project map.

Usage:
    python .agent-skills/repo-mapper/scripts/update_map.py [project_root]

If *project_root* is omitted, the current working directory is used.

The script walks the project tree (respecting ignore patterns) and writes
one ``_index.md`` file per directory into the ``map/`` folder inside the
repo-mapper skill directory.  Each ``_index.md`` lists the subdirectories
and files of the corresponding project directory.  Every file entry also
includes a **distilled summary** (key classes/functions, doc comments,
purpose) so that an agent gets immediate context without opening the file.
"""

import os
import re
import shutil
import sys
from datetime import datetime, timezone

# ── configuration ────────────────────────────────────────────────────────────

IGNORED_DIRS = {
    ".git",
    "node_modules",
    "venv",
    ".venv",
    "__pycache__",
    "dist",
    "build",
    ".idea",
    ".dart_tool",
    ".pub-cache",
    ".pub",
}

# Binary / non-summarisable extensions.
BINARY_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".svg",
    ".wasm", ".so", ".dll", ".exe", ".zip", ".tar", ".gz",
    ".ttf", ".otf", ".woff", ".woff2",
    ".lock",
}

# Path to the map directory **relative to the project root**.
SKILL_DIR = os.path.join(".agent-skills", "repo-mapper")
MAP_DIR = os.path.join(SKILL_DIR, "map")

MAX_READ_BYTES = 8192  # Only read the first 8 KB of each file.

# ── file analysis ────────────────────────────────────────────────────────────


def _summarise_file(filepath: str) -> str:
    """Return a short distilled summary of *filepath*."""
    ext = os.path.splitext(filepath)[1].lower()
    basename = os.path.basename(filepath)

    if ext in BINARY_EXTENSIONS:
        return "Binärdatei"

    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read(MAX_READ_BYTES)
    except (OSError, UnicodeDecodeError):
        return "Nicht lesbar"

    if not content.strip():
        return "Leer"

    if ext == ".dart":
        return _summarise_dart(content)
    if ext == ".py":
        return _summarise_python(content)
    if ext in (".yaml", ".yml"):
        return _summarise_yaml(content, basename)
    if ext == ".md":
        return _summarise_markdown(content)
    if ext == ".proto":
        return _summarise_proto(content)
    if ext in (".gradle", ".kts"):
        return _summarise_gradle(content)
    if ext == ".xml":
        return _summarise_xml(basename)
    if ext in (".json",):
        return _summarise_json(content, basename)
    if ext in (".sh",):
        return _summarise_shell(content)
    if basename in ("Podfile", "Podfile.lock"):
        return "CocoaPods-Abhängigkeiten"
    if basename == "CMakeLists.txt":
        return "CMake Build-Konfiguration"

    # Fallback: first non-empty line.
    for line in content.splitlines():
        stripped = line.strip()
        if stripped:
            return _truncate(stripped, 120)
    return "—"


# ── language-specific analysers ──────────────────────────────────────────────

_DART_CLASS_RE = re.compile(r"^\s*(?:abstract\s+)?class\s+(\w+)", re.MULTILINE)
_DART_MIXIN_RE = re.compile(r"^\s*mixin\s+(\w+)", re.MULTILINE)
_DART_ENUM_RE = re.compile(r"^\s*enum\s+(\w+)", re.MULTILINE)
_DART_TOP_FN_RE = re.compile(r"^(?:Future<[^>]+>|void|int|String|bool|double|dynamic|[\w<>]+)\s+(\w+)\s*\(", re.MULTILINE)
_DART_DOC_RE = re.compile(r"^///\s*(.+)", re.MULTILINE)
_DART_PROVIDER_RE = re.compile(r"final\s+(\w+)\s*=\s*(?:Provider|StateProvider|StreamProvider|FutureProvider|StateNotifierProvider|ChangeNotifierProvider)", re.MULTILINE)


def _summarise_dart(content: str) -> str:
    parts: list[str] = []

    # Doc comments (first block of ///).
    docs = _DART_DOC_RE.findall(content)
    if docs:
        parts.append(" ".join(docs[:3]))

    classes = _DART_CLASS_RE.findall(content)
    mixins = _DART_MIXIN_RE.findall(content)
    enums = _DART_ENUM_RE.findall(content)
    providers = _DART_PROVIDER_RE.findall(content)
    functions = _DART_TOP_FN_RE.findall(content)

    if classes:
        parts.append("Klassen: " + ", ".join(classes))
    if mixins:
        parts.append("Mixins: " + ", ".join(mixins))
    if enums:
        parts.append("Enums: " + ", ".join(enums))
    if providers:
        parts.append("Providers: " + ", ".join(providers))
    if functions:
        # Filter out common noise (build, main, etc. already covered by class).
        fns = [f for f in functions if f not in ("build", "main", "initState", "dispose", "createState")]
        if fns:
            parts.append("Funktionen: " + ", ".join(fns[:5]))

    return _join_parts(parts) or "Dart-Datei"


_PY_CLASS_RE = re.compile(r"^\s*class\s+(\w+)", re.MULTILINE)
_PY_DEF_RE = re.compile(r"^def\s+(\w+)", re.MULTILINE)
_PY_DOCSTRING_RE = re.compile(r'^"""(.+?)"""', re.DOTALL)


def _summarise_python(content: str) -> str:
    parts: list[str] = []

    m = _PY_DOCSTRING_RE.search(content)
    if m:
        doc = m.group(1).strip().splitlines()[0]
        parts.append(doc)

    classes = _PY_CLASS_RE.findall(content)
    functions = _PY_DEF_RE.findall(content)

    if classes:
        parts.append("Klassen: " + ", ".join(classes))
    if functions:
        fns = [f for f in functions if not f.startswith("_")]
        if fns:
            parts.append("Funktionen: " + ", ".join(fns[:5]))

    return _join_parts(parts) or "Python-Datei"


def _summarise_yaml(content: str, basename: str) -> str:
    if basename == "pubspec.yaml":
        m = re.search(r"^name:\s*(.+)", content, re.MULTILINE)
        desc = re.search(r"^description:\s*(.+)", content, re.MULTILINE)
        parts = []
        if m:
            parts.append(f"Paket: {m.group(1).strip()}")
        if desc:
            parts.append(desc.group(1).strip().strip('"'))
        return _join_parts(parts) or "pubspec.yaml"
    if basename == "analysis_options.yaml":
        return "Dart/Flutter Analyse-Konfiguration (Linting-Regeln)"

    # Generic YAML: list top-level keys.
    keys = re.findall(r"^(\w[\w-]*):", content, re.MULTILINE)
    if keys:
        return "Top-Level-Keys: " + ", ".join(keys[:8])
    return "YAML-Konfiguration"


def _summarise_markdown(content: str) -> str:
    m = re.search(r"^#\s+(.+)", content, re.MULTILINE)
    if m:
        return _truncate(m.group(1).strip(), 120)
    first_line = content.strip().splitlines()[0]
    return _truncate(first_line, 120)


def _summarise_proto(content: str) -> str:
    messages = re.findall(r"^\s*message\s+(\w+)", content, re.MULTILINE)
    services = re.findall(r"^\s*service\s+(\w+)", content, re.MULTILINE)
    parts: list[str] = []
    if services:
        parts.append("Services: " + ", ".join(services))
    if messages:
        parts.append("Messages: " + ", ".join(messages[:8]))
    return _join_parts(parts) or "Protocol-Buffer-Definition"


def _summarise_gradle(content: str) -> str:
    plugins = re.findall(r'id\s*\(\s*"([^"]+)"\s*\)', content)
    if plugins:
        return "Gradle-Build – Plugins: " + ", ".join(plugins[:5])
    return "Gradle-Build-Konfiguration"


def _summarise_xml(basename: str) -> str:
    if basename == "AndroidManifest.xml":
        return "Android-Manifest (Berechtigungen, Activities)"
    return "XML-Konfiguration"


def _summarise_json(content: str, basename: str) -> str:
    if basename == "manifest.json":
        return "PWA Web-App-Manifest"
    if basename == "package.json":
        m = re.search(r'"name"\s*:\s*"([^"]+)"', content)
        if m:
            return f"Node-Paket: {m.group(1)}"
    return "JSON-Daten"


def _summarise_shell(content: str) -> str:
    for line in content.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#!"):
            if stripped.startswith("#"):
                return stripped.lstrip("# ")
            return _truncate(stripped, 120)
    return "Shell-Skript"


# ── formatting helpers ───────────────────────────────────────────────────────


def _truncate(text: str, max_len: int) -> str:
    if len(text) <= max_len:
        return text
    return text[: max_len - 1] + "…"


def _join_parts(parts: list[str]) -> str:
    return " · ".join(parts) if parts else ""


# ── index writer ─────────────────────────────────────────────────────────────


def _should_ignore(name: str) -> bool:
    """Return True if a directory entry should be skipped."""
    return name in IGNORED_DIRS


def _write_index(
    map_path: str,
    rel_dir: str,
    dirs: list[str],
    files: list[str],
    project_root: str,
) -> None:
    """Write an ``_index.md`` for *rel_dir* into the map tree."""
    os.makedirs(map_path, exist_ok=True)
    index_path = os.path.join(map_path, "_index.md")

    display_dir = rel_dir if rel_dir != "." else "(root)"

    lines: list[str] = []
    lines.append(f"# 📂 `{display_dir}/`\n")
    lines.append(
        f"> Auto-generated by `update_map.py` — "
        f"{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}\n"
    )

    if dirs:
        lines.append("## Unterordner\n")
        for d in sorted(dirs):
            map_link = os.path.join(d, "_index.md")
            lines.append(f"* 📁 [{d}/]({map_link})")
        lines.append("")

    if files:
        lines.append("## Dateien\n")
        for f in sorted(files):
            abs_file = os.path.join(project_root, rel_dir, f) if rel_dir != "." else os.path.join(project_root, f)
            summary = _summarise_file(abs_file)
            lines.append(f"* 📄 **`{f}`** — {summary}")
        lines.append("")

    if not dirs and not files:
        lines.append("*(leerer Ordner)*\n")

    with open(index_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


# ── main logic ───────────────────────────────────────────────────────────────


def generate_map(project_root: str) -> None:
    """Walk *project_root* and create the map tree under ``MAP_DIR``."""
    project_root = os.path.normpath(project_root)

    if not os.path.isdir(project_root):
        print(f"Error: '{project_root}' is not a valid directory.")
        sys.exit(1)

    abs_map_dir = os.path.join(project_root, MAP_DIR)

    # Remove stale map so deleted dirs/files are not left behind.
    if os.path.isdir(abs_map_dir):
        shutil.rmtree(abs_map_dir)

    # Also skip the skill directory itself to avoid recursion.
    skill_abs = os.path.normpath(os.path.join(project_root, SKILL_DIR))

    for dirpath, dirnames, filenames in os.walk(project_root):
        # Skip ignored directories (modifying dirnames in-place prunes walk).
        dirnames[:] = [
            d
            for d in dirnames
            if not _should_ignore(d)
            and os.path.normpath(os.path.join(dirpath, d)) != skill_abs
        ]
        dirnames.sort()

        # Hide hidden files (dotfiles) except at root level.
        rel_dir = os.path.relpath(dirpath, project_root)
        visible_files = [f for f in filenames if not f.startswith(".") or rel_dir == "."]
        visible_files.sort()

        # Determine corresponding map path.
        if rel_dir == ".":
            map_path = abs_map_dir
        else:
            map_path = os.path.join(abs_map_dir, rel_dir)

        _write_index(map_path, rel_dir, dirnames, visible_files, project_root)

    print(f"✅ Map updated at '{os.path.relpath(abs_map_dir, project_root)}/'")


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    generate_map(root)
