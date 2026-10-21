#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 4 D1: what the bar clock's seconds cost on an idle desktop. Each second changes the
# seconds text on the shell's full-screen panel surface: the shell re-renders its scene,
# Hyprland recomposites the screen and re-blurs the panels. This switches the bar's seconds on
# and off between blocks through the account's shell.json (bar.clock.showSeconds, what Settings >
# Taskbar does; the shell reloads the file by itself) on a desktop left alone.
# Six rounds, order alternating, 10 s to settle, then 45 s: battery power (coulomb counter), PSTR,
# PMVR (3.8 V rail: CPU, memory, SSD), PPbb (E-cluster), PP0b (P-cluster) every 5 s, and the CPU
# time and wake-ups of the shell (qs) and Hyprland.
# Keeps the screen awake for the run (the shell's idle inhibitor) and puts back what it found at
# the end, also if interrupted: shell.json as it was, the idle inhibitor as it was. Results:
# results/d1-<time>.txt. About 11 minutes, during which nothing on the Mac should be touched.
# Needs: taris_smc_keys loaded (dev/power/smc-keys/test-install.sh), the Mac on battery, the
# desktop as it usually sits idle (nothing playing or moving). Run by the maintainer, as root,
# from the desktop session:
#   sudo dev/power/stage4/measure-d1.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
rundir=/run/taris-d1
out=$here/results/d1-$(date +%Y%m%d-%H%M%S).txt
rounds=6; settle=10; samples=9

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
  echo "Start it with sudo from your own account: the shell runs in your session." >&2
  exit 1
fi
shell_pid=$(pgrep -u "$SUDO_USER" -x qs -o || true)
hypr_pid=$(pgrep -u "$SUDO_USER" -x Hyprland -o || true)
if [[ -z $shell_pid || -z $hypr_pid ]]; then
  echo "No Taris shell or Hyprland running for $SUDO_USER: log in to the desktop first." >&2
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

mapfile -d '' session_env < "/proc/$shell_pid/environ"
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")
config_home=$("${as_user[@]}" sh -c 'echo "${XDG_CONFIG_HOME:-$HOME/.config}"')
config=$config_home/taris/shell.json

rm -rf "$rundir"
mkdir -p "$rundir" "$here/results"
had_config=false
if [[ -e $config ]]; then
  had_config=true
  cp -p "$config" "$rundir/shell.json"
fi
inhibit_was=$("${as_user[@]}" taris shell idleInhibitor isEnabled 2>/dev/null || echo "false")

# The bar's seconds on or off, as Settings writes them, in the account's own file
set_seconds() {
  "${as_user[@]}" python3 -I - "$config" "$1" <<'EOF'
import json, os, sys
path, value = sys.argv[1], sys.argv[2] == "true"
try:
    with open(path) as f:
        config = json.load(f)
except FileNotFoundError:
    config = {}
config.setdefault("bar", {}).setdefault("clock", {})["showSeconds"] = value
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(config, f, indent=4)
    f.write("\n")
EOF
}

restore() {
  if [[ $had_config == "true" ]]; then
    "${as_user[@]}" sh -c 'cat > "$1"' sh "$config" < "$rundir/shell.json" || true
  else
    rm -f "$config"
  fi
  if [[ $inhibit_was != "true" ]]; then
    "${as_user[@]}" taris shell idleInhibitor disable >/dev/null 2>&1 || true
  fi
  rm -rf "$rundir"
}
trap 'restore; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT

"${as_user[@]}" taris shell idleInhibitor enable >/dev/null

# CPU time (ticks) and context switches of every thread of a process
proc() {
  cat /proc/"$1"/task/*/stat 2>/dev/null | awk '{sub(/^.*\) /, ""); c += $12 + $13} END {printf "%d ", c}'
  cat /proc/"$1"/task/*/status 2>/dev/null | awk '/ctxt_switches/ {s += $2} END {print s}'
}

snap() {
  local c w
  echo "t ${EPOCHREALTIME/./}"
  echo "q $(<"$bat/charge_counter")"
  echo "v $(<"$bat/voltage_now")"
  read -r c w < <(proc "$shell_pid"); echo "qs.cpu $c"; echo "qs.wake $w"
  read -r c w < <(proc "$hypr_pid"); echo "hl.cpu $c"; echo "hl.wake $w"
}

block() {
  local a b smc= i
  a=$(snap)
  for (( i = 0; i < samples; i++ )); do
    smc+=$(awk '$1 ~ /^(PSTR|PMVR|PPbb|PP0b)$/ {printf "%s %s ", $1, $2}' "$power")$'\n'
    sleep 5
  done
  b=$(snap)
  awk -v hz="$(getconf CLK_TCK)" '
    FILENAME == ARGV[1] {a[$1] = $2; next}
    FILENAME == ARGV[2] {b[$1] = $2; next}
    {for (i = 1; i < NF; i += 2) {smc[$i] += $(i + 1); ns[$i]++}}
    function d(k) {return b[k] - a[k]}
    END {
      dt = d("t") / 1e6
      printf "battery=%.3f", (a["q"] - b["q"]) / 1000 * (a["v"] + b["v"]) / 2e6 / dt
      split("PSTR PMVR PPbb PP0b", keys, " ")
      for (i = 1; i <= 4; i++) printf " %s=%.3f", keys[i], ns[keys[i]] ? smc[keys[i]] / ns[keys[i]] : -1
      printf " | qs=%.1f%% qs.wake=%.0f/s Hyprland=%.1f%% hl.wake=%.0f/s", \
        100 * d("qs.cpu") / hz / dt, d("qs.wake") / dt, 100 * d("hl.cpu") / hz / dt, d("hl.wake") / dt
      print ""
    }' <(echo "$a") <(echo "$b") <(echo "$smc")
}

exec > >(tee "$out") 2>&1
echo "# D1 $(date '+%F %T'), kernel $(uname -r), $(pacman -Q taris-shell hyprland 2>/dev/null | tr '\n' ' ')"
echo "# seconds = the bar clock showing seconds, none = not (bar.clock.showSeconds in"
echo "# $config); idle desktop, screen kept awake. qs/Hyprland = CPU time and wake-ups, all threads"
results=
for (( round = 1; round <= rounds; round++ )); do
  if (( round % 2 == 0 )); then order=(seconds none); else order=(none seconds); fi
  for state in "${order[@]}"; do
    if [[ $state == "seconds" ]]; then set_seconds true; else set_seconds false; fi
    sleep "$settle"
    line="round $round $state: $(block)"
    echo "$line"
    results+=$line$'\n'
  done
done
echo
echo "seconds minus none, per round (what the seconds cost):"
printf '%s' "$results" | awk -v rounds="$rounds" '
  {
    r = $2; s = $3; sub(/:$/, "", s)
    for (i = 4; i <= NF; i++) if (split($i, kv, "=") == 2) {sub(/\/s$|%$/, "", kv[2]); v[r, s, kv[1]] = kv[2]}
  }
  END {
    n = split("battery PSTR PMVR PPbb PP0b", k, " ")
    for (r = 1; r <= rounds; r++) {
      printf "round %d:", r
      for (i = 1; i <= n; i++) {
        x = v[r, "seconds", k[i]] - v[r, "none", k[i]]; m[i] += x; m2[i] += x * x
        printf " %s %+.3f W", k[i], x
      }
      print ""
    }
    printf "mean:   "
    for (i = 1; i <= n; i++) {
      mu = m[i] / rounds
      var = rounds > 1 ? (m2[i] - rounds * mu * mu) / (rounds - 1) : 0
      printf " %s %+.3f W (+-%.3f)", k[i], mu, (var > 0 ? sqrt(var / rounds) : 0)
    }
    print ""
  }'
