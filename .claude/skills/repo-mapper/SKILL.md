---
name: Iterative Context Mapper
description: Persistent project map with agent-generated summaries. The map lives as markdown files under map/ and is maintained by the agent itself – not through a script.
---

# Iterative Context Mapper

## Purpose

This map gives you **instant** context about every file and folder
in the project without needing to open the source files.

The map is located under `.agent-skills/repo-mapper/map/` and reflects the
relevant project structure.

## Structure

```
map/
├── _index.md              ← Root summary
├── lib/
│   ├── _index.md          ← Summary of lib/
│   ├── screens/
│   │   ├── _index.md      ← Summary of lib/screens/
│   │   └── chat.md        ← Detail summary for lib/screens/chat/
│   …
└── packages/
    └── redpanda_light_client/
        └── _index.md
```

### Rules

* Each folder gets an `_index.md`.
* Deep leaf folders (e.g. `lib/screens/chat/`) get a **detail summary**
  with file-by-file summaries.
* Parent folders (e.g. `lib/screens/`) summarize children **more briefly**.
* The higher in the hierarchy, the **more compressed** the summary.
* The root `_index.md` is a **high-level overview** of the entire project
  (max. 15–20 lines).

## Workflow – Reading (Drill-Down)

1. Read `.agent-skills/repo-mapper/map/_index.md`.
2. Decide which folder is relevant.
3. Open its `_index.md` for more detail.
4. Repeat until you've found the file.

## Workflow – Generate / Update Map

> **Important:** You (the agent) generate the map yourself. There is no script.
> You read the source files, summarize them, and write the map files.

### Step 1 – Determine Folder Structure

Use `view` or `glob` to see the directories.
Ignore: `.git`, `node_modules`, `.dart_tool`, `build`, `dist`,
`.pub-cache`, `.pub`, `.venv`, `__pycache__`, `.idea`.

Scan only relevant folders: `lib/`, `packages/`, `integration_test/`,
and root configuration files.

Platform folders (`android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`)
only mention as a single line in the root `_index.md` – **do not** scan deeply.

### Step 2 – Read and Summarize Files (Bottom-Up)

Work **from the leaves upward**:

1. **Read file:** Open each source file (e.g. `lib/screens/chat/chat_screen.dart`).
2. **Write summary:** Create a short paragraph per file:
   - What does the file do?
   - Which classes / widgets / functions / providers are contained?
   - Which dependencies / imports are relevant?
3. **Write leaf `_index.md`:** Collect all file summaries of a folder
   in its `_index.md` under `map/`.

### Step 3 – Summarize Parent Folders (Bubble-Up)

4. **Parent `_index.md`:** Condense the child `_index.md` files to a
   **shorter** summary.  
   Example: `map/lib/screens/_index.md` contains one line per
   screen subfolder instead of all file details.
5. **Repeat upward** until you reach `map/_index.md` (root).
   The root summary is **maximum 15–20 lines**.

### Step 4 – Commit the Map

Commit all `map/` files together with your code changes.

### When to Update?

* If you **create, delete, move, or significantly change** a file,
  update the affected `_index.md` and all parents up to root.
* For a complete regeneration: Delete `map/` and run steps 1–4.

## Format of `_index.md`

```markdown
# 📂 folder/

> Brief summary (1-2 sentences) of what this folder contains.

## Subfolders

* 📁 **sub-folder/** — One-liner what you find there.

## Files

* 📄 **file.dart** — What the file does, which classes/widgets/providers.
```

## Example

`map/lib/screens/chat/_index.md`:
```markdown
# 📂 lib/screens/chat/

> Chat functionality: send/receive messages and QR code sharing.

## Files

* 📄 **chat_screen.dart** — Main chat UI. ConsumerWidget with message
  list, input field, and AppBar. Uses channelProvider and redPandaClientProvider.
* 📄 **share_qr_dialog.dart** — Dialog for sharing your own public key as
  QR code. Uses qr_flutter.
```

`map/lib/screens/_index.md`:
```markdown
# 📂 lib/screens/

> All app screens: Onboarding, Home, Chat, Channel Management, Debug.

## Subfolders

* 📁 **chat/** — Chat UI and QR code sharing.
* 📁 **channels/** — Screens for creating and joining channels.
* 📁 **home/** — Main screen with channel list.
* 📁 **onboarding/** — Initial setup / username setting.

## Files

* 📄 **debug_peer_stats_screen.dart** — Debug screen for peer statistics.
```
