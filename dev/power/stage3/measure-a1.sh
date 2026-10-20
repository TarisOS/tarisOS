#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 3 A1: PipeWire's audio threads (data-loop.0 of pipewire, pipewire-pulse and WirePlumber,
# which runs the speaker DSP) at Asahi's utilisation clamp, uclamp.max 128, against unclamped
# (1024, what libpipewire's own module-rt leaves them at). The patched module-rt is installed and
# clamps them; between blocks this switches the same running threads with uclampset, nothing
# restarts.
# Two modes:
# - silence (default): digital silence plays through the speakers. Nothing is heard and the
#   speakers get no power, but the DSP runs as with any sound (the convolver's work doesn't
#   depend on what plays; the compressors and limiters do more only while they turn sound down).
#   Three rounds, order alternating, 15 s to settle, then 90 s.
# - music: the maintainer's own music plays through the speakers for the whole run (about 12
#   minutes of it, at their usual volume). The speakers' power follows the music, so the blocks
#   are short and many to spread it evenly over both states: twelve rounds, order alternating,
#   5 s to settle, then 25 s.
# Per block: battery power (coulomb counter), PSTR, PMVR (3.8 V rail: CPU, memory, SSD), PPbb
# (E-cluster), PP0b (P-cluster) every 5 s, the audio threads' CPU time, the E- and P-cluster's
# mean frequency, where the DSP thread last ran (share of 5 s samples on an E-core). PipeWire's
# profiler runs for the whole run (one connection: the speaker device is hidden from pw-top, the
# profiler still reports it) for each block's xruns of the speakers and the DSP's busy time per
# cycle. Checked throughout: every audio thread at the clamp the block asks for, the speakers
# playing.
# Back as found at the end, also if interrupted: every audio thread at 128, the silence (if any)
# and the profiler stopped. Results: results/a1-<mode>-<time>.txt, the raw profiler data in
# /run/taris-a1 until the next run. About 12 minutes.
# Needs: the patched module-rt installed (the audio threads at 128), taris_smc_keys loaded
# (dev/power/smc-keys/test-install.sh), the Mac on battery, the speakers as the output (no
# headphones); for silence, nothing else playing; for music, the music already playing. Run by
# the maintainer, as root, from the desktop session:
#   sudo dev/power/stage3/measure-a1.sh [music]

set -euo pipefail

mode=${1:-silence}
here=$(cd "$(dirname "$0")" && pwd)
speakers=/proc/asound/card1/pcm1p/sub0
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
freq=/sys/devices/system/cpu/cpufreq
rundir=/run/taris-a1
out=$here/results/a1-$mode-$(date +%Y%m%d-%H%M%S).txt

if [[ $mode == "silence" ]]; then
  rounds=3; settle=15; samples=18
elif [[ $mode == "music" ]]; then
  rounds=12; settle=5; samples=5
else
  echo "Usage: sudo $0 [music]" >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
  echo "Start it with sudo from your own account: the audio runs in your session." >&2
  exit 1
fi
shell_pid=$(pgrep -u "$SUDO_USER" -x qs -o || true)
if [[ -z $shell_pid ]]; then
  echo "No Taris shell running for $SUDO_USER: log in to the desktop first." >&2
  exit 1
fi
if [[ ! -r $power ]]; then
  echo "taris_smc_keys isn't loaded: run dev/power/smc-keys/test-install.sh first." >&2
  exit 1
fi
if [[ $(</sys/class/power_supply/macsmc-ac/online) != "0" ]]; then
  echo "Unplug the charger first: the energy comes from the battery's counter." >&2
  exit 1
fi
if [[ ! -r $freq/policy0/stats/time_in_state || ! -r $freq/policy4/stats/time_in_state ]]; then
  echo "No cpufreq statistics for the E- and P-cluster (policy0, policy4)." >&2
  exit 1
fi
if [[ $mode == "music" ]] && ! grep -q 'state: RUNNING' "$speakers/status" 2>/dev/null; then
  echo "The speakers aren't playing: start the music first (speakers as the output)." >&2
  exit 1
fi

# The audio threads: data-loop.0 of each process (WirePlumber has two, one per PipeWire context)
loops=()
for p in pipewire pipewire-pulse wireplumber; do
  pid=$(pgrep -u "$SUDO_USER" -x "$p" -o || true)
  if [[ -z $pid ]]; then
    echo "$p isn't running for $SUDO_USER." >&2
    exit 1
  fi
  for t in /proc/$pid/task/*; do
    if [[ $(<"$t/comm") == "data-loop.0" ]]; then
      loops+=("${t##*/}")
    fi
  done
done
if (( ${#loops[@]} != 4 )); then
  echo "Found ${#loops[@]} audio threads (${loops[*]}), not the 4 expected." >&2
  exit 1
fi

clamp_of() { awk '/effective uclamp.max/ {print $4}' "/proc/$1/sched" 2>/dev/null; }
for t in "${loops[@]}"; do
  if [[ $(clamp_of "$t") != "128" ]]; then
    echo "Audio thread $t isn't at uclamp.max 128: is the patched module-rt installed (and the" \
      "audio services restarted after)?" >&2
    exit 1
  fi
done

mapfile -d '' session_env < "/proc/$shell_pid/environ"
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")
# The profiler's data and the blocks' times stay in $rundir after the run, an interrupted one
# too, until the next run or a restart: a stopped run can still be read
rm -rf "$rundir"
mkdir -p "$here/results" "$rundir"
player=
profiler=

start_player() {
  "${as_user[@]}" pw-cat -p --raw --format s16 --rate 48000 --channels 2 /dev/zero >/dev/null 2>&1 &
  player=$!
}

stop_player() {
  if [[ -n $player ]]; then
    kill "$player" 2>/dev/null || true
    pkill -u "$SUDO_USER" -f '^pw-cat -p --raw' 2>/dev/null || true
    wait "$player" 2>/dev/null || true
    player=
  fi
}

# PipeWire's profiler for the whole run, kept to what's needed: per cycle the speaker device's
# signal time and xrun counter (D), and the DSP's wake-up and finish (F), in CLOCK_MONOTONIC ns
start_profiler() {
  "${as_user[@]}" pw-profiler -J -o /dev/null 2>/dev/null | python3 -I -u -c '
import json, sys
for line in sys.stdin:
    try:
        o = json.loads(line.strip().lstrip("[").rstrip(",]"))
    except ValueError:
        continue
    t, n = o.get("type"), o.get("name")
    if t == "driver" and n == "alsa_output.platform-sound.RawSpeakers":
        print("D", o["signal"], o["xrun_count"])
    elif t == "follower" and n == "effect_output.j293-convolver" and o["status"] == "finished":
        print("F", o["awake"], o["finish"])
' > "$rundir/profile" &
  profiler=$!
}

stop_profiler() {
  if [[ -n $profiler ]]; then
    pkill -u "$SUDO_USER" -x pw-profiler 2>/dev/null || true
    wait "$profiler" 2>/dev/null || true
    profiler=
  fi
}

mono_ns() { python3 -I -c 'import time; print(time.monotonic_ns())'; }

# Every audio thread at the given uclamp.max (min stays 0), checked
set_clamp() {
  local t
  for t in "${loops[@]}"; do
    uclampset -m 0 -M "$1" -p "$t" >/dev/null
    if [[ $(clamp_of "$t") != "$1" ]]; then
      echo "audio thread $t didn't take uclamp.max $1 (has the audio restarted?)" >&2
      return 1
    fi
  done
}

restore() {
  local t
  for t in "${loops[@]}"; do
    uclampset -m 0 -M 128 -p "$t" >/dev/null 2>&1 || true
  done
  stop_player
  stop_profiler
}
trap 'restore; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT

# The DSP thread: the busier of WirePlumber's two audio threads (its other context's carries no
# filters), measured over 2 s of playback
runtime() { awk '{print $1}' "/proc/$1/schedstat"; }
pick_dsp() {
  local b best= max=-1 t
  declare -A a0
  for t in "${loops[@]:2}"; do a0[$t]=$(runtime "$t"); done
  sleep 2
  for t in "${loops[@]:2}"; do
    b=$(( $(runtime "$t") - ${a0[$t]} ))
    if (( b > max )); then max=$b; best=$t; fi
  done
  echo "$best"
}

# Snapshot of running totals: time, battery, the audio threads' CPU time, the clusters' time at
# each frequency
snap() {
  local t
  echo "t ${EPOCHREALTIME/./}"
  echo "q $(<"$bat/charge_counter")"
  echo "v $(<"$bat/voltage_now")"
  for t in "${loops[@]}"; do echo "run.$t $(runtime "$t")"; done
  awk '{print "E." $1, $2}' "$freq/policy0/stats/time_in_state"
  awk '{print "P." $1, $2}' "$freq/policy4/stats/time_in_state"
}

block() {
  local a b smc= ecpu=0 i cpu
  a=$(snap)
  for (( i = 0; i < samples; i++ )); do
    smc+=$(awk '$1 ~ /^(PSTR|PMVR|PPbb|PP0b)$/ {printf "%s %s ", $1, $2}' "$power")$'\n'
    cpu=$(awk '{print $39}' "/proc/$dsp/stat")
    if (( cpu < 4 )); then (( ++ecpu )); fi
    sleep 5
  done
  b=$(snap)
  awk -v dsp="run.$dsp" -v ecpu="$ecpu" -v n="$samples" '
    FILENAME == ARGV[1] {a[$1] = $2; next}
    FILENAME == ARGV[2] {b[$1] = $2; next}
    {for (i = 1; i < NF; i += 2) {smc[$i] += $(i + 1); ns[$i]++}}
    function d(k) {return b[k] - a[k]}
    END {
      dt = d("t") / 1e6
      printf "battery=%.3f", (a["q"] - b["q"]) / 1000 * (a["v"] + b["v"]) / 2e6 / dt
      split("PSTR PMVR PPbb PP0b", keys, " ")
      for (i = 1; i <= 4; i++) printf " %s=%.3f", keys[i], ns[keys[i]] ? smc[keys[i]] / ns[keys[i]] : -1
      for (k in b) {
        if (k ~ /^run\./) loops += d(k)
        split(k, f, ".")
        if (f[1] == "E" || f[1] == "P") {ft[f[1]] += d(k); fs[f[1]] += d(k) * f[2]}
      }
      printf " | loops=%.1fms/s dsp=%.1fms/s E.MHz=%.0f P.MHz=%.0f dsp.onE=%.0f%%", \
        loops / 1e6 / dt, d(dsp) / 1e6 / dt, ft["E"] ? fs["E"] / ft["E"] / 1000 : 0, \
        ft["P"] ? fs["P"] / ft["P"] / 1000 : 0, 100 * ecpu / n
      print ""
    }' <(echo "$a") <(echo "$b") <(echo "$smc")
}

exec > >(tee "$out") 2>&1
echo "# A1 $mode $(date '+%F %T'), kernel $(uname -r), $(pacman -Q libpipewire taris-hardware | tr '\n' ' ')"
echo "# audio threads ${loops[*]}; clamp = at uclamp.max 128, open = at 1024. loops = the audio"
echo "# threads' CPU time; dsp = WirePlumber's DSP thread's; E/P.MHz = the clusters' mean frequency"
echo "# (idle included); dsp.onE = samples with the DSP thread on an E-core"
if [[ $mode == "silence" ]]; then
  start_player
  sleep 3
fi
if ! grep -q 'state: RUNNING' "$speakers/status" 2>/dev/null; then
  echo "The speakers aren't playing (headphones in, or another output chosen): stopping."
  exit 1
fi
start_profiler
dsp=$(pick_dsp)
echo "# DSP thread $dsp"
: > "$rundir/windows"
results=
for (( round = 1; round <= rounds; round++ )); do
  if (( round % 2 == 0 )); then order=(clamp open); else order=(open clamp); fi
  for state in "${order[@]}"; do
    if [[ $state == "clamp" ]]; then max=128; else max=1024; fi
    if ! set_clamp "$max"; then
      echo "round $round $state: couldn't set the clamp; stopping."
      exit 1
    fi
    w0=$(mono_ns)
    sleep "$settle"
    line="round $round $state: $(block)"
    w1=$(mono_ns)
    if ! grep -q 'state: RUNNING' "$speakers/status" 2>/dev/null; then
      echo "round $round $state: the speakers stopped playing; stopping."
      exit 1
    fi
    for t in "${loops[@]}"; do
      if [[ $(clamp_of "$t") != "$max" ]]; then
        echo "round $round $state: audio thread $t changed its clamp during the block; stopping."
        exit 1
      fi
    done
    echo "$line"
    echo "$round $state $w0 $w1" >> "$rundir/windows"
    results+=$line$'\n'
  done
done
stop_profiler
echo
echo "clamp minus open, per round (negative = the clamp uses less):"
printf '%s' "$results" | awk -v rounds="$rounds" '
  {
    r = $2; s = $3; sub(/:$/, "", s)
    for (i = 4; i <= NF; i++) if (split($i, kv, "=") == 2) {sub(/ms\/s$|%$/, "", kv[2]); v[r, s, kv[1]] = kv[2]}
  }
  END {
    n = split("battery PSTR PMVR PPbb PP0b", k, " ")
    for (r = 1; r <= rounds; r++) {
      printf "round %2d:", r
      for (i = 1; i <= n; i++) {
        x = v[r, "clamp", k[i]] - v[r, "open", k[i]]; m[i] += x; m2[i] += x * x
        printf " %s %+.3f W", k[i], x
      }
      print ""
    }
    printf "mean:     "
    for (i = 1; i <= n; i++) {
      mu = m[i] / rounds
      var = rounds > 1 ? (m2[i] - rounds * mu * mu) / (rounds - 1) : 0
      se = var > 0 ? sqrt(var / rounds) : 0
      printf " %s %+.3f W (+-%.3f)", k[i], mu, se
    }
    print ""
  }'
echo
echo "Speakers' xruns and the DSP's busy time per cycle, per block (from PipeWire's profiler):"
python3 -I - "$rundir/windows" "$rundir/profile" <<'EOF'
import sys

windows = [l.split() for l in open(sys.argv[1])]
drv, dsp = [], []
for l in open(sys.argv[2]):
    f = l.split()
    if len(f) == 3 and f[0] == "D":
        drv.append((int(f[1]), int(f[2])))
    elif len(f) == 3 and f[0] == "F" and int(f[2]) >= int(f[1]):
        dsp.append((int(f[1]), (int(f[2]) - int(f[1])) / 1e3))
if not drv:
    print("  no profiler data (the profiler didn't run)")
    sys.exit(0)
tot = {}
for r, s, w0, w1 in windows:
    w0, w1 = int(w0), int(w1)
    before = [x for t, x in drv if t < w0]
    inside = [x for t, x in drv if w0 <= t < w1]
    busy = [b for t, b in dsp if w0 <= t < w1]
    xr = (inside[-1] - (before[-1] if before else inside[0])) if inside else 0
    st = tot.setdefault(s, [0, [], 0])
    st[0] += xr; st[1] += busy; st[2] += len(inside)
    print("  round %2s %-5s cycles %5d  xruns %d  DSP busy mean %4.0f us, max %5.0f us"
          % (r, s, len(inside), xr, sum(busy) / len(busy) if busy else 0, max(busy) if busy else 0))
for s, (xr, busy, cyc) in sorted(tot.items()):
    busy.sort()
    print("  %-5s total: cycles %6d  xruns %d  DSP busy mean %4.0f us, 99%% %5.0f us, max %5.0f us"
          % (s, cyc, xr, sum(busy) / len(busy) if busy else 0,
             busy[int(0.99 * (len(busy) - 1))] if busy else 0, busy[-1] if busy else 0))
print("  whole run: xruns %d -> %d" % (drv[0][1], drv[-1][1]))
EOF
