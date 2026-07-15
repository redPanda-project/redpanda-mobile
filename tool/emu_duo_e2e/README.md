# Emulator Duo E2E Harness (T23)

Two headless Android emulators (Alice + Bob) chat with each other through a
**local** backend node — the deterministic, host-only variant of the desktop
duo E2E. This is a local loop tool; it does **not** run in GitHub CI (it
needs KVM, an Android system image and ~4 GB of free RAM).

## Scenarios

- **S1** — fresh pairing: Alice creates the channel through the real UI, Bob
  joins via the QR JSON (same code path as the scanner, minus the camera),
  Alice sends one message, delivery is timed.
- **S2** — 10 messages ping-pong (odd from Alice, even from Bob), latency per
  message; report contains p50/p95/max (nearest-rank).

Latency timestamps are taken **on the host** by the coordination server when
the `sent-<id>` / `recv-<id>` markers arrive, so guest clock drift cannot
skew the numbers (resolution: UI poll interval of ~250 ms + one HTTP hop).

## Prerequisites

- KVM available (`/dev/kvm` readable+writable).
- Android SDK in `~/tools/android-sdk` (override root via `RP_TOOLS` or
  `ANDROID_HOME`) with `platform-tools`, `emulator` and the system image
  `system-images;android-35;google_apis;x86_64` installed:
  `sdkmanager emulator "system-images;android-35;google_apis;x86_64"`
- Flutter in `~/tools/flutter`, JDK in `~/tools/jdk` (or on `PATH`).
- Backend jar at `references/redPandaj/target/redpanda.jar`:
  `gh release download latest --repo redPanda-project/redpandaj --pattern 'redpanda.jar' --dir references/redPandaj/target --clobber`
- Ports free: `59558` (node — override with `RP_NODE_PORT` if a stray node
  already holds it), `8123` (coord server, `RP_COORD_PORT`), `5554`/`5556`
  (adb).

## Run

```sh
tool/emu_duo_e2e/run.sh             # local node — the default, deterministic
tool/emu_duo_e2e/run.sh --testnet   # live testnet seeds instead (no local node)
```

The script:

1. creates the AVDs `rp_alice` / `rp_bob` once (API 35, 1536 MB RAM, 2 cores,
   swiftshader) and reuses them afterwards,
2. builds ONE debug apk with `integration_test/emu_duo_e2e_test.dart` as the
   entrypoint (`RP_SEEDS`/`RP_COORD` are dart-defines; the role is derived
   from the AVD name at runtime, so both emulators run the identical apk),
3. starts the local node (`PORT=59558 REDPANDA_KNOWN_NODES="127.0.0.1:9"
   java -jar redpanda.jar`) and the coord server
   (`tool/emu_duo_e2e/coord_server.dart`). The blackhole seed keeps the
   node isolated: peers gossiped from other nodes have addresses that are
   wrong or unreachable from inside an emulator and break garlic routing.
   An empty `REDPANDA_KNOWN_NODES` does NOT isolate — the jar falls back
   to its default known nodes (which include `127.0.0.1:59558`),
4. boots the emulators sequentially (tight RAM), installs the apk (app data
   is wiped via `pm clear` so reused AVDs still start fresh), launches the
   app on both, and
5. waits for both verdicts, then writes the artifacts.

Exit code 0 iff both roles report `ok:true`.

## Artifacts (`build/e2e-artifacts/`, git-ignored)

| File | Content |
| --- | --- |
| `report.json` | S1 latency + S2 per-message latencies with p50/p95/max |
| `alice.logcat`, `bob.logcat` | full logcat per emulator (`flutter: [emu-duo]` lines are the test's own log) |
| `node.log`, `coord.log`, `emulator-*.log` | host-side process logs |

## Known limits

- RAM: two emulators à 1.5 GB + JVM node need roughly 4 GB free; the apk is
  built before the emulators boot and the gradle daemon is stopped to make
  room. Do not run RAM-heavy jobs in parallel.
- The QR *scan* is bypassed (headless emulators have no camera); everything
  else drives the real UI. On the creator side the peer-OH import writes only
  the peer-OH columns instead of re-scanning — a real scan would go through
  `addChannel`/insertOrReplace and wipe `authPrivateKey`/`ratchetState`
  (known finding from the desktop duo E2E, 2026-07-11).
- OH registration is rate-limited node-side (5/min per connection): the test
  waits for `ConnectionStatus.connected` and retries every 30 s.
- First delivery on a fresh pairing should land in <60 s since the retry
  backoff rework (redpandaj#254, mobile#53). If S1 hangs for minutes, check
  the logcats for garlic/OH-resolve errors instead of raising timeouts.
- The harness assumes the emulator serials `emulator-5554`/`emulator-5556`
  and AVD names `rp_alice`/`rp_bob` (the role detection depends on them).
