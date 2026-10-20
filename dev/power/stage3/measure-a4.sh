#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 3 A4: what a longer PipeWire cycle is worth while sound plays through the speakers. The
# graph runs once per quantum; with 44.1 kHz music it can't pass 1024 frames today (the 2048-frame
# max-quantum is set at 48 kHz, scales to 1881 and rounds down to a power of two). This forces
# 1024, 2048 and 4096 frames in turn through PipeWire's settings (clock.force-quantum, live, no
# restart) while the maintainer's own audio plays at their usual volume.
# Six rounds, each state once per round, the order rotated and reversed so every state takes
# every place twice; 5 s to settle, then 25 s: battery power (coulomb counter), PSTR, PMVR (3.8 V
# rail: CPU, memory, SSD), PPbb (E-cluster), PP0b (P-cluster) every 5 s, PipeWire's and
# WirePlumber's context switches (all their threads), the audio DMA's interrupts, the E-cores'
# share of idle in deep idle and their wake-up IPIs. PipeWire's profiler runs for the whole run
# (one connection) for each block's cycle length (to confirm the forced quantum), the speakers'
# xruns and the DSP's busy time. Checked throughout: the speakers playing.
# Back as found at the end, also if interrupted: clock.force-quantum as it was, the profiler
# stopped. Results: results/a4-<time>.txt, the raw profiler data in /run/taris-a4 until the next
# run. About 9 minutes.
# Needs: taris_smc_keys loaded (dev/power/smc-keys/test-install.sh), the Mac on battery, the
# speakers as the output (no headphones), steady audio already playing (offline, ~10 minutes
# without gaps, autoplay off). Run by the maintainer, as root, from the desktop session:
#   sudo dev/power/stage3/measure-a4.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
speakers=/proc/asound/card1/pcm1p/sub0
irqname=238200000.dma-controller
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
cpus=/sys/devices/system/cpu
rundir=/run/taris-a4
out=$here/results/a4-$(date +%Y%m%d-%H%M%S).txt
rounds=6; settle=5; samples=5
states=(1024 2048 4096)

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
if ! grep -q " $irqname\$" /proc/interrupts; then
  echo "No interrupt line named $irqname: the audio DMA's line has changed." >&2
  exit 1
fi
if ! grep -q 'state: RUNNING' "$speakers/status" 2>/dev/null; then
  echo "The speakers aren't playing: start the audio first (speakers as the output)." >&2
  exit 1
fi
pw_pid=$(pgrep -u "$SUDO_USER" -x pipewire -o || true)
wp_pid=$(pgrep -u "$SUDO_USER" -x wireplumber -o || true)
if [[ -z $pw_pid || -z $wp_pid ]]; then
  echo "pipewire or wireplumber isn't running for $SUDO_USER." >&2
  exit 1
fi

mapfile -d '' session_env < "/proc/$shell_pid/environ"
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")

# PipeWire's live settings: clock.force-quantum, 0 when nothing is forced
force_of() {
  "${as_user[@]}" pw-metadata -n settings 0 clock.force-quantum 2>/dev/null |
    sed -n "s/.*key:'clock.force-quantum' value:'\([0-9]*\)'.*/\1/p"
}
force0=$(force_of)
if [[ -z $force0 ]]; then
  echo "Can't read clock.force-quantum from PipeWire's settings." >&2
  exit 1
fi
set_force() { "${as_user[@]}" pw-metadata -n settings 0 clock.force-quantum "$1" >/dev/null; }

# The profiler's data and the blocks' times stay in $rundir after the run, an interrupted one
# too, until the next run or a restart: a stopped run can still be read
rm -rf "$rundir"
mkdir -p "$here/results" "$rundir"
profiler=

# PipeWire's profiler for the whole run, kept to what's needed, in CLOCK_MONOTONIC ns: per cycle
# its length (C), the speaker device's xrun counter (D), the DSP's wake-up and finish (F)
start_profiler() {
  "${as_user[@]}" pw-profiler -J -o /dev/null 2>/dev/null | python3 -I -u -c '
import json, sys
for line in sys.stdin:
    try:
        o = json.loads(line.strip().lstrip("[").rstrip(",]"))
    except ValueError:
        continue
    t, n = o.get("type"), o.get("name")
    if t == "clock" and n.startswith("api.alsa.p-"):
        print("C", o["nsec"], o["duration"])
    elif t == "driver" and n == "alsa_output.platform-sound.RawSpeakers":
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

restore() {
  set_force "$force0" 2>/dev/null || true
  stop_profiler
}
trap 'restore; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT

mono_ns() { python3 -I -c 'import time; print(time.monotonic_ns())'; }
irqs() { awk -v n="$irqname" '$NF == n {s = 0; for (i = 2; i <= 9; i++) s += $i; print s}' /proc/interrupts; }
# Context switches of every thread of a process
ctx() { cat /proc/"$1"/task/*/status 2>/dev/null | awk '/ctxt_switches/ {s += $2} END {print s}'; }

# Snapshot of running totals: time, battery, the audio processes, the DMA, the E-cores
snap() {
  local c
  echo "t ${EPOCHREALTIME/./}"
  echo "q $(<"$bat/charge_counter")"
  echo "v $(<"$bat/voltage_now")"
  echo "pw $(ctx "$pw_pid")"
  echo "wp $(ctx "$wp_pid")"
  echo "irq $(irqs)"
  for c in 0 1 2 3; do
    echo "c$c.s0 $(<"$cpus/cpu$c/cpuidle/state0/time")"
    echo "c$c.s1 $(<"$cpus/cpu$c/cpuidle/state1/time")"
  done
  awk '$1 == "IPI0:" || $1 == "IPI1:" {for (i = 2; i <= 5; i++) s += $i} END {print "ipi", s}' \
    /proc/interrupts
}

block() {
  local a b smc= i
  a=$(snap)
  for (( i = 0; i < samples; i++ )); do
    smc+=$(awk '$1 ~ /^(PSTR|PMVR|PPbb|PP0b)$/ {printf "%s %s ", $1, $2}' "$power")$'\n'
    sleep 5
  done
  b=$(snap)
  awk '
    FILENAME == ARGV[1] {a[$1] = $2; next}
    FILENAME == ARGV[2] {b[$1] = $2; next}
    {for (i = 1; i < NF; i += 2) {smc[$i] += $(i + 1); ns[$i]++}}
    function d(k) {return b[k] - a[k]}
    END {
      dt = d("t") / 1e6
      printf "battery=%.3f", (a["q"] - b["q"]) / 1000 * (a["v"] + b["v"]) / 2e6 / dt
      split("PSTR PMVR PPbb PP0b", keys, " ")
      for (i = 1; i <= 4; i++) printf " %s=%.3f", keys[i], ns[keys[i]] ? smc[keys[i]] / ns[keys[i]] : -1
      for (c = 0; c <= 3; c++) {t0 += d("c" c ".s0"); t1 += d("c" c ".s1")}
      printf " | pipewire=%.0f/s wireplumber=%.0f/s dma-irq=%.0f/s E.deep=%.1f%% E.ipi=%.0f/s", \
        d("pw") / dt, d("wp") / dt, d("irq") / dt, (t0 + t1) ? 100 * t1 / (t0 + t1) : 0, \
        d("ipi") / dt
      print ""
    }' <(echo "$a") <(echo "$b") <(echo "$smc")
}

exec > >(tee "$out") 2>&1
echo "# A4 $(date '+%F %T'), kernel $(uname -r), $(pacman -Q pipewire wireplumber | tr '\n' ' ')"
echo "# q<N> = clock.force-quantum N frames (was $force0 before the run). pipewire/wireplumber ="
echo "# context switches of all their threads; dma-irq = $irqname interrupts; E.deep = E-cores'"
echo "# idle in CPU PD; E.ipi = their wake IPIs"
start_profiler
: > "$rundir/windows"
results=
for (( round = 1; round <= rounds; round++ )); do
  # rotate the order each round, and reverse it in the second half
  order=()
  for (( i = 0; i < 3; i++ )); do order+=("${states[$(( (i + round - 1) % 3 ))]}"); done
  if (( round > 3 )); then order=("${order[2]}" "${order[1]}" "${order[0]}"); fi
  for q in "${order[@]}"; do
    set_force "$q"
    if [[ $(force_of) != "$q" ]]; then
      echo "round $round q$q: PipeWire didn't take clock.force-quantum $q; stopping."
      exit 1
    fi
    w0=$(mono_ns)
    sleep "$settle"
    line="round $round q$q: $(block)"
    w1=$(mono_ns)
    if ! grep -q 'state: RUNNING' "$speakers/status" 2>/dev/null; then
      echo "round $round q$q: the speakers stopped playing; stopping."
      exit 1
    fi
    echo "$line"
    echo "$round q$q $w0 $w1" >> "$rundir/windows"
    results+=$line$'\n'
  done
done
stop_profiler
set_force "$force0"
echo
echo "Against q1024, per round (negative = the longer cycle uses less):"
printf '%s' "$results" | awk -v rounds="$rounds" '
  {
    r = $2; s = $3; sub(/:$/, "", s)
    for (i = 4; i <= NF; i++) if (split($i, kv, "=") == 2) {sub(/\/s$|%$/, "", kv[2]); v[r, s, kv[1]] = kv[2]}
  }
  END {
    n = split("battery PSTR PMVR PPbb PP0b", k, " ")
    split("q2048 q4096", st, " ")
    for (j = 1; j <= 2; j++) {
      delete m; delete m2
      for (r = 1; r <= rounds; r++) {
        printf "%s round %d:", st[j], r
        for (i = 1; i <= n; i++) {
          x = v[r, st[j], k[i]] - v[r, "q1024", k[i]]; m[i] += x; m2[i] += x * x
          printf " %s %+.3f W", k[i], x
        }
        print ""
      }
      printf "%s mean:   ", st[j]
      for (i = 1; i <= n; i++) {
        mu = m[i] / rounds
        var = rounds > 1 ? (m2[i] - rounds * mu * mu) / (rounds - 1) : 0
        printf " %s %+.3f W (+-%.3f)", k[i], mu, (var > 0 ? sqrt(var / rounds) : 0)
      }
      print ""
    }
  }'
echo
echo "Per block, from PipeWire's profiler: cycle length, the speakers' xruns, the DSP's busy time:"
python3 -I - "$rundir/windows" "$rundir/profile" <<'EOF'
import sys

windows = [l.split() for l in open(sys.argv[1])]
clk, drv, dsp = [], [], []
for l in open(sys.argv[2]):
    f = l.split()
    if len(f) != 3:
        continue
    if f[0] == "C":
        clk.append((int(f[1]), int(f[2])))
    elif f[0] == "D":
        drv.append((int(f[1]), int(f[2])))
    elif f[0] == "F" and int(f[2]) >= int(f[1]):
        dsp.append((int(f[1]), (int(f[2]) - int(f[1])) / 1e3))
if not drv:
    print("  no profiler data (the profiler didn't run)")
    sys.exit(0)
tot = {}
for r, s, w0, w1 in windows:
    w0, w1 = int(w0), int(w1)
    dt = (w1 - w0) / 1e9
    durs = sorted(set(d for t, d in clk if w0 <= t < w1))
    before = [x for t, x in drv if t < w0]
    inside = [x for t, x in drv if w0 <= t < w1]
    busy = [b for t, b in dsp if w0 <= t < w1]
    xr = (inside[-1] - (before[-1] if before else inside[0])) if inside else 0
    st = tot.setdefault(s, [0, 0.0, 0, 0.0])
    st[0] += xr; st[1] += sum(busy) / 1e3; st[2] += len(inside); st[3] += dt
    print("  round %s %-5s cycle %-12s %5.1f cycles/s  xruns %d  DSP busy %5.0f us/cycle, %5.1f ms/s"
          % (r, s, ",".join(map(str, durs)) or "?", len(inside) / dt, xr,
             sum(busy) / len(busy) if busy else 0, sum(busy) / 1e3 / dt))
for s, (xr, busy_ms, cyc, dt) in sorted(tot.items(), key=lambda x: int(x[0][1:])):
    print("  %-5s total: %5.1f cycles/s  xruns %d  DSP busy %5.1f ms/s" % (s, cyc / dt, xr, busy_ms / dt))
print("  whole run: xruns %d -> %d" % (drv[0][1], drv[-1][1]))
EOF
