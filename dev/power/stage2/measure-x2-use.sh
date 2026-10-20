#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 2 X2 during the maintainer's own use: deep idle on the efficiency cores, measured while the
# Mac is used normally, since no made-up workload stands for real use. Two settings, switched at
# runtime:
#   found  both idle states on every core (as the system runs now)
#   edeep  WFI disabled on cpu0-3 (the E-cores), so every idle there is CPU PD: with state 0
#          disabled, the menu governor takes the first enabled state (governors/menu.c:304-312,
#          :383-386 at asahi-7.1.13-3)
# 15 pairs of 2-minute blocks, both settings in each pair, the order alternating from pair to pair
# (found-edeep, edeep-found, ...), about an hour. Use varies from block to block, so each pair is
# compared within itself and the summary gives the mean difference with its standard error.
# Per block: the 3.8 V rail (PMVR: every CPU, memory and SSD load, not the backlight or Wi-Fi), the
# CPU clusters' SMC keys (PPbb E, PP0b P) and PSTR every 5 s; battery power (coulomb counter);
# per cluster the busy share, the share of idle in CPU PD, idle entries a second, wake-up IPIs and
# the mean clock; the brightness. A block on the charger or with a sleep in it is left out;
# battery power is compared only for pairs at one unchanged brightness (PMVR doesn't depend on it).
# Writing a state's "disable" only sets or clears a user flag (sysfs.c:301-304): everything goes
# back as found at the end, also when stopped early; nothing outlasts a reboot.
# Started from a terminal, it checks everything, then runs on as the transient service
# taris-x2-use, so the terminal can be closed. Results, and the summary at the end:
# results/x2-use-<time>.txt. Needs taris_smc_keys loaded (dev/power/smc-keys/test-install.sh) and
# the Mac on battery. To stop early (the summary covers the pairs done): sudo systemctl stop
# taris-x2-use
# Run by the maintainer, as root:
#   sudo dev/power/stage2/measure-x2-use.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
self=$here/$(basename "$0")
unit=taris-x2-use
cpus=/sys/devices/system/cpu
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
ac=/sys/class/power_supply/macsmc-ac/online
bl=/sys/class/backlight/apple-panel-bl/brightness
pairs=15
secs=120

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ ! -r $power ]]; then
  echo "taris_smc_keys isn't loaded: run dev/power/smc-keys/test-install.sh first." >&2
  exit 1
fi
if [[ $(<"$ac") != "0" ]]; then
  echo "Unplug the charger first: the battery is measured." >&2
  exit 1
fi
if [[ $(<"$cpus/cpuidle/current_driver") != "apple_idle" || $(<"$cpus/cpuidle/current_governor") != "menu" ]]; then
  echo "Expected the apple_idle driver with the menu governor; found" \
    "$(<"$cpus/cpuidle/current_driver") with $(<"$cpus/cpuidle/current_governor")." >&2
  exit 1
fi
for f in "$cpus"/cpu[0-7]/cpuidle/state[01]/disable; do
  if [[ $(<"$f") != "0" ]]; then
    echo "$f is $(<"$f") already: this compares against every state enabled." >&2
    exit 1
  fi
done

restore() {
  local c
  for c in 0 1 2 3; do
    echo 0 > "$cpus/cpu$c/cpuidle/state0/disable" 2>/dev/null || true
  done
}

# Each write is checked itself: set -e doesn't apply inside a function called from an if
apply() {
  local c v=0 d=
  if [[ $1 == "edeep" ]]; then v=1; fi
  for c in 0 1 2 3; do
    echo "$v" > "$cpus/cpu$c/cpuidle/state0/disable" || return 1
  done
  for c in 0 1 2 3; do d+=$(<"$cpus/cpu$c/cpuidle/state0/disable"); done
  [[ $d == "$v$v$v$v" ]]
}

# Running totals: time, battery counter and voltage, charger, sleeps, brightness, per-CPU idle
# states, CPU time, wake-up IPIs (rescheduling and function call), each cluster's time per clock
snap() {
  local c s d p
  echo "t ${EPOCHREALTIME/./}"
  echo "q $(<"$bat/charge_counter")"
  echo "v $(<"$bat/voltage_now")"
  echo "ac $(<"$ac")"
  echo "susp $(</sys/power/suspend_stats/success)"
  echo "bl $(<"$bl")"
  for c in 0 1 2 3 4 5 6 7; do
    for s in 0 1; do
      d=$cpus/cpu$c/cpuidle/state$s
      echo "c$c.s$s.time $(<"$d/time")"
      echo "c$c.s$s.usage $(<"$d/usage")"
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

# One block; the background sleep lets a stop interrupt it at once (bash's own sleep wouldn't)
block() {
  local a b smc= i
  a=$(snap)
  for (( i = 0; i < secs / 5; i++ )); do
    smc+=$(awk '$1 ~ /^(PSTR|PMVR|PPbb|PP0b)$/ {printf "%s %s ", $1, $2}' "$power")$'\n'
    sleep 5 &
    wait $!
  done
  b=$(snap)
  awk '
    FILENAME == ARGV[1] {a[$1] = $2; next}
    FILENAME == ARGV[2] {b[$1] = $2; next}
    {for (i = 1; i < NF; i += 2) {smc[$i] += $(i + 1); ns[$i]++}}
    function d(k) {return b[k] - a[k]}
    function cluster(name, lo, hi, pol,    c, t0, t1, u0, u1, busy, all, ipi, k, f, ft, tt) {
      for (c = lo; c <= hi; c++) {
        t0 += d("c" c ".s0.time"); t1 += d("c" c ".s1.time")
        u0 += d("c" c ".s0.usage"); u1 += d("c" c ".s1.usage")
        busy += d("c" c ".busy"); all += d("c" c ".all")
        ipi += d("c" c ".ipiIPI0:") + d("c" c ".ipiIPI1:")
      }
      for (k in b) {
        if (index(k, "p" pol ".f") == 1) {
          f = substr(k, length("p" pol ".f") + 1); ft += f * d(k); tt += d(k)
        }
      }
      printf " | %s.busy=%.1f %s.deep=%.1f %s.wfi=%.0f %s.pd=%.0f %s.ipi=%.0f %s.mhz=%.0f", \
        name, all ? 100 * busy / all : 0, name, (t0 + t1) ? 100 * t1 / (t0 + t1) : 0, \
        name, u0 / dt, name, u1 / dt, name, ipi / dt, name, tt ? ft / tt / 1000 : 0
    }
    END {
      dt = d("t") / 1e6
      why = ""
      if (a["ac"] != 0 || b["ac"] != 0) why = why "charger,"
      if (d("susp") != 0) why = why "sleep,"
      printf "valid=%s", why == "" ? "yes" : "no(" substr(why, 1, length(why) - 1) ")"
      printf " brightness=%s", a["bl"] == b["bl"] ? a["bl"] : a["bl"] "->" b["bl"]
      printf " battery=%.3f", (a["q"] - b["q"]) / 1000 * (a["v"] + b["v"]) / 2e6 / dt
      split("PMVR PPbb PP0b PSTR", keys, " ")
      for (i = 1; i <= 4; i++) {
        printf " %s=%.3f", keys[i], ns[keys[i]] ? smc[keys[i]] / ns[keys[i]] : -1
      }
      cluster("E", 0, 3, 0)
      cluster("P", 4, 7, 4)
      print ""
    }' <(echo "$a") <(echo "$b") <(echo "$smc")
}

# Per pair (both blocks valid) edeep minus found: mean, standard error, how many pairs
summary() {
  echo
  echo "Summary: edeep minus found per pair (negative = edeep uses less), mean +- standard error"
  awk '
    $1 == "pair" {
      p = $2; s = $3
      for (i = 4; i <= NF; i++) {
        if (split($i, kv, "=") == 2) v[p, s, kv[1]] = kv[2]
      }
      seen[p]++
    }
    function stat(name, k, battery,    p, n, x, sum, sq, m, sd) {
      for (p in seen) {
        if (seen[p] != 2 || v[p, "found", "valid"] != "yes" || v[p, "edeep", "valid"] != "yes")
          continue
        if (battery && (v[p, "found", "brightness"] ~ /->/ || \
            v[p, "found", "brightness"] != v[p, "edeep", "brightness"]))
          continue
        x = v[p, "edeep", k] - v[p, "found", k]; n++; sum += x; sq += x * x
      }
      if (n < 2) {printf "  %-28s %d pairs: too few\n", name, n; return}
      m = sum / n; sd = sqrt((sq - n * m * m) / (n - 1))
      printf "  %-28s %+.3f +- %.3f  (%d pairs)\n", name, m, sd / sqrt(n), n
    }
    END {
      stat("3.8 V rail PMVR (W)", "PMVR", 0)
      stat("E-cluster PPbb (W)", "PPbb", 0)
      stat("P-cluster PP0b (W)", "PP0b", 0)
      stat("total PSTR (W)", "PSTR", 0)
      stat("battery (W, same brightness)", "battery", 1)
      print "  Workload balance (should be near 0) and the effect of the setting on the E-cores:"
      stat("E-cores busy (%)", "E.busy", 0)
      stat("P-cores busy (%)", "P.busy", 0)
      stat("E-cores idle in CPU PD (%)", "E.deep", 0)
    }' "$out"
  echo "A difference smaller than about twice its standard error isn't a measured effect."
}

if [[ ${1:-} == "--run" ]]; then
  out=$here/results/x2-use-$(date +%Y%m%d-%H%M%S).txt
  mkdir -p "$here/results"
  exec >> "$out" 2>&1
  trap 'exit 143' TERM
  trap 'exit 130' INT
  trap 'restore; summary; echo "Back as found: E-core WFI enabled again."; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT
  echo "# X2 during use, $(date '+%F %T'), kernel $(uname -r): $pairs pairs of ${secs} s blocks"
  echo "# found = both idle states; edeep = WFI disabled on cpu0-3. busy, deep (share of idle in"
  echo "# CPU PD) in %; wfi, pd (entries), ipi (rescheduling + function call) per second"
  for (( p = 1; p <= pairs; p++ )); do
    if (( p % 2 )); then order=(found edeep); else order=(edeep found); fi
    for setting in "${order[@]}"; do
      if ! apply "$setting"; then
        echo "pair $p: $setting didn't take; stopping."
        exit 1
      fi
      echo "pair $p $setting $(block)"
    done
  done
else
  if systemctl is-active --quiet "$unit"; then
    echo "$unit is running already. Stop it with: sudo systemctl stop $unit" >&2
    exit 1
  fi
  systemd-run --quiet --collect --unit="$unit" --description="Stage 2 X2 during use" "$self" --run
  echo "Started ($unit): about $(( pairs * 2 * secs / 60 )) minutes. Use the Mac normally, on battery."
  echo "Results: $here/results/x2-use-<time>.txt, with the summary at the end when it's done."
  echo "To stop early: sudo systemctl stop $unit"
fi
