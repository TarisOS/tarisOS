#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 3 A2: speakersafetyd reading its sense stream in 48-frame ALSA periods (Asahi's build,
# about 1,000 wake-ups and DMA interrupts a second while sound plays) against one period per
# 4096-frame block (speakersafetyd-taris, about 12). Digital silence plays through the speakers
# for the whole run: nothing is heard and the speakers get no power, but the sense stream and the
# daemon run exactly as with any sound (its wake-ups don't depend on what plays). The two daemons
# take turns: Asahi's, kept from before the package change (results/speakersafetyd-2.0.1-1-asahi),
# runs from /run/taris-a2 through a runtime drop-in for the service; ours is the installed one.
# Each switch restarts the service, as systemd does after a failure (the kernel holds the speakers
# at its safe limit until the daemon pings it again), with the silence stopped and the speakers
# closed: the daemon opens its sense stream as at boot and after a resume. With the speakers open
# the stream's rate is fixed at theirs and ALSA's own period (Asahi's daemon sets none) comes out
# at 256 frames, not the 48 of normal running. Three rounds, order alternating, 15 s to
# settle, then 90 s: battery power (coulomb counter), PSTR, PMVR (3.8 V rail: CPU, memory, SSD),
# PPbb (E-cluster), PP0b (P-cluster) every 5 s, the daemon's wake-ups, the audio DMA's interrupts,
# the sense stream's frames, the E-cores' share of idle in deep idle and their wake-up IPIs.
# Checked throughout: the sense stream's ALSA period (48 for Asahi's, 4096 for ours), the speakers
# playing, no automatic restart of the daemon, and the kernel's speaker lock: a "Lock timeout"
# means the daemon missed its 250 ms ping, and stops the run.
# Back as found at the end, also if interrupted: the drop-in removed, the installed daemon
# restarted, the silence stopped. Results: results/a2-<time>.txt. About 12 minutes.
# Needs: speakersafetyd-taris installed, taris_smc_keys loaded (dev/power/smc-keys/
# test-install.sh), the Mac on battery, the speakers as the output (no headphones), nothing else
# playing. Run by the maintainer, as root, from the desktop session:
#   sudo dev/power/stage3/measure-a2.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
old=$here/results/speakersafetyd-2.0.1-1-asahi
old_sum=7631c45199b135b8291194c0baad742b6696510888cba49b33f62fc3b3172cde
rundir=/run/taris-a2
dropdir=/run/systemd/system/speakersafetyd.service.d
dropin=$dropdir/50-taris-a2.conf
sense=/proc/asound/card1/pcm2c/sub0
speakers=/proc/asound/card1/pcm1p/sub0
irqname=238200000.dma-controller
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
cpus=/sys/devices/system/cpu
out=$here/results/a2-$(date +%Y%m%d-%H%M%S).txt

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
if ! pacman -Q speakersafetyd-taris >/dev/null 2>&1; then
  echo "speakersafetyd-taris isn't installed: install it first." >&2
  exit 1
fi
if [[ ! -f $old || $(sha256sum < "$old" | cut -d' ' -f1) != "$old_sum" ]]; then
  echo "Asahi's daemon isn't at $old (or has changed)." >&2
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
if [[ -e $dropin ]]; then
  echo "$dropin exists: an earlier run didn't finish. Remove it, then run" \
    "systemctl daemon-reload && systemctl restart speakersafetyd." >&2
  exit 1
fi
if ! grep -q " $irqname\$" /proc/interrupts; then
  echo "No interrupt line named $irqname: the audio DMA's line has changed." >&2
  exit 1
fi
mapfile -d '' session_env < "/proc/$shell_pid/environ"
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")
mkdir -p "$here/results"
since=$(date '+%Y-%m-%d %H:%M:%S')
restarts0=$(systemctl show -p NRestarts --value speakersafetyd)
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

restore() {
  rm -f "$dropin"
  rmdir "$dropdir" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  systemctl restart speakersafetyd 2>/dev/null || true
  stop_player
  rm -rf "$rundir"
}
trap 'restore; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT

daemon_pid() { systemctl show -p MainPID --value speakersafetyd; }
hwptr() { awk '$1 == "hw_ptr" {print $3}' "$sense/status"; }
irqs() { awk -v n="$irqname" '$NF == n {s = 0; for (i = 2; i <= 9; i++) s += $i; print s}' /proc/interrupts; }
ctx() { awk '/ctxt_switches/ {s += $2} END {print s}' "/proc/$1/status"; }
period() { awk '$1 == "period_size:" {print $2}' "$sense/hw_params"; }

# Switch daemons with the speakers closed: the drop-in starts Asahi's from /run (the service's
# DynamicUser can't reach a home folder); without it, the installed one. Then wait for the new
# daemon to open the sense stream, start the silence, wait for frames flowing and check the period.
use() {
  local pid p0 p i want=48
  if [[ $1 == "taris" ]]; then want=4096; fi
  stop_player
  i=0
  while [[ $(<"$speakers/status") != "closed" ]] && (( i++ < 120 )); do
    sleep 0.25
  done
  if [[ $(<"$speakers/status") != "closed" ]]; then
    echo "$1: the speakers didn't close within 30 s of the silence stopping." >&2
    return 1
  fi
  if [[ $1 == "asahi" ]]; then
    mkdir -p "$dropdir"
    printf '[Service]\nExecStart=\nExecStart=%s -c /usr/share/speakersafetyd/ -m 7\n' \
      "$rundir/speakersafetyd" > "$dropin"
  else
    rm -f "$dropin"
  fi
  systemctl daemon-reload
  systemctl restart speakersafetyd
  for (( i = 0; i < 40; i++ )); do
    sleep 0.25
    pid=$(daemon_pid)
    if (( pid > 0 )) && grep -q "owner_pid *: $pid\$" "$sense/status" 2>/dev/null; then
      break
    fi
  done
  if (( i == 40 )); then
    echo "$1: the daemon didn't open the sense stream within 10 s." >&2
    return 1
  fi
  start_player
  for (( i = 0; i < 40; i++ )); do
    sleep 0.25
    if grep -q 'state: RUNNING' "$speakers/status" 2>/dev/null; then
      p0=$(hwptr)
      sleep 0.5
      if (( $(hwptr) > p0 )); then
        p=$(period)
        if [[ $p == "$want" ]]; then
          return 0
        fi
        echo "$1: the sense stream's period is $p frames, not $want." >&2
        return 1
      fi
    fi
  done
  echo "$1: the speakers didn't play with sense frames flowing within 10 s (headphones in, or" \
    "another output chosen?)." >&2
  return 1
}

# Snapshot of running totals: time, battery, the daemon, the DMA, the sense stream, the E-cores
snap() {
  local c
  echo "t ${EPOCHREALTIME/./}"
  echo "q $(<"$bat/charge_counter")"
  echo "v $(<"$bat/voltage_now")"
  echo "ctx $(ctx "$1")"
  echo "irq $(irqs)"
  echo "ptr $(hwptr)"
  for c in 0 1 2 3; do
    echo "c$c.s0 $(<"$cpus/cpu$c/cpuidle/state0/time")"
    echo "c$c.s1 $(<"$cpus/cpu$c/cpuidle/state1/time")"
  done
  awk '$1 == "IPI0:" || $1 == "IPI1:" {for (i = 2; i <= 5; i++) s += $i} END {print "ipi", s}' \
    /proc/interrupts
}

block() {
  local pid a b smc= i
  pid=$(daemon_pid)
  a=$(snap "$pid")
  for (( i = 0; i < 18; i++ )); do
    smc+=$(awk '$1 ~ /^(PSTR|PMVR|PPbb|PP0b)$/ {printf "%s %s ", $1, $2}' "$power")$'\n'
    sleep 5
  done
  b=$(snap "$pid")
  if [[ $(daemon_pid) != "$pid" ]]; then
    echo "the daemon restarted during the block"
    return 1
  fi
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
      printf " | daemon=%.0f/s dma-irq=%.0f/s sense=%.0f frames/s E.deep=%.1f%% E.ipi=%.0f/s", \
        d("ctx") / dt, d("irq") / dt, d("ptr") / dt, (t0 + t1) ? 100 * t1 / (t0 + t1) : 0, \
        d("ipi") / dt
      print ""
    }' <(echo "$a") <(echo "$b") <(echo "$smc")
}

# Whether the kernel locked the speakers for a missed ping since the block began (the reason
# printed at a daemon switch doesn't count)
lock_timeout() {
  journalctl -k -q --since "$1" --no-pager -o cat 2>/dev/null | grep 'Lock timeout' >/dev/null
}

mkdir -p "$rundir"
install -m 0755 "$old" "$rundir/speakersafetyd"

exec > >(tee "$out") 2>&1
echo "# A2 $(date '+%F %T'), kernel $(uname -r), $(pacman -Q speakersafetyd-taris)"
echo "# asahi = Asahi's daemon (48-frame periods), taris = speakersafetyd-taris; digital silence"
echo "# through the speakers. daemon = its context switches; dma-irq = $irqname interrupts;"
echo "# sense = V/ISENSE frames read; E.deep = E-cores' idle in CPU PD; E.ipi = their wake IPIs"
start_player
sleep 3
if ! grep -q 'state: RUNNING' "$speakers/status" 2>/dev/null; then
  echo "The speakers aren't playing (headphones in, or another output chosen): stopping."
  exit 1
fi
results=
for round in 1 2 3; do
  if (( round == 2 )); then order=(taris asahi); else order=(asahi taris); fi
  for daemon in "${order[@]}"; do
    if ! use "$daemon"; then
      echo "round $round $daemon: couldn't switch; stopping."
      exit 1
    fi
    sleep 15
    block_since=$(date '+%Y-%m-%d %H:%M:%S')
    if ! line="round $round $daemon: period=$(period) $(block)"; then
      echo "round $round $daemon: $line; stopping."
      exit 1
    fi
    echo "$line"
    results+=$line$'\n'
    if lock_timeout "$block_since"; then
      echo "The kernel locked the speakers for a missed ping (Lock timeout): stopping."
      exit 1
    fi
  done
done
echo
echo "taris minus asahi, per round (negative = ours uses less):"
printf '%s' "$results" | awk '
  {
    r = $2; s = $3; sub(/:$/, "", s)
    for (i = 4; i <= NF; i++) if (split($i, kv, "=") == 2) {sub(/\/s$|%$/, "", kv[2]); v[r, s, kv[1]] = kv[2]}
  }
  END {
    n = split("battery PSTR PMVR PPbb PP0b", k, " ")
    for (r = 1; r <= 3; r++) {
      printf "round %d:", r
      for (i = 1; i <= n; i++) {
        x = v[r, "taris", k[i]] - v[r, "asahi", k[i]]; m[i] += x / 3
        printf " %s %+.3f W", k[i], x
      }
      print ""
    }
    printf "mean:   "
    for (i = 1; i <= n; i++) printf " %s %+.3f W", k[i], m[i]
    print ""
  }'
echo
echo "Automatic restarts of the daemon during the run:" \
  "$(( $(systemctl show -p NRestarts --value speakersafetyd) - restarts0 ))"
echo "The kernel's speaker lock during the run (a lock and unlock at each switch is expected):"
journalctl -k -q --since "$since" --no-pager -o short-monotonic 2>/dev/null |
  grep -i 'speaker volumes' || echo "  none"
echo "The daemons' warnings during the run:"
journalctl -q --since "$since" --no-pager -o cat -u speakersafetyd 2>/dev/null |
  grep -E 'WARN|Panic|panic|Expected|Skipping|PCM period' | sort | uniq -c || echo "  none"
