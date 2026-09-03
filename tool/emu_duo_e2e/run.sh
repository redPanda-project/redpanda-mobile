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
# Guest RAM per AVD. T101 finding: this knob was DEAD until 2026-08-24 —
# tune_avd wrote the wrong config key (`hw.ram.size`; canonical is
# `hw.ramSize`), and even the right key gets clamped UP by the emulator
# ("Increasing RAM size to 2560MB" for this API 35 image), so every "1536/
# 1280/1024" run of the past actually booted a 2.5 GB guest and each qemu
# grew to ~2.9-3.3 GB resident — which is why an 8 GB host with a desktop
# session kept losing an emulator to the OOM killer ("Getötet" in the run
# log, `Out of memory: Killed process ... qemu-system-x86` in dmesg; on
# hosts with systemd-oomd the whole run gets SIGTERMed instead). The only
# thing that beats the clamp is handing qemu the size directly
# (`-qemu -m`, see boot_avd), which run.sh now does. Measured on this host
# (single AVD, booted + settled): guest 988 MB, qemu RSS 1.68 GB — the
# qemu-side overhead on top of guest RAM is ~0.7 GB. 1024 leaves the guest
# ~260 MB available after boot before the app starts; go lower only if you
# enjoy watching Android's lowmemorykiller take the app instead.
AVD_RAM_MB="${RP_AVD_RAM_MB:-1024}"
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
  # Summarize only when THIS invocation started the sampler — a pre-flight
  # abort would otherwise report a stale mem.csv from a previous run as if
  # it were this run's telemetry (Copilot finding, PR #101).
  if [[ -n "${MEM_SAMPLER_PID:-}" ]]; then
    kill "$MEM_SAMPLER_PID" 2>/dev/null
    wait "$MEM_SAMPLER_PID" 2>/dev/null
    log "mem (T101): $(summarize_mem)"
  fi
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

# node.log line count taken immediately before S4 cuts Bob's radio — the S4
# slice is everything after it. Counting lines instead of matching timestamps
# keeps this independent of the node's clock and log format.
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
  printf '"lmkdKills": %s, ' \
    "$(count_pat "$f" "lmkd")"
  printf '"hostNodeNotConnected": %s, "noActivePeer": %s, "pollCycles": %s, "testTimeouts": %s}' \
    "$(count_pat "$f" 'not connected — requesting a connection')" \
    "$(count_pat "$f" 'fetchMessages() no active peer available')" \
    "$(count_pat "$f" 'poll cycle fetched')" \
    "$(count_pat "$f" 'TIMEOUT waiting for')"
}

collect_counters() {
  local log="$ART/node.log"
  local dup_total dup_s4 evict_total evict_s4 act enc conn exc s4slice
  # T101/TD040: one guest-side + host-side snapshot per run, to tell guest
  # page cache from qemu overhead when the RSS numbers look bad. Best-effort —
  # on the failure path the emulators may already be gone.
  local pair mrole mserial mavd mpid
  for pair in "alice:$SERIAL_ALICE:rp_alice" "bob:$SERIAL_BOB:rp_bob"; do
    IFS=: read -r mrole mserial mavd <<<"$pair"
    adb -s "$mserial" shell cat /proc/meminfo >"$ART/guest-meminfo-$mrole.txt" 2>/dev/null || true
    # Heaviest match, not first PID: a light launcher/wrapper process can
    # share the cmdline fragment with the actual qemu engine.
    mpid="$(for mp in $(pgrep -f -- "avd $mavd" 2>/dev/null || true); do
      echo "$(awk '/^VmRSS:/{print $2}' "/proc/$mp/status" 2>/dev/null || echo 0) $mp"
    done | sort -rn | head -1 | cut -d' ' -f2)"
    [[ -n "$mpid" ]] && { cat "/proc/$mpid/smaps_rollup" >"$ART/qemu-smaps-$mrole.txt" 2>/dev/null || true; }
  done
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
    # T119: the cut verification, in the artifact. `checks: 0` means S4 never
    # got to the silence; `method: null` means no probe was selected at all.
    printf '"s4Probe": {"method": %s, "target": "%s:%s", "checks": %s, "breaches": %s, "firstBreachSec": %s}, ' \
      "$([[ -n "$PROBE_CMD" ]] && printf '"%s"' "$PROBE_CMD" || echo null)" \
      "$PROBE_HOST" "$COORD_PORT" "$PROBE_CHECKS" "$PROBE_BREACHES" \
      "${PROBE_FIRST_BREACH_SEC:-null}"
    printf '"clients": {"alice": %s, "bob": %s}}' \
      "$(client_counters_json "$ART/alice.logcat")" \
      "$(client_counters_json "$ART/bob.logcat")"
  } >"$ART/counters.json"

  # Non-fatal on purpose: this runs on the failure path too, where the coord
  # server may already be gone — counters.json on disk is still the artifact.
  "${CURL[@]}" -X PUT --data-binary "@$ART/counters.json" \
    "http://127.0.0.1:$COORD_PORT/kv/harness_counters" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# T101: memory sampler — one CSV line every 5 s so an OOM (or a near miss)
# leaves numbers behind instead of folklore. The peaks feed the run log (also
# on the failure path, via cleanup) and calibrated QEMU_OVERHEAD_MB above.
# ---------------------------------------------------------------------------
MEM_SAMPLER_PID=""
rss_mb_of() { # pgrep -f pattern -> summed RSS in MB (0 when absent)
  local p kb=0 v
  for p in $(pgrep -f -- "$1" 2>/dev/null || true); do
    v="$(awk '/^VmRSS:/ {print $2}' "/proc/$p/status" 2>/dev/null)" || v=""
    kb=$(( kb + ${v:-0} ))
  done
  echo $(( kb / 1024 ))
}
start_mem_sampler() {
  echo "elapsedSec,memAvailableMB,swapFreeMB,aliceRssMB,bobRssMB,nodeRssMB" >"$ART/mem.csv"
  local t0
  t0=$(date +%s)
  (
    # The subshell inherits `set -e`: without the guards a single transient
    # failure (a /proc entry vanishing mid-read) would silently end the
    # sampler for the rest of a 45-min run.
    set +e
    while :; do
      echo "$(( $(date +%s) - t0 )),$(( $(mem_kb MemAvailable) / 1024 )),$(( $(mem_kb SwapFree) / 1024 )),$(rss_mb_of "avd rp_alice"),$(rss_mb_of "avd rp_bob"),$(rss_mb_of "redpanda\.jar")" >>"$ART/mem.csv" || true
      sleep 5
    done
  ) &
  MEM_SAMPLER_PID=$!
}
summarize_mem() { # -> one line: per-process peaks + min MemAvailable
  [[ -s "$ART/mem.csv" ]] || { echo "no samples"; return 0; }
  awk -F, 'NR>1 { if ($4>a) a=$4; if ($5>b) b=$5; if ($6>n) n=$6; if (m=="" || $2<m) m=$2 }
    END { printf "peak RSS MB: alice=%d bob=%d node=%d (pair=%d); min MemAvailable=%d MB", a, b, n, a+b, m }' "$ART/mem.csv"
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

# ---------------------------------------------------------------------------
# S4 network cut on Bob.
#
# ROOT CAUSE, T119 (gate red on main 2026-09-03): `cmd connectivity
# airplane-mode enable` alone does NOT produce a blackout on these emulator
# images. The API 35 google_apis image boots TWO default-capable networks:
# WIFI (`wlan0`, AndroidWifi) and CELLULAR (`eth0`, the qemu slirp NIC, route
# `0.0.0.0/0 -> 10.0.2.2`, APN fast.t-mobile.com). Airplane mode tears them
# down asynchronously and NOT in lockstep: Wi-Fi goes first, and for as long as
# the modem takes to actually power off, ConnectivityService *promotes the
# still-connected cellular network to default* — i.e. 10.0.2.2 is fully
# reachable again a few seconds into the supposed silence. From Bob's logcat:
#
#   red run 33771942708   15:13:27 airplane enable
#                         15:13:35 [100 WIFI] disconnected
#                         15:13:37 networkSetDefault(101)  <- CELLULAR/eth0
#                         15:13:38 CONNECTED broadcast [101 CELLULAR]
#                         15:13:46 node.log: new incoming connection from Bob
#                         15:13:55 [101 CELLULAR] disconnected   (18 s late)
#   green run 33726760277 07:22:20 airplane enable
#                         07:22:25 [100 WIFI] disconnected
#                         07:22:29 networkSetDefault(101)  <- same promotion
#                         07:22:32 [101 CELLULAR] disconnected   (3 s, in time)
#
# So the green runs were green by 3 seconds of luck; nothing about the client
# changed. The fix is to take both transports down explicitly instead of
# relying on the airplane-mode teardown order, and — more importantly — to
# verify the *effect* rather than the mechanism (see bob_can_reach_host).
#
# The old verification (`ping -c1 -W1 10.0.2.2` until it fails) was vacuous:
# it broke out of its wait loop on the FIRST iteration in every run we have
# artifacts for, green and red alike, i.e. while Wi-Fi was still up and the
# app was still exchanging messages — ICMP to the slirp gateway simply never
# answers here. A check that cannot succeed cannot detect a failure to cut.
# ---------------------------------------------------------------------------
bob_net() { # down|up
  if [[ "$1" == up ]]; then
    # Airplane mode off FIRST: while it is on, `svc wifi/data enable` is a
    # no-op, so the other order would leave both transports disabled.
    adb -s "$SERIAL_BOB" shell cmd connectivity airplane-mode disable \
      || die "airplane-mode disable failed on $SERIAL_BOB"
    adb -s "$SERIAL_BOB" shell svc wifi enable >/dev/null 2>&1 || true
    adb -s "$SERIAL_BOB" shell svc data enable >/dev/null 2>&1 || true
  else
    # Both transports explicitly, then airplane mode. `svc` failures are not
    # fatal on purpose: airplane mode stays the primary mechanism and the
    # probe below decides whether the cut actually happened — enforce the
    # effect, never the mechanism.
    adb -s "$SERIAL_BOB" shell svc data disable >/dev/null 2>&1 || true
    adb -s "$SERIAL_BOB" shell svc wifi disable >/dev/null 2>&1 || true
    adb -s "$SERIAL_BOB" shell cmd connectivity airplane-mode enable \
      || die "airplane-mode enable failed on $SERIAL_BOB"
  fi
  log "S4: net $1 -> airplane-mode: $(adb -s "$SERIAL_BOB" shell cmd connectivity airplane-mode | tr -d '\r')"
}

# ---------------------------------------------------------------------------
# Guest-side TCP reachability probe (T119): can Bob's guest still open a TCP
# connection to this host? That is the one question the S4 cut is about, and
# unlike ICMP it is answered by the same path the app uses.
#
# Target is the coord server port, not the node's 59558, deliberately: a bare
# connect to the node makes it accept a peer, log `incoming connection from
# ip: 127.0.0.1` and later evict it as undialable — which would inflate
# `undialableEvictions.duringS4`, the very counter the T89(a) S4 precondition
# reads. Both ports are host loopback behind the same 10.0.2.2 gateway, so
# reachability is identical; only the side effects differ. The coord server is
# a Dart HttpServer and logs nothing for a connect-and-close.
# ---------------------------------------------------------------------------
PROBE_HOST="10.0.2.2"
# Filled by select_probe(); every candidate must exit 0 exactly when the guest
# can reach the host. `nc` and `wget` are toybox applets and should be there on
# any API 30+ image; the `ip route get` candidate is the belt-and-braces last
# resort (always present, and a route to 10.0.2.2 over a live interface is
# exactly what the promoted CELLULAR/eth0 network re-created in the T119
# breakage), so "no probe available" cannot become a reason to run S4 blind.
PROBE_CMD=""
PROBE_CHECKS=0
PROBE_BREACHES=0
PROBE_FIRST_BREACH_SEC=""

run_probe() { # probe_cmd -> 0 when the host is reachable from Bob's guest
  local out
  # `|| out=""` so this is a predicate in every context, not just inside an
  # `if`/`&&`/`||` (which is where `set -e` happens to be suppressed today):
  # with `pipefail` on, an adb hiccup would otherwise take the assignment's
  # exit status and, from a bare call site, the whole harness with it. An adb
  # failure reads as "not reachable" — the safe direction for the wait-for-cut
  # loop, and a breach that adb was too busy to observe shows up on the next
  # of the ~28 probes in the silence anyway.
  out="$(adb -s "$SERIAL_BOB" shell "$1 >/dev/null 2>&1; echo rc=\$?" 2>/dev/null | tr -d '\r')" || out=""
  [[ "$out" == "rc=0" ]]
}

# Picks a probe that demonstrably WORKS while the network is up. Running this
# before the cut is what keeps the check from silently going vacuous the way
# the ping loop did: if no candidate can reach the host now, we abort instead
# of "verifying" the cut with a command that always fails.
select_probe() {
  local c
  for c in "nc -w 2 $PROBE_HOST $COORD_PORT </dev/null" \
           "toybox nc -w 2 $PROBE_HOST $COORD_PORT </dev/null" \
           "toybox wget -T 2 -O /dev/null http://$PROBE_HOST:$COORD_PORT/kv/scenarios" \
           "ip route get $PROBE_HOST"; do
    if run_probe "$c"; then
      PROBE_CMD="$c"
      log "S4: TCP probe in Bob's guest: '$c' (verified reachable before the cut)"
      return 0
    fi
  done
  return 1
}

bob_can_reach_host() { run_probe "$PROBE_CMD"; }

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
# T101: host RAM pre-flight — fail fast HERE instead of letting the kernel
# OOM killer shoot a qemu mid-scenario after ~15 min of build+boot (three
# gate runs died that way on 2026-08-17; the resulting verdict looks nothing
# like a finding). Budget: 2 x (guest RAM + measured qemu overhead) + node
# heap + headroom. Half of the free swap is credited: cold guest pages
# (zygote preloads, dead app heaps) swap out fine, and MemAvailable alone
# underestimates what a run survives (2026-08-18 evidence: green gate with
# ~5.3 GB free). Override with RP_MIN_AVAIL_MB; 0 disables the check.
# RSS(qemu) minus guest RAM, measured ~0.7 GB + margin — calibrated at
# 1024 MB guests on this host; NOT proportional to guest size. Re-measure
# via mem.csv before trusting the pre-flight with a much larger RP_AVD_RAM_MB.
QEMU_OVERHEAD_MB=800
# A non-numeric override must die loudly: `[[ "$MIN_AVAIL_MB" -gt 0 ]]` with
# a non-integer merely returns false under `if`, which would silently skip
# exactly the safety check this exists for.
[[ "$AVD_RAM_MB" =~ ^[0-9]+$ ]] || die "RP_AVD_RAM_MB must be a number of MB (got '$AVD_RAM_MB')"
MIN_AVAIL_MB="${RP_MIN_AVAIL_MB:-$(( 2 * (AVD_RAM_MB + QEMU_OVERHEAD_MB) + 512 + 256 ))}"
[[ "$MIN_AVAIL_MB" =~ ^[0-9]+$ ]] || die "RP_MIN_AVAIL_MB must be a number of MB, 0 disables (got '$MIN_AVAIL_MB')"
mem_kb() { # -> value in kB, 0 when the key is missing (empty would be a fatal arithmetic syntax error)
  local v
  v="$(awk -v k="$1:" '$1 == k {print $2}' /proc/meminfo 2>/dev/null)" || v=""
  echo "${v:-0}"
}
if [[ "$MIN_AVAIL_MB" -gt 0 ]]; then
  MEM_AVAILABLE_MB=$(( $(mem_kb MemAvailable) / 1024 ))
  SWAP_FREE_MB=$(( $(mem_kb SwapFree) / 1024 ))
  EFFECTIVE_MB=$(( MEM_AVAILABLE_MB + SWAP_FREE_MB / 2 ))
  [[ "$EFFECTIVE_MB" -ge "$MIN_AVAIL_MB" ]] || die "not enough free RAM for the duo gate: MemAvailable ${MEM_AVAILABLE_MB} MB + SwapFree/2 (${SWAP_FREE_MB}/2) MB = ${EFFECTIVE_MB} MB effective, threshold ${MIN_AVAIL_MB} MB (= 2 AVDs x (${AVD_RAM_MB} MB guest + ~${QEMU_OVERHEAD_MB} MB qemu overhead) + node + headroom).
Close desktop apps (browsers are the usual offender) and retry — or lower RP_AVD_RAM_MB / override RP_MIN_AVAIL_MB if you know better."
  log "RAM pre-flight ok: MemAvailable ${MEM_AVAILABLE_MB} MB + SwapFree/2 -> ${EFFECTIVE_MB} MB effective (threshold ${MIN_AVAIL_MB} MB)"
fi
SCENARIOS="$(echo "$SCENARIOS" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
for s in ${SCENARIOS//,/ }; do
  [[ "$s" =~ ^s[1-4]$ ]] || die "unknown scenario '$s' in RP_SCENARIOS (allowed: s1,s2,s3,s4)"
done
has_scenario s1 || SCENARIOS="s1,$SCENARIOS"  # s1 is the pairing foundation
[[ "$S4_SILENCE_SEC" =~ ^[0-9]+$ ]] || die "RP_S4_SILENCE_SEC must be a number of seconds"
[[ "$NODE_PING_TIMEOUT_SEC" =~ ^[0-9]+$ ]] \
  || die "RP_NODE_PING_TIMEOUT_SEC must be a number of seconds"
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
      "$ART"/node.log "$ART"/coord.log "$ART"/mem.csv \
      "$ART"/guest-meminfo-*.txt "$ART"/qemu-smaps-*.txt
start_mem_sampler   # T101: covers the build phase too — gradle is a RAM hog

# ---------------------------------------------------------------------------
# AVDs (created once, reused afterwards)
# ---------------------------------------------------------------------------
tune_avd() { # name
  local cfg="$HOME/.android/avd/$1.avd/config.ini"
  [[ -f "$cfg" ]] || die "AVD config not found: $cfg"
  # T101: `hw.ramSize` is the canonical key. Earlier versions appended the
  # non-key `hw.ram.size`, which the emulator silently ignored; avdmanager
  # also seeds `hw.ramSize = 96M` (spaces around '='). Purge both spellings,
  # then write ours. The emulator clamps this value up to the image minimum
  # (2560 MB here) anyway — the effective size comes from `-qemu -m` in
  # boot_avd; the config entry documents intent and keeps tooling honest.
  sed -i -E '/^hw\.ramSize[ =]/d; /^hw\.ram\.size[ =]/d' "$cfg"
  for kv in "hw.ramSize=$AVD_RAM_MB" "hw.cpu.ncore=2" "hw.keyboard=yes" \
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
  # `-qemu -m` (must stay the LAST arguments) instead of `-memory`: the
  # emulator clamps both `-memory` and hw.ramSize up to the image minimum
  # (2560 MB — "Increasing RAM size to 2560MB" in emulator-*.log). Passing
  # the size straight to qemu is the only override that sticks; measured
  # guest MemTotal 988 MB at 1024 vs 2532 MB via the clamped path (T101).
  emulator -avd "$1" -port "$2" \
    -no-window -no-audio -no-snapshot -no-boot-anim -no-metrics \
    -gpu swiftshader_indirect -cores 2 -qemu -m "$AVD_RAM_MB" \
    >"$ART/emulator-$1.log" 2>&1 &
  timeout 300 adb -s "$3" wait-for-device || die "AVD $1 never appeared on adb ($3)"
  local booted=""
  for _ in $(seq 1 180); do
    booted="$(adb -s "$3" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$booted" == "1" ]] && break
    sleep 2
  done
  [[ "$booted" == "1" ]] || die "AVD $1 did not finish booting within 6 minutes"
  # T101: the -qemu -m override beats the emulator's clamped value only by
  # "last -m wins", which is measured behaviour, not documented qemu API —
  # verify the guest really got the requested size so a regression shows up
  # as a WARNING here instead of as an unexplained OOM later.
  local guest_total_kb guest_mb
  guest_total_kb="$(adb -s "$3" shell cat /proc/meminfo 2>/dev/null | awk '/^MemTotal:/{print $2}')" || guest_total_kb=""
  if [[ "$guest_total_kb" =~ ^[0-9]+$ ]]; then
    guest_mb=$(( guest_total_kb / 1024 ))
    log "AVD $1 guest MemTotal: ${guest_mb} MB (requested $AVD_RAM_MB)"
    if (( guest_mb > AVD_RAM_MB + AVD_RAM_MB / 4 )); then
      log "WARNING: guest RAM is >25% above the requested size — the -qemu -m override did not stick; expect ~$(( guest_mb + QEMU_OVERHEAD_MB )) MB RSS for this emulator"
    fi
  fi
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
  # Taken just before the cut, so the S4 slice starts one moment early rather
  # than one moment late: the counters must not miss an eviction because the
  # node logged it while `bob_net down` was still returning (T89c).
  S4_NODE_MARK="$(node_log_lines)"
  # Prove the probe works while the network is still up — see select_probe().
  select_probe \
    || die "S4: no working TCP probe inside Bob's guest (tried nc, toybox nc, toybox wget against $PROBE_HOST:$COORD_PORT while the network was UP) — the airplane-mode cut cannot be verified, refusing to run S4 blind"
  bob_net down
  # A fixed sleep here is a race: `airplane-mode enable` returns (and reports
  # "enabled") before the guest's network teardown has actually severed the
  # established TCP socket to the node. On a loaded host that teardown took
  # >3 s and Alice's S4 message slipped through the still-open connection,
  # arriving DURING the blackout (gate run 2026-08-18, reconnectDeliveryMs
  # -90661). Verify from inside Bob's guest that the host is unreachable
  # before green-lighting Alice.
  for _ in $(seq 1 30); do
    bob_can_reach_host || break
    sleep 1
  done
  bob_can_reach_host \
    && die "S4: $PROBE_HOST:$COORD_PORT still reachable from Bob's guest 30s after the cut — cut ineffective (T119: check whether CELLULAR/eth0 is still the default network, \`adb -s $SERIAL_BOB shell dumpsys connectivity | head -40\`)"
  kv_put s4-net-down host
  wait_kv "sent-e2e-s4" 300
  # The silence has to outlast the node's ping timeout — see the
  # S4_SILENCE_SEC comment at the top for why this is the whole point of S4.
  # T119: probing across the WHOLE silence, not just once at the start. The
  # 2026-09-03 breakage was a transport that came back 10 s in, long after a
  # one-shot check had already green-lit Alice.
  log "S4: radio silence for ${S4_SILENCE_SEC}s (node ping timeout ${NODE_PING_TIMEOUT_SEC}s), probing reachability throughout"
  s4_silence_start=$(date +%s)
  s4_silence_end=$(( s4_silence_start + S4_SILENCE_SEC ))
  while [[ $(date +%s) -lt $s4_silence_end ]]; do
    PROBE_CHECKS=$(( PROBE_CHECKS + 1 ))
    if bob_can_reach_host; then
      PROBE_BREACHES=$(( PROBE_BREACHES + 1 ))
      if [[ -z "$PROBE_FIRST_BREACH_SEC" ]]; then
        PROBE_FIRST_BREACH_SEC=$(( $(date +%s) - s4_silence_start ))
        log "S4 BREACH: $PROBE_HOST:$COORD_PORT reachable again ${PROBE_FIRST_BREACH_SEC}s into the silence — the cut did not hold (T119)"
      fi
    fi
    sleep 3
  done
  log "S4: silence over — probe checks: $PROBE_CHECKS, breaches: $PROBE_BREACHES"
  bob_net up
  kv_put s4-net-up host
  # The reconnect can only be measured if the network really comes back. A
  # bounded check here turns "restore silently did not work" into one clear
  # line instead of a 10-minute wait_kv timeout further down.
  s4_restore_deadline=$(( $(date +%s) + 60 ))
  while [[ $(date +%s) -lt $s4_restore_deadline ]]; do
    bob_can_reach_host && break
    sleep 2
  done
  bob_can_reach_host \
    || die "S4: $PROBE_HOST:$COORD_PORT still unreachable from Bob's guest 60s after the restore — airplane-mode disable / svc enable did not bring the network back"
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
  # T119: the direct statement of the same defect, from the harness side. It
  # names the second when the blackout ended, which the delivery timestamps
  # cannot: a breach at +10 s and a breach at +80 s look identical in
  # reconnectDeliveryMs, and only one of them is the transport-promotion bug.
  if [[ "$PROBE_BREACHES" -gt 0 ]]; then
    failures+=("S4 cut did not hold (harness): Bob's guest reached $PROBE_HOST:$COORD_PORT again ${PROBE_FIRST_BREACH_SEC}s into the ${S4_SILENCE_SEC}s silence ($PROBE_BREACHES of $PROBE_CHECKS probes succeeded) — the blackout was not a blackout, see the T119 root-cause comment at bob_net()")
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
