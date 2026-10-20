#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 3 A5: what an output stream that stays open while nothing plays costs. Taris Music's own
# player keeps its output open from its first use until the app quits, paused or not, writing
# silence: PipeWire's speaker graph keeps running (the DSP, speakersafetyd's sense stream, the
# amplifiers). This plays digital silence through the speakers the same way, against nothing
# playing with the speakers closed (PipeWire suspends them about 5 s after the last stream).
# Four rounds, order alternating; each block starts once the state is reached (silence: the
# speakers running; nothing: the speakers closed), 15 s to settle, then 45 s: battery power
# (coulomb counter), PSTR, PMVR (3.8 V rail: CPU, memory, SSD), PPbb (E-cluster), PP0b
# (P-cluster) every 5 s. Checked throughout: the speakers in the state the block asks for.
# Back as found at the end, also if interrupted: the silence stopped. Results:
# results/a5-output-<time>.txt. About 9 minutes.
# Needs: taris_smc_keys loaded (dev/power/smc-keys/test-install.sh), the Mac on battery, the
# speakers as the output (no headphones), nothing else playing and Taris Music closed (its own
# player would hold the output open). Run by the maintainer, as root, from the desktop session:
#   sudo dev/power/stage3/measure-a5-output.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
speakers=/proc/asound/card1/pcm1p/sub0
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
out=$here/results/a5-output-$(date +%Y%m%d-%H%M%S).txt
rounds=4; settle=15; samples=9

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
  echo "Start it with sudo from your own account: the silence plays in your session." >&2
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
if pgrep -u "$SUDO_USER" -x taris-music >/dev/null; then
  echo "Quit Taris Music first: its own player would hold the output open in every block." >&2
  exit 1
fi

mapfile -d '' session_env < "/proc/$shell_pid/environ"
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")
mkdir -p "$here/results"
player=

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
trap 'stop_player; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT

speakers_state() { head -1 "$speakers/status" 2>/dev/null || echo "closed"; }

# Reach the block's state: silence playing with the speakers running, or nothing playing with
# the speakers closed (up to 30 s for PipeWire to suspend them)
use() {
  local i
  if [[ $1 == "silence" ]]; then
    start_player
    for (( i = 0; i < 40; i++ )); do
      sleep 0.25
      if [[ $(speakers_state) == "state: RUNNING" ]]; then
        return 0
      fi
    done
    echo "the speakers didn't start within 10 s (headphones in, or another output chosen?)" >&2
    return 1
  fi
  stop_player
  for (( i = 0; i < 120; i++ )); do
    if [[ $(speakers_state) == "closed" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "the speakers didn't close within 30 s of the silence stopping (is something else" \
    "playing?)" >&2
  return 1
}

# Snapshot of running totals: time, battery
snap() {
  echo "t ${EPOCHREALTIME/./}"
  echo "q $(<"$bat/charge_counter")"
  echo "v $(<"$bat/voltage_now")"
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
      print ""
    }' <(echo "$a") <(echo "$b") <(echo "$smc")
}

exec > >(tee "$out") 2>&1
echo "# A5 output $(date '+%F %T'), kernel $(uname -r), $(pacman -Q pipewire wireplumber | tr '\n' ' ')"
echo "# silence = digital silence playing through the speakers (an open output with nothing to"
echo "# play); nothing = no stream, the speakers closed"
results=
for (( round = 1; round <= rounds; round++ )); do
  if (( round % 2 == 0 )); then order=(silence nothing); else order=(nothing silence); fi
  for state in "${order[@]}"; do
    if ! use "$state"; then
      echo "round $round $state: couldn't reach the state; stopping."
      exit 1
    fi
    sleep "$settle"
    line="round $round $state: $(block)"
    want="closed"
    if [[ $state == "silence" ]]; then
      want="state: RUNNING"
    fi
    if [[ $(speakers_state) != "$want" ]]; then
      echo "round $round $state: the speakers left the state during the block; stopping."
      exit 1
    fi
    echo "$line"
    results+=$line$'\n'
  done
done
stop_player
echo
echo "silence minus nothing, per round (what an open, silent output costs):"
printf '%s' "$results" | awk -v rounds="$rounds" '
  {
    r = $2; s = $3; sub(/:$/, "", s)
    for (i = 4; i <= NF; i++) if (split($i, kv, "=") == 2) v[r, s, kv[1]] = kv[2]
  }
  END {
    n = split("battery PSTR PMVR PPbb PP0b", k, " ")
    for (r = 1; r <= rounds; r++) {
      printf "round %d:", r
      for (i = 1; i <= n; i++) {
        x = v[r, "silence", k[i]] - v[r, "nothing", k[i]]; m[i] += x; m2[i] += x * x
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
