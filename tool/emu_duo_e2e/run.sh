#!/usr/bin/env bash
# Emulator duo E2E harness (T23/T24): two headless Android emulators (Alice
# + Bob) chat with each other through a LOCAL backend node on this host.
# See README.md in this directory for prerequisites and details.
#
# Usage:
#   tool/emu_duo_e2e/run.sh              # local node (default, deterministic)
#   tool/emu_duo_e2e/run.sh --testnet    # against the live testnet seeds
#
# Scenario selection (RP_SCENARIOS, default all):
#   RP_SCENARIOS=s1,s2 tool/emu_duo_e2e/run.sh
#   s1 pairing + first delivery (always runs — it is the foundation)
#   s2 10-message ping-pong with latency percentiles
#   s3 kill/restart catch-up on Bob (T18 restart-requeue, budget 60 s)
#   s4 airplane-mode reconnect on Bob (T15 isolate resilience)
#
# Artifacts land in build/e2e-artifacts/: report.json, alice.logcat,
# bob.logcat, node.log, coord.log, emulator-*.log.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="${RP_TOOLS:-$HOME/tools}"
export JAVA_HOME="${JAVA_HOME:-$TOOLS/jdk}"
export ANDROID_HOME="${ANDROID_HOME:-$TOOLS/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$TOOLS/flutter/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

COORD_PORT="${RP_COORD_PORT:-8123}"
NODE_PORT="${RP_NODE_PORT:-59558}"
SYSIMG="system-images;android-35;google_apis;x86_64"
AVD_RAM_MB=1536
JAR="$REPO/references/redPandaj/target/redpanda.jar"
# Profile build (T27): AOT-compiled like a release apk, so crypto costs
# (Ed25519 signing, ratchet decrypt) match production. A debug/JIT build
# inflates them ~10-50x (3-8 s per signature on these emulators) and
# drowns the latency signal this harness exists to measure.
APK="$REPO/build/app/outputs/flutter-apk/app-profile.apk"
ART="$REPO/build/e2e-artifacts"
RESULT_TIMEOUT_MIN="${RP_TIMEOUT_MIN:-45}"
SCENARIOS="${RP_SCENARIOS:-s1,s2,s3,s4}"
# T89(a): the S4 radio silence must outlast the node's `Settings.pingTimeout`
# (65 s), otherwise the run is a coin flip. Below that timeout the node keeps
# Bob's peer entry alive across the outage and the returning client slots back
# into it; above it `PeerJobs` disconnects the silent peer and the next pass
# evicts the (undialable, port-0) entry, so the client has to run the full
# fresh-handshake reconnect. Both paths are real, but only the second one
# exercises the T88/#297 stale-peer path — and with 45 s of silence which one a
# run took was decided by seconds (see T88: run1's first post-outage handshake
# landed ~8 s after the timeout had fired). 90 s puts the eviction beyond doubt:
# `getLastAnswered()` is at least the silence itself, so it always crosses 65 s,
# and there is room for one more `PeerJobs` pass (1-5 s) to do the eviction.
# The harness verifies the eviction actually happened (node.log counter) and
# fails the run if it did not — a silent fallback to the easy path would be the
# very non-determinism this budget exists to remove.
NODE_PING_TIMEOUT_SEC="${RP_NODE_PING_TIMEOUT_SEC:-65}"
S4_SILENCE_SEC="${RP_S4_SILENCE_SEC:-90}"

SEEDS="10.0.2.2:$NODE_PORT"
START_NODE=1
if [[ "${1:-}" == "--testnet" ]]; then
  # Non-deterministic variant: real network, no local node.
  SEEDS="5.75.137.166:59558,46.224.156.238:59558"
  START_NODE=0
fi

SERIAL_ALICE="emulator-5554"
SERIAL_BOB="emulator-5556"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

NODE_PID=""
COORD_PID=""
LOGCAT_PIDS=()

# Kills the emulator on a serial ONLY if it runs the given AVD — a developer
# may have an unrelated emulator sitting on 5554/5556.
kill_our_emulator() { # serial avd_name
  local name
  name="$(adb -s "$1" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
  [[ "$name" == "$2" ]] && adb -s "$1" emu kill >/dev/null 2>&1
}

cleanup() {
  set +e
  log "cleanup: stopping emulators, node, coord server"
  for pid in "${LOGCAT_PIDS[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null; done
  kill_our_emulator "$SERIAL_ALICE" rp_alice
  kill_our_emulator "$SERIAL_BOB" rp_bob
  [[ -n "$COORD_PID" ]] && kill "$COORD_PID" 2>/dev/null
  if [[ -n "$NODE_PID" ]]; then
    kill "$NODE_PID" 2>/dev/null
    sleep 2
    kill -9 "$NODE_PID" 2>/dev/null
  fi
}
trap cleanup EXIT

port_open() { (echo >"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

wait_port() { # port what seconds
  for _ in $(seq 1 "$3"); do
    port_open "$1" && return 0
    sleep 1
  done
  die "$2 did not open port $1 within $3s"
}

has_scenario() { [[ ",$SCENARIOS," == *",$1,"* ]]; }

# All coord-server curls are bounded — a wedged server must not hang the
# harness (the surrounding waits are deadline-driven, curl was not).
CURL=(curl -fs --connect-timeout 5 --max-time 15)

kv_put() { # name value — first PUT wins the host-side timestamp
  # --data-raw: never interpret a leading '@' as "read body from file".
  "${CURL[@]}" -X PUT --data-raw "$2" "http://127.0.0.1:$COORD_PORT/kv/$1" >/dev/null \
    || die "kv_put $1 failed — coord server down?"
}

# ---------------------------------------------------------------------------
# T89(c): per-run counters, so "the gate flaked" can be told from "the gate
# found something" without reading 3 MB of logcat.
#
# Everything here is a grep over artifacts the harness writes anyway (node.log,
# {alice,bob}.logcat) — no backend change and no extra instrumentation. The
# numbers are PUT to the coord server, which folds them into report.json under
# `counters`; the collection runs inside save_report(), so an aborted run keeps
# them too (that is the run you actually want them for).
# ---------------------------------------------------------------------------

# node.log line count at the moment S4 cut Bob's radio — the S4 slice is
# everything after it. Counting lines instead of matching timestamps keeps this
# independent of the node's clock and log format.
S4_NODE_MARK=""
# Filled by collect_counters(), read by the acceptance checks at the end.
S4_EVICTIONS=""
S4_DUPLICATES=""

count_pat() { # file pattern -> count (0 when the file is missing)
  [[ -f "$1" ]] || { echo 0; return; }
  # grep -c prints "0" and exits 1 when nothing matches; -a keeps it happy on
  # the logcats, which do contain the odd non-UTF8 byte.
  grep -acF -- "$2" "$1" 2>/dev/null || true
}

count_pat_since() { # file pattern startline -> count in the tail after startline
  [[ -f "$1" && -n "$3" ]] || { echo 0; return; }
  tail -n "+$(( $3 + 1 ))" "$1" 2>/dev/null | grep -acF -- "$2" 2>/dev/null || true
}

node_log_lines() { [[ -f "$ART/node.log" ]] && wc -l <"$ART/node.log" || echo 0; }

# Per-role client counters from a logcat. The markers are the ones that
# distinguish a healthy run from the two failure modes the gate has actually
# produced: the T88 duplicate loop (host node never connected, mailbox polls
# spinning) and a worker isolate that keeps dying and respawning.
client_counters_json() { # logcat file
  local f="$1"
  printf '{"available": %s, "clientInitialized": %s, "connectRoutineStarts": %s, ' \
    "$([[ -f "$f" ]] && echo true || echo false)" \
    "$(count_pat "$f" 'RedPandaWorker: Client initialized.')" \
    "$(count_pat "$f" 'RedPandaLightClient: Starting connection routine...')"
  printf '"workerDied": %s, "workerRespawns": %s, "commandsDropped": %s, ' \
    "$(count_pat "$f" 'RedPandaIsolateClient: worker isolate died.')" \
    "$(count_pat "$f" 'RedPandaIsolateClient: respawning worker')" \
    "$(count_pat "$f" 'Isolate not ready. Dropping command')"
  printf '"hostNodeNotConnected": %s, "noActivePeer": %s, "pollCycles": %s, "testTimeouts": %s}' \
    "$(count_pat "$f" 'not connected — requesting a connection')" \
    "$(count_pat "$f" 'fetchMessages() no active peer available')" \
    "$(count_pat "$f" 'poll cycle fetched')" \
    "$(count_pat "$f" 'TIMEOUT waiting for')"
}

collect_counters() {
  local log="$ART/node.log"
  local dup_total dup_s4 evict_total evict_s4 act enc conn exc s4slice
  dup_total="$(count_pat "$log" 'duplicate parallel connection from the same identity')"
  evict_total="$(count_pat "$log" 'removed undialable disconnected peer from peerList')"
  act="$(count_pat "$log" 'parsed ACTIVATE_ENCRYPTION')"
  enc="$(count_pat "$log" 'received first encrypted command')"
  conn="$(count_pat "$log" 'Connected successfully to')"
  exc="$(count_pat "$log" 'Exception')"
  if [[ -n "$S4_NODE_MARK" ]]; then
    dup_s4="$(count_pat_since "$log" 'duplicate parallel connection from the same identity' "$S4_NODE_MARK")"
    evict_s4="$(count_pat_since "$log" 'removed undialable disconnected peer from peerList' "$S4_NODE_MARK")"
    s4slice="$S4_NODE_MARK"
  else
    dup_s4=null; evict_s4=null; s4slice=null
  fi
  S4_EVICTIONS="$evict_s4"
  S4_DUPLICATES="$dup_s4"

  # `wedged` is the T80 metric: a handshake that reached ACTIVATE_ENCRYPTION but
  # never produced a first encrypted command is a connection the client believes
  # in and the node cannot use. It was 3-4 per run before redpandaj#288 and 0
  # after; anything above 0 here means that class of defect is back.
  local wedged=$(( act - enc ))
  [[ $wedged -lt 0 ]] && wedged=0

  {
    printf '{"collectedAt": "%s", ' "$(date -Iseconds)"
    printf '"node": {"available": %s, "pingTimeoutSec": %s, "s4SilenceSec": %s, "s4LogMark": %s, ' \
      "$([[ -f "$log" ]] && echo true || echo false)" \
      "$NODE_PING_TIMEOUT_SEC" "$S4_SILENCE_SEC" "$s4slice"
    printf '"duplicateConnections": {"total": %s, "duringS4": %s}, ' "$dup_total" "$dup_s4"
    printf '"undialableEvictions": {"total": %s, "duringS4": %s}, ' "$evict_total" "$evict_s4"
    printf '"handshakes": {"activateEncryption": %s, "firstEncryptedCommand": %s, "wedged": %s}, ' \
      "$act" "$enc" "$wedged"
    printf '"connectedSuccessfully": %s, "exceptionLines": %s}, ' "$conn" "$exc"
    printf '"clients": {"alice": %s, "bob": %s}}' \
      "$(client_counters_json "$ART/alice.logcat")" \
      "$(client_counters_json "$ART/bob.logcat")"
  } >"$ART/counters.json"

  # Non-fatal on purpose: this runs on the failure path too, where the coord
  # server may already be gone — counters.json on disk is still the artifact.
  "${CURL[@]}" -X PUT --data-binary "@$ART/counters.json" \
    "http://127.0.0.1:$COORD_PORT/kv/harness_counters" >/dev/null 2>&1 || true
}

save_report() {
  collect_counters
  # Fetch into a temp file — a failing curl must not truncate a previously
  # saved report.json (it is the primary debugging artifact).
  if "${CURL[@]}" "http://127.0.0.1:$COORD_PORT/report" >"$ART/report.json.tmp" 2>/dev/null; then
    mv "$ART/report.json.tmp" "$ART/report.json"
  else
    rm -f "$ART/report.json.tmp"
  fi
}

wait_kv() { # name seconds — aborts early if either role reported failure
  local deadline=$(( $(date +%s) + $2 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    if "${CURL[@]}" -o /dev/null "http://127.0.0.1:$COORD_PORT/kv/$1"; then
      return 0
    fi
    local a b
    a="$("${CURL[@]}" "http://127.0.0.1:$COORD_PORT/kv/alice_result" 2>/dev/null || true)"
    b="$("${CURL[@]}" "http://127.0.0.1:$COORD_PORT/kv/bob_result" 2>/dev/null || true)"
    if [[ "$a" == *'"ok":false'* || "$b" == *'"ok":false'* ]]; then
      save_report
      die "a role reported failure while waiting for kv '$1' (alice=$a bob=$b)"
    fi
    sleep 2
  done
  save_report
  die "kv '$1' never appeared within $2s"
}

# S4 network cut on Bob. `cmd connectivity airplane-mode` works on API 35
# and drops the emulated wifi+cellular NICs, which is exactly the
# app-visible connection loss we need (10.0.2.2 becomes unreachable).
bob_net() { # down|up
  local mode=enable
  [[ "$1" == up ]] && mode=disable
  adb -s "$SERIAL_BOB" shell cmd connectivity airplane-mode "$mode" \
    || die "airplane-mode $mode failed on $SERIAL_BOB"
  log "S4: airplane-mode $mode -> state: $(adb -s "$SERIAL_BOB" shell cmd connectivity airplane-mode | tr -d '\r')"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm not accessible — KVM is required"
command -v flutter >/dev/null || die "flutter not on PATH"
command -v curl >/dev/null || die "curl not installed"
command -v adb >/dev/null || die "adb not on PATH (platform-tools)"
command -v emulator >/dev/null || die "emulator not on PATH — install with: sdkmanager emulator"
[[ -d "$ANDROID_HOME/system-images/android-35/google_apis/x86_64" ]] \
  || die "system image missing — install with: sdkmanager \"$SYSIMG\""
if [[ "$START_NODE" == 1 ]]; then
  [[ -f "$JAR" ]] || die "backend jar missing at $JAR — fetch with:
  gh release download latest --repo redPanda-project/redpandaj --pattern 'redpanda.jar' --dir references/redPandaj/target --clobber"
  if port_open "$NODE_PORT"; then
    die "port $NODE_PORT already in use — is another node running?"
  fi
fi
if port_open "$COORD_PORT"; then die "port $COORD_PORT already in use"; fi
SCENARIOS="$(echo "$SCENARIOS" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
for s in ${SCENARIOS//,/ }; do
  [[ "$s" =~ ^s[1-4]$ ]] || die "unknown scenario '$s' in RP_SCENARIOS (allowed: s1,s2,s3,s4)"
done
has_scenario s1 || SCENARIOS="s1,$SCENARIOS"  # s1 is the pairing foundation
[[ "$S4_SILENCE_SEC" =~ ^[0-9]+$ ]] || die "RP_S4_SILENCE_SEC must be a number of seconds"
if has_scenario s4 && [[ "$START_NODE" == 1 ]] \
   && [[ "$S4_SILENCE_SEC" -le "$NODE_PING_TIMEOUT_SEC" ]]; then
  # Refused rather than warned: with a shorter silence the node keeps Bob's peer
  # entry across the outage, S4 no longer exercises the eviction+reconnect path
  # it exists for, and the acceptance check below would fail the run anyway.
  die "RP_S4_SILENCE_SEC=$S4_SILENCE_SEC is not longer than the node's ping timeout (${NODE_PING_TIMEOUT_SEC}s) — S4 would not exercise the stale-peer eviction"
fi
log "scenarios: $SCENARIOS"

mkdir -p "$ART"
rm -f "$ART"/report.json "$ART"/counters.json "$ART"/alice.logcat "$ART"/bob.logcat \
      "$ART"/node.log "$ART"/coord.log

# ---------------------------------------------------------------------------
# AVDs (created once, reused afterwards)
# ---------------------------------------------------------------------------
tune_avd() { # name
  local cfg="$HOME/.android/avd/$1.avd/config.ini"
  [[ -f "$cfg" ]] || die "AVD config not found: $cfg"
  for kv in "hw.ram.size=$AVD_RAM_MB" "hw.cpu.ncore=2" "hw.keyboard=yes" \
            "hw.gpu.mode=swiftshader_indirect" "disk.dataPartition.size=2048M"; do
    local key="${kv%%=*}"
    # Literal prefix match (keys contain '.', which is a regex wildcard).
    awk -v p="$key=" 'index($0, p) != 1' "$cfg" > "$cfg.tmp"
    mv "$cfg.tmp" "$cfg"
    echo "$kv" >> "$cfg"
  done
}

ensure_avd() { # name
  if [[ ! -d "$HOME/.android/avd/$1.avd" ]]; then
    log "creating AVD $1"
    echo no | avdmanager create avd -n "$1" -k "$SYSIMG" >/dev/null
  fi
  tune_avd "$1"
}
ensure_avd rp_alice
ensure_avd rp_bob

# ---------------------------------------------------------------------------
# Build the test APK FIRST (gradle is the RAM hog — emulators come later).
# Both emulators run this same apk; the role comes from the AVD name.
# ---------------------------------------------------------------------------
log "building test apk (target=integration_test/emu_duo_e2e_test.dart, seeds=$SEEDS)"
(cd "$REPO" && flutter build apk --profile \
  --target=integration_test/emu_duo_e2e_test.dart \
  --dart-define=RP_SEEDS="$SEEDS" \
  --dart-define=RP_COORD="http://10.0.2.2:$COORD_PORT")
[[ -f "$APK" ]] || die "apk not found at $APK after build"
# Free the gradle daemon's heap before booting two emulators.
(cd "$REPO/android" && ./gradlew --stop >/dev/null 2>&1) || true

# ---------------------------------------------------------------------------
# Backend node + coordination server
# ---------------------------------------------------------------------------
if [[ "$START_NODE" == 1 ]]; then
  NODE_DIR="$(mktemp -d /tmp/rp-emu-node.XXXXXX)"
  log "starting local backend node on port $NODE_PORT (workdir $NODE_DIR)"
  # REDPANDA_KNOWN_NODES=none (T29) starts the node without any bootstrap
  # peers: the jar's default known-nodes list would connect it to other
  # local or testnet nodes, whose gossiped peer addresses (e.g.
  # 127.0.0.1:59558) are wrong or unreachable from inside an emulator and
  # send garlic routes / deposits into the void. (Before T29 this needed a
  # blackhole seed 127.0.0.1:9 -- an EMPTY list falls back to the defaults.)
  # -Xmx512m: cap the node heap -- the host has ~7.5 GiB and an uncapped JVM
  # next to two emulators swap-thrashes the whole run (findings of runs 6/7).
  (cd "$NODE_DIR" && PORT="$NODE_PORT" REDPANDA_KNOWN_NODES="none" \
    exec java -Xmx512m -jar "$JAR") >"$ART/node.log" 2>&1 &
  NODE_PID=$!
  wait_port "$NODE_PORT" "backend node" 60
fi

log "starting coord server on port $COORD_PORT"
dart "$REPO/tool/emu_duo_e2e/coord_server.dart" "$COORD_PORT" >"$ART/coord.log" 2>&1 &
COORD_PID=$!
wait_port "$COORD_PORT" "coord server" 30
# The apps read the scenario selection from the coord server at startup —
# no dart-define, so changing RP_SCENARIOS does not require an apk rebuild.
kv_put scenarios "$SCENARIOS"

# ---------------------------------------------------------------------------
# Emulators (booted sequentially — tight RAM budget on this host)
# ---------------------------------------------------------------------------
boot_avd() { # name console_port serial
  # Never boot over a foreign emulator that already occupies our serial.
  if adb devices | grep -q "^$3[[:space:]]"; then
    local name
    name="$(adb -s "$3" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
    if [[ "$name" == "$1" ]]; then
      log "AVD $1 already running on $3 — stopping stale instance"
      adb -s "$3" emu kill >/dev/null 2>&1
      sleep 5
    else
      die "serial $3 is occupied by another emulator ('$name') — free it first"
    fi
  fi
  log "booting AVD $1 (serial $3, console port $2)"
  emulator -avd "$1" -port "$2" \
    -no-window -no-audio -no-snapshot -no-boot-anim -no-metrics \
    -gpu swiftshader_indirect -memory "$AVD_RAM_MB" -cores 2 \
    >"$ART/emulator-$1.log" 2>&1 &
  timeout 300 adb -s "$3" wait-for-device || die "AVD $1 never appeared on adb ($3)"
  local booted=""
  for _ in $(seq 1 180); do
    booted="$(adb -s "$3" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$booted" == "1" ]] && break
    sleep 2
  done
  [[ "$booted" == "1" ]] || die "AVD $1 did not finish booting within 6 minutes"
  # Keep the (headless) device awake and predictable for widget taps.
  adb -s "$3" shell svc power stayon true || true
  adb -s "$3" shell input keyevent 82 || true
  for s in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb -s "$3" shell settings put global "$s" 0 || true
  done
  log "AVD $1 booted"
}
boot_avd rp_alice 5554 "$SERIAL_ALICE"
boot_avd rp_bob 5556 "$SERIAL_BOB"

# ---------------------------------------------------------------------------
# Install + launch
# ---------------------------------------------------------------------------
for serial in "$SERIAL_ALICE" "$SERIAL_BOB"; do
  log "installing apk on $serial"
  adb -s "$serial" install -r "$APK" >/dev/null
  # AVDs are reused across runs — wipe app state so every run starts with a
  # fresh onboarding, an empty DB and an empty peer repository.
  adb -s "$serial" shell pm clear com.example.redpanda >/dev/null
  # T16: pre-grant the notification permission so the foreground service's
  # permission dialog never overlays (and pauses) the app mid-scenario.
  adb -s "$serial" shell pm grant com.example.redpanda \
    android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
done

adb -s "$SERIAL_ALICE" logcat -c || true
adb -s "$SERIAL_BOB" logcat -c || true
adb -s "$SERIAL_ALICE" logcat -v time >"$ART/alice.logcat" 2>&1 &
LOGCAT_PIDS+=($!)
adb -s "$SERIAL_BOB" logcat -v time >"$ART/bob.logcat" 2>&1 &
LOGCAT_PIDS+=($!)

log "launching app on both emulators"
adb -s "$SERIAL_ALICE" shell am start -n com.example.redpanda/.MainActivity >/dev/null
adb -s "$SERIAL_BOB" shell am start -n com.example.redpanda/.MainActivity >/dev/null

# ---------------------------------------------------------------------------
# S3 orchestration: kill Bob's app, let Alice send, restart, measure catch-up
# (the test process dies with the force-stop — the restarted app detects the
# resume phase via the bob_phase key and skips onboarding/pairing).
# ---------------------------------------------------------------------------
if has_scenario s3; then
  log "S3: waiting for Bob to finish the earlier scenarios"
  wait_kv bob_ready_s3 1500
  log "S3: force-stopping Bob's app"
  adb -s "$SERIAL_BOB" shell am force-stop com.example.redpanda
  sleep 2
  kv_put s3-bob-killed host
  wait_kv "sent-e2e-s3" 300
  sleep 5   # give the message time to settle in the node-side OH mailbox
  kv_put bob_phase resume-s3
  log "S3: restarting Bob's app (catch-up clock starts now)"
  kv_put s3-bob-restart host
  adb -s "$SERIAL_BOB" shell am start -n com.example.redpanda/.MainActivity >/dev/null
  wait_kv "recv-e2e-s3" 300
  log "S3: catch-up message delivered"
fi

# ---------------------------------------------------------------------------
# S4 orchestration: cut Bob's network (airplane mode), let Alice send into
# the silence, restore the network, measure reconnect delivery.
# ---------------------------------------------------------------------------
if has_scenario s4; then
  log "S4: waiting for Bob to be ready"
  wait_kv bob_ready_s4 900
  # Everything the node logs from here on belongs to the S4 window — the
  # counters slice node.log at this line (T89c).
  S4_NODE_MARK="$(node_log_lines)"
  bob_net down
  sleep 3   # let the disconnect propagate before Alice sends
  kv_put s4-net-down host
  wait_kv "sent-e2e-s4" 300
  # The silence has to outlast the node's ping timeout — see the
  # S4_SILENCE_SEC comment at the top for why this is the whole point of S4.
  log "S4: radio silence for ${S4_SILENCE_SEC}s (node ping timeout ${NODE_PING_TIMEOUT_SEC}s)"
  sleep "$S4_SILENCE_SEC"
  bob_net up
  kv_put s4-net-up host
  wait_kv "recv-e2e-s4" 600
  log "S4: message delivered after reconnect"
fi

# ---------------------------------------------------------------------------
# Wait for both verdicts, then collect the report
# ---------------------------------------------------------------------------
log "waiting for results (max ${RESULT_TIMEOUT_MIN} min)"
deadline=$(( $(date +%s) + RESULT_TIMEOUT_MIN * 60 ))
alice_result=""
bob_result=""
while [[ $(date +%s) -lt $deadline ]]; do
  alice_result="$("${CURL[@]}" "http://127.0.0.1:$COORD_PORT/kv/alice_result" 2>/dev/null || true)"
  bob_result="$("${CURL[@]}" "http://127.0.0.1:$COORD_PORT/kv/bob_result" 2>/dev/null || true)"
  [[ -n "$alice_result" && -n "$bob_result" ]] && break
  # A role that failed hard writes its verdict immediately — no point
  # waiting the full window for the other side once one side reports fail.
  if [[ "$alice_result" == *'"ok":false'* || "$bob_result" == *'"ok":false'* ]]; then
    log "one side reported failure — waiting 30s for the other verdict"
    sleep 30
    alice_result="$("${CURL[@]}" "http://127.0.0.1:$COORD_PORT/kv/alice_result" 2>/dev/null || true)"
    bob_result="$("${CURL[@]}" "http://127.0.0.1:$COORD_PORT/kv/bob_result" 2>/dev/null || true)"
    break
  fi
  sleep 10
done

save_report
[[ -f "$ART/report.json" ]] || die "could not fetch report from coord server"

log "report written to $ART/report.json"
echo "----- latency summary -----"
grep -E '"(latencyMs|p50Ms|p95Ms|maxMs|measured|catchupMs|withinCatchupBudget|silenceMs|reconnectDeliveryMs)"' \
  "$ART/report.json" || true
echo "----- run counters (T89c) -----"
cat "$ART/counters.json" 2>/dev/null || echo "<none>"
echo
echo "---------------------------"
echo "alice: ${alice_result:-<no result>}"
echo "bob:   ${bob_result:-<no result>}"

failures=()
[[ "$alice_result" == *'"ok":true'* ]] || failures+=("alice did not report ok")
[[ "$bob_result" == *'"ok":true'* ]] || failures+=("bob did not report ok")
if has_scenario s1; then
  # Hard acceptance (T82): pairing + first delivery within the S1 budget. Before
  # this, S3 was the only scenario that could fail on a number, which let a
  # 130 s S1 through unnoticed on the dafbb918 gate run.
  # `withinBudget` is null when a marker never arrived — that is "not measured",
  # not "too slow", and reporting it as a missed budget sends whoever reads the
  # log looking for a latency problem that is not there.
  if grep -q '"withinBudget": null' "$ART/report.json"; then
    failures+=("S1 was never measured — a sent-/recv-e2e-s1 marker is missing (see s1 in report.json)")
  elif ! grep -q '"withinBudget": true' "$ART/report.json"; then
    failures+=("S1 pairing + first delivery missed its budget (see s1.latencyMs/budgetMs)")
  fi
fi
# A negative latency anywhere means the measurement itself is broken (T72), not
# that something was fast — never let that read as a pass.
if grep -qE '"latencyMs": -' "$ART/report.json"; then
  failures+=("negative latency in the report — marker timestamps are unreliable")
fi
if has_scenario s3; then
  # Hard acceptance: catch-up after the app restart within the 60 s budget.
  grep -q '"withinCatchupBudget": true' "$ART/report.json" \
    || failures+=("S3 catch-up missed the 60s budget (see s3.catchupMs)")
fi
if has_scenario s4; then
  # Delivery before s4-net-up would mean airplane mode never actually cut
  # the connection — the scenario would not have tested a reconnect.
  if grep -qE '"reconnectDeliveryMs": -' "$ART/report.json"; then
    failures+=("S4 message arrived BEFORE the network was restored — no real disconnect")
  fi
  # T89(a): S4 exists to exercise the reconnect *after* the node has thrown the
  # stale peer away. If no undialable peer was evicted during the silence, the
  # client slotted back into a peer entry that was still alive and the run
  # proved nothing about that path — which is how the 45 s silence used to turn
  # the T88 defect into a once-in-a-while red. This is a harness precondition,
  # not a product defect: the message says so, so nobody goes hunting in the
  # client for it.
  if [[ "$START_NODE" == 1 ]]; then
    if [[ "$S4_EVICTIONS" =~ ^[0-9]+$ && "$S4_EVICTIONS" -gt 0 ]]; then
      log "S4: node evicted $S4_EVICTIONS stale peer(s) during the silence — reconnect path exercised"
    else
      failures+=("S4 precondition (harness): the node evicted no stale peer during the ${S4_SILENCE_SEC}s silence, so the reconnect ran against a still-live peer entry — raise RP_S4_SILENCE_SEC above the node's ping timeout (${NODE_PING_TIMEOUT_SEC}s)")
    fi
  fi
  # Not a failure by itself (the delivery checks above decide that), but the
  # T88 signature is worth spelling out instead of leaving it in node.log.
  if [[ "$S4_DUPLICATES" =~ ^[0-9]+$ && "$S4_DUPLICATES" -gt 0 ]]; then
    log "NOTE: node logged $S4_DUPLICATES duplicate-connection rejection(s) during S4 (T88 signature — see counters.json)"
  fi
fi

if [[ ${#failures[@]} -eq 0 ]]; then
  log "SUCCESS — scenarios passed: $SCENARIOS"
  exit 0
fi
for f in "${failures[@]}"; do log "FAILED: $f"; done
log "check $ART/alice.logcat, $ART/bob.logcat, $ART/node.log"
exit 1
