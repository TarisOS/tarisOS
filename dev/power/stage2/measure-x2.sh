#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 2 X2: deep idle on the efficiency cores. Asahi's idle driver offers WFI (exit 1 us) and
# CPU PD (exit 10 us, target residency 10,000 us; drivers/cpuidle/cpuidle-apple.c:100-121 at
# asahi-7.1.13-3), and the menu governor picks CPU PD only when it predicts 10 ms of idle. Three
# settings, all switched at runtime:
#   found  the menu governor, both states (as the system runs now)
#   edeep  the menu governor, WFI disabled on cpu0-3 (the E-cores): with state 0 disabled, menu
#          takes the first enabled state, CPU PD (governors/menu.c:304-312, :383-386)
#   teo    the teo governor, both states
# Writing a state's "disable" only sets or clears a user flag (sysfs.c:301-304), and the governor
# is switched through current_governor, so everything goes back by writing it back. Three rounds,
# each in a different order (a slow drift favours no setting), 15 s to settle after each switch,
# then 60 s of idle: battery power (coulomb counter), the SMC's PSTR, PMVR, PPbb (E-cluster) and
# PP0b (P-cluster) every 5 s (not every second: each read is a message to the SMC, and its
# interrupts land on cpu0, an E-core), and per cluster the busy share, the share of idle time in
# CPU PD, WFI and CPU PD entries a second, the share of CPU PD entries that ended before its target
# residency, wake-up IPIs and the mean clock. The brightness is recorded per block.
# Back as found at the end, also if interrupted; nothing outlasts a reboot.
# Results: results/x2-<time>.txt. Needs taris_smc_keys loaded (dev/power/smc-keys/
# test-install.sh) and the Mac on battery. About 12 minutes; leave it alone (the agent idle too).
# Run by the maintainer, as root, from the checkout:
#   sudo dev/power/stage2/measure-x2.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cpus=/sys/devices/system/cpu
gov=$cpus/cpuidle/current_governor
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
bl=/sys/class/backlight/apple-panel-bl/brightness
out=$here/results/x2-$(date +%Y%m%d-%H%M%S).txt

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
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
if [[ $(<"$cpus/cpuidle/current_driver") != "apple_idle" ]]; then
  echo "The idle driver isn't apple_idle ($(<"$cpus/cpuidle/current_driver"))." >&2
  exit 1
fi
if [[ $(<"$gov") != "menu" ]]; then
  echo "The idle governor isn't menu ($(<"$gov")): this compares against menu." >&2
  exit 1
fi
if ! grep -qw teo "$cpus/cpuidle/available_governors"; then
  echo "No teo governor in this kernel." >&2
  exit 1
fi
for f in "$cpus"/cpu[0-7]/cpuidle/state[01]/disable; do
  if [[ $(<"$f") != "0" ]]; then
    echo "$f is $(<"$f") already: this compares against every state enabled." >&2
    exit 1
  fi
done
mkdir -p "$here/results"

restore() {
  local c
  for c in 0 1 2 3; do
    echo 0 > "$cpus/cpu$c/cpuidle/state0/disable" 2>/dev/null || true
  done
  echo menu > "$gov" 2>/dev/null || true
}

state() {
  local c d=
  for c in 0 1 2 3; do d+=$(<"$cpus/cpu$c/cpuidle/state0/disable"); done
  echo "governor=$(<"$gov") e-wfi-disabled=$d"
}
trap 'restore; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT

# Each write is checked itself: set -e doesn't apply inside a function called from an if
apply() {
  local c v=0 g=menu want
  case $1 in
    edeep) v=1 ;;
    teo) g=teo ;;
  esac
  for c in 0 1 2 3; do
    echo "$v" > "$cpus/cpu$c/cpuidle/state0/disable" || return 1
  done
  echo "$g" > "$gov" || return 1
  want="governor=$g e-wfi-disabled=$v$v$v$v"
  [[ $(state) == "$want" ]]
}

# Running totals: time, battery counter and voltage, per-CPU idle states, CPU time, wake-up IPIs
# (rescheduling and function call), and each cluster's time at each clock
snap() {
  local c s d p
  echo "t ${EPOCHREALTIME/./}"
  echo "q $(<"$bat/charge_counter")"
  echo "v $(<"$bat/voltage_now")"
  for c in 0 1 2 3 4 5 6 7; do
    for s in 0 1; do
      d=$cpus/cpu$c/cpuidle/state$s
      echo "c$c.s$s.time $(<"$d/time")"
      echo "c$c.s$s.usage $(<"$d/usage")"
      echo "c$c.s$s.above $(<"$d/above")"
    done
  done
  awk '/^cpu[0-9]/ {
    sub(/^cpu/, "c", $1)
    print $1 ".busy", $2 + $3 + $4 + $7 + $8 + $9
    print $1 ".all", $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9
  }' /proc/stat
  awk '$1 == "IPI0:" || $1 == "IPI1:" {for (i = 2; i <= 9; i++) print "c" i - 2 ".ipi" $1, $i}' \
    /proc/interrupts
  for p in 0 4; do
    awk -v p="$p" '{print "p" p ".f" $1, $2}' "$cpus/cpufreq/policy$p/stats/time_in_state"
  done
}

block() {
  local a b smc i b0 b1
  b0=$(<"$bl")
  a=$(snap)
  smc=$(
    for (( i = 0; i < 12; i++ )); do
      awk '$1 ~ /^(PSTR|PMVR|PPbb|PP0b)$/ {printf "%s %s ", $1, $2} END {print ""}' "$power"
      sleep 5
    done
  )
  b=$(snap)
  b1=$(<"$bl")
  awk -v b0="$b0" -v b1="$b1" '
    FILENAME == ARGV[1] {a[$1] = $2; next}
    FILENAME == ARGV[2] {b[$1] = $2; next}
    {for (i = 1; i < NF; i += 2) {smc[$i] += $(i + 1); ns[$i]++}}
    function d(k) {return b[k] - a[k]}
    function cluster(name, lo, hi, pol,    c, t0, t1, u0, u1, ab, busy, all, ipi, k, f, ft, tt) {
      for (c = lo; c <= hi; c++) {
        t0 += d("c" c ".s0.time"); t1 += d("c" c ".s1.time")
        u0 += d("c" c ".s0.usage"); u1 += d("c" c ".s1.usage"); ab += d("c" c ".s1.above")
        busy += d("c" c ".busy"); all += d("c" c ".all")
        ipi += d("c" c ".ipiIPI0:") + d("c" c ".ipiIPI1:")
      }
      for (k in b) {
        if (index(k, "p" pol ".f") == 1) {
          f = substr(k, length("p" pol ".f") + 1); ft += f * d(k); tt += d(k)
        }
      }
      printf " | %s busy=%.1f%% deep=%.1f%% wfi=%.0f/s pd=%.0f/s pd-early=%.0f%% ipi=%.0f/s mhz=%.0f", \
        name, all ? 100 * busy / all : 0, (t0 + t1) ? 100 * t1 / (t0 + t1) : 0, u0 / dt, u1 / dt, \
        u1 ? 100 * ab / u1 : 0, ipi / dt, tt ? ft / tt / 1000 : 0
    }
    END {
      dt = d("t") / 1e6
      w = (a["q"] - b["q"]) / 1000 * (a["v"] + b["v"]) / 2e6 / dt
      printf "battery=%.3f", w
      split("PSTR PMVR PPbb PP0b", keys, " ")
      for (i = 1; i <= 4; i++) {
        printf " %s=%.3f", keys[i], ns[keys[i]] ? smc[keys[i]] / ns[keys[i]] : -1
      }
      printf " brightness=%s", (b0 == b1) ? b0 : b0 "->" b1 "(CHANGED)"
      cluster("E", 0, 3, 0)
      cluster("P", 4, 7, 4)
      print ""
    }' <(echo "$a") <(echo "$b") <(echo "$smc")
}

{
  echo "# X2 $(date '+%F %T'): $(state), kernel $(uname -r)"
  echo "# found = menu, both states; edeep = menu, WFI disabled on cpu0-3; teo = teo, both states"
  echo "# deep = share of idle time in CPU PD; pd-early = CPU PD entries that ended before 10 ms;"
  echo "# ipi = rescheduling + function-call IPIs; mhz = time-weighted clock, idle time included"
  sleep 30
  results=
  for round in 1 2 3; do
    case $round in
      1) order=(found edeep teo) ;;
      2) order=(edeep teo found) ;;
      3) order=(teo found edeep) ;;
    esac
    for setting in "${order[@]}"; do
      if ! apply "$setting"; then
        restore
        echo "round $round $setting: the setting didn't take ($(state)); stopping."
        exit 1
      fi
      sleep 15
      line="round $round $setting: $(block)"
      echo "$line"
      results+=$line$'\n'
    done
  done
  restore
  echo "Back as found: $(state)."
  echo
  echo "Against found, per round (battery, PSTR; negative = less power):"
  printf '%s' "$results" | awk '
    {
      r = $2; s = $3; sub(/:$/, "", s)
      for (i = 4; i <= NF; i++) {
        if ($i ~ /^battery=/) {sub(/^battery=/, "", $i); bat[r, s] = $i}
        if ($i ~ /^PSTR=/) {sub(/^PSTR=/, "", $i); pstr[r, s] = $i}
      }
    }
    END {
      for (r = 1; r <= 3; r++) {
        printf "round %d: edeep %+.3f W, %+.3f W   teo %+.3f W, %+.3f W\n", r, \
          bat[r, "edeep"] - bat[r, "found"], pstr[r, "edeep"] - pstr[r, "found"], \
          bat[r, "teo"] - bat[r, "found"], pstr[r, "teo"] - pstr[r, "found"]
        mb["found"] += bat[r, "found"]; mb["edeep"] += bat[r, "edeep"]; mb["teo"] += bat[r, "teo"]
        mp["found"] += pstr[r, "found"]; mp["edeep"] += pstr[r, "edeep"]; mp["teo"] += pstr[r, "teo"]
      }
      printf "mean:    found %.3f W / %.3f W   edeep %.3f W / %.3f W   teo %.3f W / %.3f W\n", \
        mb["found"] / 3, mp["found"] / 3, mb["edeep"] / 3, mp["edeep"] / 3, \
        mb["teo"] / 3, mp["teo"] / 3
    }'
} 2>&1 | tee "$out"
