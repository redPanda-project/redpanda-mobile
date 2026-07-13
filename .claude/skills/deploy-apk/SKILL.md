---
name: Deploy APK
description: >
  Builds the release APK and installs it on a USB-connected Android phone
  via adb. Use when the user says "deploy the app", "build the APK",
  "install on my phone" or invokes /deploy-apk. Handles the local
  toolchain paths, device detection and the known USB pitfalls.
---

# Deploy APK

Builds `redpanda-mobile` as a release APK and installs it on the phone.

## Prerequisites (already set up on this machine, 2026-07-12)

- Flutter/JDK live in `~/tools` and are **not on PATH** — export per command.
- Android SDK: `~/tools/android-sdk` (platform-tools, platforms;android-36,
  build-tools;36.0.0, licenses accepted).
- udev rules for the phone exist in `/etc/udev/rules.d/51-android.rules`
  (Xiaomi `2717` + Google `18d1`). New device vendors need a new rule line
  (requires auth via `pkexec`).

## Steps

1. **Build** (from the repo root `redpanda-mobile/`):

   ```bash
   export PATH="$HOME/tools/flutter/bin:$HOME/tools/jdk/bin:$PATH" \
          JAVA_HOME="$HOME/tools/jdk" ANDROID_HOME="$HOME/tools/android-sdk"
   flutter build apk --release
   ```

   Result: `build/app/outputs/flutter-apk/app-release.apk` (~75 MB).
   Run the build in the background — it takes 2–20 min (first run after
   `flutter clean` or a dependency change is the slow case).

2. **Wait for the device** (user plugs in via USB):

   ```bash
   ~/tools/android-sdk/platform-tools/adb devices
   ```

   Expected: `<serial>  device`. Poll in the background if it is not there
   yet — do not block the conversation.

3. **Install**:

   ```bash
   ~/tools/android-sdk/platform-tools/adb install -r \
     build/app/outputs/flutter-apk/app-release.apk
   ```

   `-r` keeps app data (signed with the debug key, so upgrades from this
   machine always work). Success output is literally `Success`.

## Troubleshooting

| Symptom in `adb devices` | Fix |
|---|---|
| *(empty, but phone charging)* | USB debugging off → enable in developer options; check `lsusb` for the device |
| `no permissions (missing udev rules?)` | vendor missing in `/etc/udev/rules.d/51-android.rules` → add line with the vendor id from `lsusb`, `udevadm control --reload-rules && udevadm trigger --subsystem-match=usb --action=add` (via `pkexec`), then `adb kill-server` |
| `unauthorized` | Confirmation dialog on the phone; it only appears with the **screen unlocked**. If it never shows: revoke USB debugging authorizations in developer options, toggle USB debugging off/on, replug |
| Device re-enumerates with a different vendor id | Normal: MTP mode is the phone vendor (e.g. Xiaomi `2717`), debug mode is Google `18d1` — both must be in the udev rule |

- `sudo` needs a password and the terminal cannot prompt — use `pkexec`
  (graphical auth dialog) for root steps.
- Build fails with "No Android SDK found": `ANDROID_HOME` export missing.
- After installing: app id is `com.example.redpanda`, label "Redpanda".

## Field-test debugging

Release builds log almost nothing (`RpLog` → `dart:developer.log` is a
no-op in AOT — backlog T17). What still works:

```bash
# Crashes and unhandled exceptions of the app process:
~/tools/android-sdk/platform-tools/adb logcat -d --pid=$( \
  ~/tools/android-sdk/platform-tools/adb shell pidof com.example.redpanda)
```

Grep for `E flutter` — unhandled Dart exceptions show up there.
