# Emulator Duo E2E Harness (T23/T24)

Two headless Android emulators (Alice + Bob) chat with each other through a
**local** backend node — the deterministic, host-only variant of the desktop
duo E2E. This is a local loop tool; it does **not** run in GitHub CI (it
needs KVM, an Android system image and ~4 GB of free RAM).

## Scenarios

Selected via `RP_SCENARIOS` (comma list, default `s1,s2,s3,s4`); S1 is the
pairing foundation and always runs, even when omitted from the list.

- **S1** — fresh pairing: Alice creates the channel through the real UI, Bob
  joins via the QR JSON (same code path as the scanner, minus the camera),
  Alice sends one message, delivery is timed.
- **S2** — 10 messages ping-pong (odd from Alice, even from Bob), latency per
  message; report contains p50/p95/max (nearest-rank).
- **S3** — kill/restart catch-up (T24): the harness force-stops Bob's app
  (`am force-stop` — the in-app test process dies with it), Alice sends while
  Bob is dead, the harness restarts the app. The restarted process detects
  the resume phase via the coord key `bob_phase=resume-s3`, skips
  onboarding/pairing (everything is persisted; **no** `pm clear` on resume)
  and must show the message within the **60 s catch-up budget**
  (`s3.catchupMs` = `recv` − `s3-bob-restart`, enforced by run.sh). Proves
  the T18 restart-requeue (PR #50).
- **S4** — airplane-mode reconnect (T24): with both apps running, the
  harness enables airplane mode on Bob (`cmd connectivity airplane-mode
  enable` — verified on the API 35 image to drop guest→host TCP, i.e.
  10.0.2.2 becomes unreachable), Alice sends into the silence
  (`RP_S4_SILENCE_SEC`, default 90 s), then airplane mode goes off again.
  Bob must reconnect and receive; `s4.reconnectDeliveryMs` = `recv` −
  `s4-net-up`. run.sh fails the scenario if the message arrived *before*
  the network was restored (that would mean the disconnect never happened).
  Proves the T15 isolate resilience + the #55 host-node fix.

  **The silence must outlast the node's `Settings.pingTimeout` (65 s)**
  — that is what makes S4 deterministic (T89a). Below the timeout the node
  keeps Bob's peer entry alive across the outage and the returning client
  slots straight back into it; above it `PeerJobs` disconnects the silent
  peer and the next pass evicts the entry (light clients announce port 0, so
  the entry is undialable), and the client has to run a full fresh
  handshake. Both are real paths, but only the second exercises the
  stale-peer reconnect — and at the old 45 s which one a run took was
  decided by a few seconds, which is exactly how T88 produced three
  different verdicts in four runs. run.sh therefore *verifies* the eviction
  (`counters.node.undialableEvictions.duringS4`) and fails the run if it did
  not happen, with a message that names it as a harness precondition rather
  than a product defect. `RP_S4_SILENCE_SEC` ≤ `RP_NODE_PING_TIMEOUT_SEC`
  (default 65) is refused up front. Cost: ~45 s more per run than the old
  budget.
- **S5 (OH expiry / re-announce) is NOT covered**: the node clamps every OH
  registration to `MIN_TTL_MS` = 10 min … `MAX_TTL_MS` = 7 d in
  `OutboundService.java` (`private static final`, no env/property override),
  so a short-expiry run is impossible without a redpandaj change — out of
  scope for this harness by decision (T24).

Latency timestamps are taken **on the host** by the coordination server when
the `sent-<id>` / `recv-<id>` markers arrive, so guest clock drift cannot
skew the numbers (resolution: UI poll interval of ~250 ms + one HTTP hop).
The S3/S4 lifecycle markers (`s3-bob-killed`, `s3-bob-restart`,
`s4-net-down`, `s4-net-up`) are PUT by run.sh itself and timestamped the
same way.

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
tool/emu_duo_e2e/run.sh                        # all scenarios, local node
RP_SCENARIOS=s1,s2 tool/emu_duo_e2e/run.sh     # only pairing + ping-pong
tool/emu_duo_e2e/run.sh --testnet              # live testnet seeds (no local node)
```

The scenario list is served to the apps via the coord server key
`scenarios` (no dart-define), so changing `RP_SCENARIOS` does not require
an apk rebuild.

The script:

1. creates the AVDs `rp_alice` / `rp_bob` once (API 35, 1536 MB RAM, 2 cores,
   swiftshader) and reuses them afterwards,
2. builds ONE debug apk with `integration_test/emu_duo_e2e_test.dart` as the
   entrypoint (`RP_SEEDS`/`RP_COORD` are dart-defines; the role is derived
   from the AVD name at runtime, so both emulators run the identical apk),
3. starts the local node with `PORT=59558 REDPANDA_KNOWN_NODES=none` and
   the coord server (`tool/emu_duo_e2e/coord_server.dart`). `none` (T29)
   starts the node without any bootstrap peers and keeps it isolated:
   peers gossiped from other nodes have addresses that are wrong or
   unreachable from inside an emulator and break garlic routing. An empty
   `REDPANDA_KNOWN_NODES` does NOT isolate — the jar falls back to its
   default known nodes (which include `127.0.0.1:59558`). Before T29 the
   harness used the blackhole seed `127.0.0.1:9` instead; `none` requires
   the jar from the 2026-07-19 release or newer.
4. boots the emulators sequentially (tight RAM), installs the apk (app data
   is wiped via `pm clear` so reused AVDs still start fresh), launches the
   app on both,
5. orchestrates the lifecycle scenarios: S3 (force-stop Bob → Alice sends →
   restart with `bob_phase=resume-s3`) and S4 (airplane mode on → Alice
   sends → silence → airplane mode off), and
6. waits for both verdicts, then writes the artifacts.

Exit code 0 iff both roles report `ok:true` AND S1 stayed within its 30 s
budget AND (with s3 enabled) the catch-up stayed within the 60 s budget AND
(with s4 enabled) delivery happened only after the network came back and the
node actually evicted the stale peer during the silence.

## Artifacts (`build/e2e-artifacts/`, git-ignored)

| File | Content |
| --- | --- |
| `report.json` | S1 latency, S2 per-message latencies with p50/p95/max, S3 `catchupMs`/`withinCatchupBudget`, S4 `silenceMs`/`reconnectDeliveryMs`, plus `counters` (see below) |
| `counters.json` | the same counter block, written straight to disk so it survives a run that dies before the report can be fetched |
| `alice.logcat`, `bob.logcat` | full logcat per emulator (`flutter: [emu-duo]` lines are the test's own log) |
| `node.log`, `coord.log`, `emulator-*.log` | host-side process logs |

### Run counters (T89c)

`report.json` → `counters` (and `counters.json`) is a grep-derived summary of
node.log and the two logcats, refreshed on every report save — including the
failure paths, which is where it earns its keep. Node counters come with a
`duringS4` slice (node.log is cut at the line it had reached when the radio
went down); the per-role client counters are whole-run totals. It exists so a red run can be
triaged as "the gate flaked" or "the gate found something" without opening a
3 MB logcat:

| Field | Reads as |
| --- | --- |
| `node.undialableEvictions.duringS4` | 0 ⇒ S4 never exercised the reconnect-after-eviction path (harness precondition, run fails) |
| `node.duplicateConnections.{total,duringS4}` | the T88 signature (`duplicate parallel connection from the same identity`); >0 during S4 means peer bookkeeping went out of sync again |
| `node.handshakes.wedged` | `parsed ACTIVATE_ENCRYPTION` − `received first encrypted command`, the T80 metric; 3–4 before redpandaj#288, 0 after — anything >0 means that class is back |
| `node.exceptionLines` | lines containing `Exception` in node.log |
| `clients.<role>.workerDied` / `workerRespawns` / `commandsDropped` | a network worker isolate that kept dying (the app recovers by replaying state, but every respawn costs a full reconnect) |
| `clients.<role>.hostNodeNotConnected` / `noActivePeer` | mailbox polls that found no usable connection. Whole-run totals — only the node counters are sliced per scenario — and in a healthy run nearly all of them fall in the S4 silence (~20 at 90 s); the T88 run had 171 |
| `clients.<role>.clientInitialized` / `connectRoutineStarts` | 1 per app process (Bob has 2: S3 restarts him) — higher means the worker was recreated |
| `clients.<role>.pollCycles` / `testTimeouts` | poll activity, and how often the in-app test gave up on a `pumpUntil` |

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
