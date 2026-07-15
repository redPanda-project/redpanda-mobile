#!/usr/bin/env bash
# Emulator duo E2E harness (T23): two headless Android emulators (Alice +
# Bob) chat with each other through a LOCAL backend node on this host.
# See README.md in this directory for prerequisites and details.
#
# Usage:
#   tool/emu_duo_e2e/run.sh              # local node (default, deterministic)
#   tool/emu_duo_e2e/run.sh --testnet    # against the live testnet seeds
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
APK="$REPO/build/app/outputs/flutter-apk/app-debug.apk"
ART="$REPO/build/e2e-artifacts"
RESULT_TIMEOUT_MIN="${RP_TIMEOUT_MIN:-45}"

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

mkdir -p "$ART"
rm -f "$ART"/report.json "$ART"/alice.logcat "$ART"/bob.logcat "$ART"/node.log "$ART"/coord.log

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
(cd "$REPO" && flutter build apk --debug \
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
  # The blackhole seed (discard port, nothing listens) isolates the node:
  # the jar's default known-nodes list would connect it to other local or
  # testnet nodes, whose gossiped peer addresses (e.g. 127.0.0.1:59558) are
  # wrong or unreachable from inside an emulator and send garlic routes /
  # deposits into the void. An EMPTY list does not work -- Settings falls
  # back to the defaults when the parsed list is empty.
  (cd "$NODE_DIR" && PORT="$NODE_PORT" REDPANDA_KNOWN_NODES="127.0.0.1:9" \
    exec java -jar "$JAR") >"$ART/node.log" 2>&1 &
  NODE_PID=$!
  wait_port "$NODE_PORT" "backend node" 60
fi

log "starting coord server on port $COORD_PORT"
dart "$REPO/tool/emu_duo_e2e/coord_server.dart" "$COORD_PORT" >"$ART/coord.log" 2>&1 &
COORD_PID=$!
wait_port "$COORD_PORT" "coord server" 30

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
# Wait for both verdicts, then collect the report
# ---------------------------------------------------------------------------
log "waiting for results (max ${RESULT_TIMEOUT_MIN} min)"
deadline=$(( $(date +%s) + RESULT_TIMEOUT_MIN * 60 ))
alice_result=""
bob_result=""
while [[ $(date +%s) -lt $deadline ]]; do
  alice_result="$(curl -fs "http://127.0.0.1:$COORD_PORT/kv/alice_result" 2>/dev/null || true)"
  bob_result="$(curl -fs "http://127.0.0.1:$COORD_PORT/kv/bob_result" 2>/dev/null || true)"
  [[ -n "$alice_result" && -n "$bob_result" ]] && break
  # A role that failed hard writes its verdict immediately — no point
  # waiting the full window for the other side once one side reports fail.
  if [[ "$alice_result" == *'"ok":false'* || "$bob_result" == *'"ok":false'* ]]; then
    log "one side reported failure — waiting 30s for the other verdict"
    sleep 30
    alice_result="$(curl -fs "http://127.0.0.1:$COORD_PORT/kv/alice_result" 2>/dev/null || true)"
    bob_result="$(curl -fs "http://127.0.0.1:$COORD_PORT/kv/bob_result" 2>/dev/null || true)"
    break
  fi
  sleep 10
done

curl -fs "http://127.0.0.1:$COORD_PORT/report" >"$ART/report.json" \
  || die "could not fetch report from coord server"

log "report written to $ART/report.json"
echo "----- latency summary -----"
grep -E '"(latencyMs|p50Ms|p95Ms|maxMs|measured)"' "$ART/report.json" || true
echo "---------------------------"
echo "alice: ${alice_result:-<no result>}"
echo "bob:   ${bob_result:-<no result>}"

if [[ "$alice_result" == *'"ok":true'* && "$bob_result" == *'"ok":true'* ]]; then
  log "SUCCESS — both roles passed S1 + S2"
  exit 0
fi
log "FAILED — check $ART/alice.logcat, $ART/bob.logcat, $ART/node.log"
exit 1
