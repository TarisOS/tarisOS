#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Logs this Mac's power use through normal use, for the Stage 1 baseline: every INTERVAL seconds
# (default 30) one CSV row in results/powerlog-<start time>.csv next to this script, until it's
# stopped. Each row has the battery (its coulomb counter, voltage, current, charge), the SMC power
# keys taris_smc_keys samples, the brightness, the focused app's class (never its title), which
# audio output is playing, and running totals the kernel keeps (CPU clock steps, idle states, CPU
# time, context switches, interrupts, disk and Wi-Fi traffic, suspends), so averages between rows
# are exact. power-summary.py turns the log into figures.
# Runs as the user. It needs taris_smc_keys loaded with sample= (see test-install.sh); a row taken
# while the module isn't loaded gets empty SMC fields. Each row costs one hyprctl call and one
# sleep process, plus reading the files below; the log's own CPU time is in every row
# (self_cpu_ticks).
# Usage:
#   systemd-run --user --unit=taris-power-log "$PWD/dev/power/smc-keys/power-log.sh" [INTERVAL]
#     (from the checkout: systemd-run takes an absolute path)
#   systemctl --user stop taris-power-log
# or in a terminal: dev/power/smc-keys/power-log.sh [INTERVAL] (Ctrl+C stops it)

set -uo pipefail

interval=${1:-30}
if [[ ! $interval =~ ^[0-9]+$ ]] || (( 10#$interval < 5 || 10#$interval > 3600 )); then
  echo "INTERVAL is a whole number of seconds from 5 to 3600." >&2
  exit 1
fi
interval=$(( 10#$interval ))

here=$(cd "$(dirname "$0")" && pwd)
sample=/sys/kernel/taris-smc/sample
bat=/sys/class/power_supply/macsmc-battery
ac=/sys/class/power_supply/macsmc-ac/online
bl=/sys/class/backlight/apple-panel-bl
net=/sys/class/net/wld0/statistics
disk=nvme0n1
# MacBook Pro J293's UCM (alsa-ucm-conf-asahi): JackDevice 0, SpeakerDevice 1
jack=/proc/asound/card1/pcm0p/sub0/status
speakers=/proc/asound/card1/pcm1p/sub0/status

# One line of a file into REPLY, empty if it can't be read
get() {
  REPLY=
  read -r REPLY < "$1" 2>/dev/null || true
}

if [[ ! -r $sample ]]; then
  echo "taris_smc_keys isn't loaded: load it with the keys to log" \
    "(test-install.sh KEY,KEY,...)." >&2
  exit 1
fi
keys=()
while read -r key _; do
  keys+=("$key")
done < "$sample"
if (( ${#keys[@]} == 0 )); then
  echo "taris_smc_keys samples no keys: reload it with sample=KEY,KEY,... (test-install.sh)." >&2
  exit 1
fi

# Clock steps of each cluster, and the CPUs in each
cpufreq=/sys/devices/system/cpu/cpufreq
freqs_e=() freqs_p=()
while read -r f _; do freqs_e+=("$f"); done < "$cpufreq/policy0/stats/time_in_state"
while read -r f _; do freqs_p+=("$f"); done < "$cpufreq/policy4/stats/time_in_state"
get "$cpufreq/policy0/affected_cpus"; read -ra cpus_e <<< "$REPLY"
get "$cpufreq/policy4/affected_cpus"; read -ra cpus_p <<< "$REPLY"

mkdir -p "$here/results"
printf -v stamp '%(%Y%m%d-%H%M%S)T' -1
file=$here/results/powerlog-$stamp.csv
exec {out}>>"$file"

get /proc/sys/kernel/random/boot_id; boot=$REPLY
get /proc/sys/kernel/osrelease; kernel=$REPLY
get "$bat/cycle_count"; cycles=$REPLY
get "$bat/energy_full"; full=$REPLY
get "$bat/energy_full_design"; design=$REPLY
get "$bl/max_brightness"; blmax=$REPLY
{
  printf '# taris power log, started %(%F %T %z)T, every %s s\n' -1 "$interval"
  printf '# boot %s, kernel %s, battery %s cycles, energy_full %s uWh of %s design\n' \
    "$boot" "$kernel" "$cycles" "$full" "$design"
  printf '# brightness max %s; SMC keys: %s\n' "$blmax" "${keys[*]}"
  printf '# charge_counter is SMC BAAC as the driver gives it: mA*s (measured), not uAh\n'
  printf '# audio_jack/audio_speakers: ALSA state of card1 pcm0p/pcm1p (Bluetooth audio not seen)\n'
  printf '# cumulative: ticks_* and self_cpu_ticks in USER_HZ, tis_* in 10 ms, idle_* in us,\n'
  printf '#   disk_* in 512-byte sectors, wifi_* in bytes\n'
} >&"$out"

header=(t_real uptime suspends ac status capacity charge_counter voltage_uv current_ua power_uw
  energy_uwh temp_dc brightness window workspace audio_jack audio_speakers)
for k in "${keys[@]}"; do header+=("smc_$k"); done
header+=(ticks_user ticks_nice ticks_system ticks_idle ticks_iowait ticks_irq ticks_softirq
  ctxt intr forks)
for f in "${freqs_e[@]}"; do header+=("tis_e_$f"); done
for f in "${freqs_p[@]}"; do header+=("tis_p_$f"); done
header+=(idle_e_wfi_us idle_e_wfi_n idle_e_pd_us idle_e_pd_n idle_p_wfi_us idle_p_wfi_n
  idle_p_pd_us idle_p_pd_n disk_read disk_written wifi_rx wifi_tx self_cpu_ticks)
# A joined line with commas, without a subshell (which would start a process every row)
put_line() {
  local IFS=,
  printf '%s\n' "$*" >&"$out"
}
put_line "${header[@]}"

# The wait between rows is a background sleep: wait returns as soon as a trapped signal comes,
# so stopping is immediate (bash's builtin sleep and read -t both run to the end first)
stopping=0
pause=
trap 'stopping=1' TERM INT
trap 'if [[ -n $pause ]]; then kill "$pause" 2>/dev/null; fi' EXIT

audio_state() {
  get "$1"
  if [[ $REPLY == "closed" || -z $REPLY ]]; then
    REPLY=closed
  else
    REPLY=${REPLY#state: }
  fi
}

# The four idle counters of a cluster: WFI time and entries, CPU PD time and entries
idle_sums() {
  local c wt=0 wn=0 pt=0 pn=0 d
  for c in "$@"; do
    d=/sys/devices/system/cpu/cpu$c/cpuidle
    get "$d/state0/time"; wt=$(( wt + ${REPLY:-0} ))
    get "$d/state0/usage"; wn=$(( wn + ${REPLY:-0} ))
    get "$d/state1/time"; pt=$(( pt + ${REPLY:-0} ))
    get "$d/state1/usage"; pn=$(( pn + ${REPLY:-0} ))
  done
  row+=("$wt" "$wn" "$pt" "$pn")
}

collect() {
  local -A smc=() tis=()
  local name v rest f line class= ws=
  row=("$EPOCHREALTIME")
  get /proc/uptime; row+=("${REPLY%% *}")
  get /sys/power/suspend_stats/success; row+=("$REPLY")
  get "$ac"; row+=("$REPLY")
  for name in status capacity charge_counter voltage_now current_now power_now energy_now temp; do
    get "$bat/$name"; row+=("$REPLY")
  done
  get "$bl/actual_brightness"; row+=("$REPLY")

  # Class and workspace of the focused window, never its title; commas would split the CSV
  line=$(hyprctl activewindow 2>/dev/null) || line=
  if [[ $line =~ $'\n'[[:space:]]*class:\ ([^$'\n']*) ]]; then
    class=${BASH_REMATCH[1]}
  fi
  if [[ $line =~ $'\n'[[:space:]]*workspace:\ [-0-9]+\ \(([^$'\n']*)\) ]]; then
    ws=${BASH_REMATCH[1]}
  fi
  row+=("${class//,/;}" "${ws//,/;}")

  audio_state "$jack"; row+=("$REPLY")
  audio_state "$speakers"; row+=("$REPLY")

  if [[ -r $sample ]]; then
    while read -r name v _; do
      if [[ $v != "error" ]]; then smc[$name]=$v; fi
    done < "$sample" 2>/dev/null
  fi
  for name in "${keys[@]}"; do row+=("${smc[$name]:-}"); done

  local cu=0 cn=0 cs=0 ci=0 cw=0 cq=0 csq=0 ctxt= intr= forks=
  while read -r name rest; do
    case $name in
      cpu) read -r cu cn cs ci cw cq csq _ <<< "$rest" ;;
      ctxt) ctxt=$rest ;;
      intr) intr=${rest%% *} ;;
      processes) forks=$rest ;;
    esac
  done < /proc/stat
  row+=("$cu" "$cn" "$cs" "$ci" "$cw" "$cq" "$csq" "$ctxt" "$intr" "$forks")

  while read -r f v; do tis[e$f]=$v; done < "$cpufreq/policy0/stats/time_in_state"
  while read -r f v; do tis[p$f]=$v; done < "$cpufreq/policy4/stats/time_in_state"
  for f in "${freqs_e[@]}"; do row+=("${tis[e$f]:-}"); done
  for f in "${freqs_p[@]}"; do row+=("${tis[p$f]:-}"); done

  idle_sums "${cpus_e[@]}"
  idle_sums "${cpus_p[@]}"

  local dr= dw= major minor dev f1 f2 f3 f4 f5 f6 f7
  while read -r major minor dev f1 f2 f3 f4 f5 f6 f7 _; do
    if [[ $dev == "$disk" ]]; then dr=$f3; dw=$f7; break; fi
  done < /proc/diskstats
  row+=("$dr" "$dw")
  get "$net/rx_bytes"; row+=("$REPLY")
  get "$net/tx_bytes"; row+=("$REPLY")

  # utime + stime + cutime + cstime: this script and the hyprctl calls it waited for
  local -a st
  get /proc/$$/stat; read -ra st <<< "${REPLY##*) }"
  row+=("$(( st[11] + st[12] + st[13] + st[14] ))")
}

next=${EPOCHREALTIME/./}
while (( ! stopping )); do
  collect
  put_line "${row[@]}"

  # Rows stay on a fixed grid from the start, so the time spent collecting doesn't add up
  next=$(( next + interval * 1000000 ))
  now=${EPOCHREALTIME/./}
  wait_us=$(( next - now ))
  if (( wait_us < 0 || wait_us > interval * 1000000 )); then
    # Behind (after a suspend, or the clock set forward) or far ahead (the clock set back, e.g.
    # by an NTP or Tor time sync): a new grid from now, so a clock jump never stalls the log
    wait_us=$(( interval * 1000000 ))
    next=$(( now + wait_us ))
  fi
  printf -v secs '%d.%06d' $(( wait_us / 1000000 )) $(( wait_us % 1000000 ))
  sleep "$secs" &
  pause=$!
  wait "$pause" || true
  # Interrupted by a stop: the sleep is still running and not yet reaped, so its PID is still its
  # own. After a normal wait it's reaped and the PID may belong to anything: never kill it then.
  if (( stopping )); then
    kill "$pause" 2>/dev/null || true
  fi
  pause=
done

printf '# stopped %(%F %T %z)T\n' -1 >&"$out"
