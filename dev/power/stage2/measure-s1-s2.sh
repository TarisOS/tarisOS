#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# A/B measurement of Stage 2 S1 (kernel.sched_util_clamp_min_rt_default = 0) and S2
# (vm.compaction_proactiveness = 0), switched at runtime: nothing is installed, and the values
# found at the start are put back at the end, also if the script is interrupted.
# Three settings, as found / S1 / S1 + S2, each measured twice in turn (so slow drift cancels), on
# the idle desktop and then with audio playing (digital silence through the speakers: the whole
# speaker DSP chain runs, nothing is heard). Each block settles 15 s, then measures 60 s: battery
# power from its coulomb counter, the SMC rails (taris_smc_keys), time at each clock step,
# kcompactd's wake-ups; with audio, PipeWire's errors (ERR) and how much of each cycle the DSP
# takes (B/Q, 1.0 = the deadline), from pw-top; and that the audio threads got the new minimum.
# Results: results/s1-s2-<time>.csv (one line per block), results/s1-s2-<time>.txt (summary).
# Needs taris_smc_keys loaded (smc-keys/test-install.sh), and the Mac on battery for the battery
# figures. Takes about 17 minutes; leave the Mac alone meanwhile.
# Run by the maintainer, as root:
#   sudo dev/power/stage2/measure-s1-s2.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
cpufreq=/sys/devices/system/cpu/cpufreq
stamp=$(date +%Y%m%d-%H%M%S)
out=$here/results/s1-s2-$stamp.csv
summary=$here/results/s1-s2-$stamp.txt
rt_key=kernel.sched_util_clamp_min_rt_default
cp_key=vm.compaction_proactiveness

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ ! -r $power ]]; then
  echo "taris_smc_keys isn't loaded: run dev/power/smc-keys/test-install.sh" \
    "first." >&2
  exit 1
fi
if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
  echo "Start it with sudo from your own account: the audio plays in your session." >&2
  exit 1
fi
# Audio runs with the session's own environment, taken from the shell's process
shell_pid=$(pgrep -u "$SUDO_USER" -x qs -o || true)
if [[ -z $shell_pid ]]; then
  echo "No Taris shell running for $SUDO_USER: log in to the desktop first." >&2
  exit 1
fi
mapfile -d '' session_env < "/proc/$shell_pid/environ"
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")
kcompactd=$(pgrep -x kcompactd0 || true)
if [[ -z $kcompactd ]]; then
  echo "No kcompactd0 thread found." >&2
  exit 1
fi

orig_rt=$(sysctl -n "$rt_key")
orig_cp=$(sysctl -n "$cp_key")
if (( orig_rt == 0 || orig_cp == 0 )); then
  echo "S1 or S2 is already applied ($rt_key=$orig_rt, $cp_key=$orig_cp): the comparison needs" \
    "the kernel's defaults (taris-hardware 1.0.0-7, or both values set back for the run)." >&2
  exit 1
fi
mkdir -p "$here/results"
player=

stop_player() {
  if [[ -n $player ]]; then
    kill "$player" 2>/dev/null || true
    pkill -u "$SUDO_USER" -f '^pw-cat -p --raw' 2>/dev/null || true
    if ! pgrep -u "$SUDO_USER" -f '^pw-cat -p --raw' >/dev/null; then
      wait "$player" 2>/dev/null || true
    fi
    player=
  fi
}

restore() {
  stop_player
  sysctl -q -w "$rt_key=$orig_rt" "$cp_key=$orig_cp"
}
trap restore EXIT

apply() {
  case $1 in
    found) sysctl -q -w "$rt_key=$orig_rt" "$cp_key=$orig_cp" ;;
    s1) sysctl -q -w "$rt_key=0" "$cp_key=$orig_cp" ;;
    s1s2) sysctl -q -w "$rt_key=0" "$cp_key=0" ;;
  esac
}

# Digital silence through the default output (the speakers): pw-cat reads zeros
play_silence() {
  "${as_user[@]}" pw-cat -p --raw --format s16 --rate 48000 --channels 2 /dev/zero \
    >/dev/null 2>&1 &
  player=$!
}

ctx_switches() {
  awk '/^(voluntary|nonvoluntary)_ctxt_switches/ {s += $2} END {print s}' "/proc/$1/status"
}

# Time at each clock step of a cluster, as "freq:ticks" (10 ms ticks)
tis() {
  awk '{printf "%s:%s ", $1, $2}' "$cpufreq/$1/stats/time_in_state"
}

# The lowest effective uclamp.min among PipeWire's, WirePlumber's and pipewire-pulse's real-time
# threads (data-loop): what S1 changes
audio_rt_min() {
  local p t v min=
  for p in $(pgrep -u "$SUDO_USER" -x 'pipewire|wireplumber|pipewire-pulse'); do
    for t in /proc/$p/task/*; do
      if [[ $(<"$t/comm") == data-loop* ]]; then
        v=$(awk '/effective uclamp.min/ {print $NF}' "$t/sched")
        if [[ -z $min ]] || (( v < min )); then
          min=$v
        fi
      fi
    done
  done
  echo "${min:--}"
}

# ERR and the highest B/Q of the speaker chain's nodes, from pw-top's last report
pw_state() {
  "${as_user[@]}" timeout 10 pw-top -b -n 3 2>/dev/null | awk '
    /^S/ && /ID/ { err = 0; bq = 0; next }
    / alsa_output\.platform-sound\.RawSpeakers$/ ||
    / (audio_effect|effect_output)\.j293-convolver$/ {
      err += $9; if ($8 != "---" && $8 + 0 > bq) bq = $8 + 0
    }
    END { printf "%d %.3f", err, bq }'
}

echo "workload,setting,round,ac,battery_w,PSTR,PMVR,PPMR,PP0b,PPbb,PP7b,tis_e,tis_p,$(
  )kcompactd_per_s,audio_rt_min,pw_err,pw_bq_max" > "$out"
start_time=$(date '+%Y-%m-%d %H:%M:%S')

block() {
  local workload=$1 setting=$2 round=$3 i line ac q0 q1 v0 v1 t0 t1 k0 k1 e0 e1 p0 p1
  local rtmin err0=0 pwerr pwbq
  local -a smc=()
  apply "$setting"
  sleep 15
  rtmin=$(audio_rt_min)
  if [[ $workload == "audio" ]]; then
    read -r err0 _ <<< "$(pw_state)"
  fi
  ac=$(<"/sys/class/power_supply/macsmc-ac/online")
  q0=$(<"$bat/charge_counter"); v0=$(<"$bat/voltage_now"); t0=${EPOCHREALTIME/./}
  k0=$(ctx_switches "$kcompactd")
  e0=$(tis policy0); p0=$(tis policy4)
  local sums="0 0 0 0 0 0"
  for (( i = 0; i < 60; i++ )); do
    line=$(awk '$1 ~ /^(PSTR|PMVR|PPMR|PP0b|PPbb|PP7b)$/ {v[$1] = $2}
      END {print v["PSTR"], v["PMVR"], v["PPMR"], v["PP0b"], v["PPbb"], v["PP7b"]}' "$power")
    sums=$(awk -v a="$sums" -v b="$line" 'BEGIN {split(a, x); split(b, y)
      for (j = 1; j <= 6; j++) printf "%.6f ", x[j] + y[j]}')
    sleep 1
  done
  q1=$(<"$bat/charge_counter"); v1=$(<"$bat/voltage_now"); t1=${EPOCHREALTIME/./}
  k1=$(ctx_switches "$kcompactd")
  e1=$(tis policy0); p1=$(tis policy4)
  local pw="0 0"
  if [[ $workload == "audio" ]]; then
    pw=$(pw_state)
  fi
  # charge_counter is in mA*s (as macsmc-power passes SMC BAAC through): W = C x V / s
  local bw
  bw=$(awk -v q0="$q0" -v q1="$q1" -v v0="$v0" -v v1="$v1" -v t0="$t0" -v t1="$t1" -v ac="$ac" \
    'BEGIN {if (ac != "0") {print ""; exit}
      printf "%.4f", (q0 - q1) / 1000 * (v0 + v1) / 2e6 / ((t1 - t0) / 1e6)}')
  read -ra smc <<< "$(awk -v a="$sums" \
    'BEGIN {split(a, x); for (j = 1; j <= 6; j++) printf "%.4f ", x[j] / 60}')"
  read -r pwerr pwbq <<< "$pw"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s","%s",%s,%s,%s,%s,%s\n' \
    "$workload" "$setting" "$round" "$ac" "$bw" "${smc[@]}" \
    "$(echo "$e0" "|" "$e1")" "$(echo "$p0" "|" "$p1")" \
    "$(awk -v a="$k0" -v b="$k1" -v t0="$t0" -v t1="$t1" \
      'BEGIN {printf "%.2f", (b - a) / ((t1 - t0) / 1e6)}')" \
    "$rtmin" "$(( pwerr - err0 ))" "$pwbq" >> "$out"
  echo "  $workload $setting round $round: battery ${bw:-n/a} W, PSTR ${smc[0]} W"
}

echo "Measuring into $out:"
for workload in idle audio; do
  if [[ $workload == "audio" ]]; then
    play_silence
    sleep 20
  fi
  for round in 1 2; do
    for setting in found s1 s1s2; do
      block "$workload" "$setting" "$round"
    done
  done
done
stop_player
restore
echo "Values restored: $rt_key=$(sysctl -n "$rt_key"), $cp_key=$(sysctl -n "$cp_key")."

{
  echo "Audio warnings and errors in the journal during the run:"
  journalctl --since "$start_time" -p warning --no-pager -q \
    _COMM=pipewire _COMM=wireplumber _COMM=pipewire-pulse _COMM=speakersafetyd || true
  echo "(end)"
} > "$summary.journal"

python3 -I - "$out" >> "$summary" <<'EOF'
import csv, statistics as st, sys
rows = list(csv.DictReader(open(sys.argv[1])))

def steps(spec):
    # spec: "f:t f:t ... | f:t f:t ..."; ticks at each clock step during the block
    a, b = spec.split("|")
    t0 = dict(x.split(":") for x in a.split()); t1 = dict(x.split(":") for x in b.split())
    return {int(f): int(t1[f]) - int(t0[f]) for f in t0}

# The top two steps each cluster ran at in the whole run: the list also has boost steps that
# are switched off here and never used
top = {}
for col in ("tis_e", "tis_p"):
    used = {f for r in rows for f, t in steps(r[col]).items() if t > 0}
    top[col] = sorted(used)[-2:]

def share_top(spec, col):
    d = steps(spec)
    return sum(d[f] for f in top[col]) / (sum(d.values()) or 1) * 100

print("Mean of the two rounds per setting (battery W from the coulomb counter; SMC W; share of")
print("time at each cluster's top two clock steps used, MHz: E %s, P %s; kcompactd wake-ups/s;" % (
    "/".join(str(f // 1000) for f in top["tis_e"]), "/".join(str(f // 1000) for f in top["tis_p"])))
print("audio threads' minimum; pw-top ERR and B/Q, which pw-top's batch mode doesn't fill in):\n")
for wl in ("idle", "audio"):
    print(wl)
    print("  %-6s %8s %7s %7s %7s %7s %7s %6s %6s %6s %5s %4s %6s" % (
        "set", "battery", "PSTR", "PMVR", "PP0b", "PPbb", "PP7b", "Etop%", "Ptop%", "kcmp/s",
        "rtmin", "err", "B/Q"))
    for s in ("found", "s1", "s1s2"):
        r = [x for x in rows if x["workload"] == wl and x["setting"] == s]
        if not r:
            continue
        def m(k):
            v = [float(x[k]) for x in r if x[k] not in ("", None)]
            return st.mean(v) if v else float("nan")
        et = st.mean(share_top(x["tis_e"], "tis_e") for x in r)
        pt = st.mean(share_top(x["tis_p"], "tis_p") for x in r)
        print("  %-6s %8.3f %7.3f %7.3f %7.3f %7.3f %7.3f %6.1f %6.1f %6.2f %5s %4d %6.3f" % (
            s, m("battery_w"), m("PSTR"), m("PMVR"), m("PP0b"), m("PPbb"), m("PP7b"), et, pt,
            m("kcompactd_per_s"), "/".join(sorted(set(x["audio_rt_min"] for x in r))),
            sum(int(x["pw_err"]) for x in r), max(float(x["pw_bq_max"]) for x in r)))
    print()
print("Round to round (battery W), to judge the noise:")
for wl in ("idle", "audio"):
    for s in ("found", "s1", "s1s2"):
        v = [x["battery_w"] for x in rows if x["workload"] == wl and x["setting"] == s]
        print("  %-5s %-6s %s" % (wl, s, "  ".join(v)))
EOF
cat "$summary.journal" >> "$summary"
rm -f "$summary.journal"
chown -R --reference="$here" "$here/results"
cat "$summary"
