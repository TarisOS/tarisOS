#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 2 S9: what a clock ceiling (the scheduler's cpu.uclamp.max on a cgroup) does to a
# CPU-heavy background job: its energy and its time. The job is single-threaded xz -6 on a fixed
# 24 MB slice of /usr/lib/libLLVM.so (compressing, as package builds and updates do), run in a
# transient scope of the user's own (systemd-run --user, Delegate=yes) whose child cgroup gets the
# ceiling: none, 50 % or 25 %. Three rounds in alternating order; before each job 15 s of idle
# give the baseline, so the job's energy is counted above idle. perf counts the job's own cycles
# on each cluster (where it ran). Runs as the user; changes nothing outside its scopes.
# Results: results/s9-<time>.txt. About 6 minutes, on battery; leave the Mac alone meanwhile.
# Usage, from the checkout: dev/power/stage2/measure-s9.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bat=/sys/class/power_supply/macsmc-battery
mkdir -p "$here/results"
out=$here/results/s9-$(date +%Y%m%d-%H%M%S).txt
sample=$here/results/s9-sample.bin

if (( EUID == 0 )); then
  echo "Run it as your own user (the scopes are your session's)." >&2
  exit 1
fi
if [[ $(</sys/class/power_supply/macsmc-ac/online) != "0" ]]; then
  echo "Unplug the charger first: the energy comes from the battery's counter." >&2
  exit 1
fi
if [[ ! -f $sample ]]; then
  head -c 24M "$(readlink -f /usr/lib/libLLVM.so)" > "$sample"
fi

# Battery energy since a mark, in joules: charge_counter is mA*s (as macsmc-power passes SMC BAAC
# on), times the mean voltage
mark() {
  m_q=$(<"$bat/charge_counter"); m_v=$(<"$bat/voltage_now"); m_t=${EPOCHREALTIME/./}
}
since_mark() {
  local q v t
  q=$(<"$bat/charge_counter"); v=$(<"$bat/voltage_now"); t=${EPOCHREALTIME/./}
  awk -v q0="$m_q" -v q1="$q" -v v0="$m_v" -v v1="$v" -v t0="$m_t" -v t1="$t" \
    'BEGIN {printf "%.3f %.3f", (q0 - q1) / 1000 * (v0 + v1) / 2e6, (t1 - t0) / 1e6}'
}

# The job under a ceiling (max, or a percentage), in its own scope; perf's per-cluster cycles.
# perf scales a count up by how much of the run its counter could count (a cluster's counter only
# counts while the job is on that cluster), so the true count is the value times that share
# (field 5 of -x output)
run_job() {
  local cap=$1
  systemd-run --user --scope --quiet -p Delegate=yes --unit="taris-s9-$cap-$RANDOM" \
    bash -c 'me=$BASHPID
      cg=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)
      mkdir "$cg/job"
      echo "$me" > "$cg/job/cgroup.procs"
      echo +cpu > "$cg/cgroup.subtree_control"
      echo "$1" > "$cg/job/cpu.uclamp.max"
      exec perf stat -x, -e apple_icestorm_pmu/cycles/u,apple_firestorm_pmu/cycles/u \
        -- xz -6 -T1 -c "$2"' _ "$cap" "$sample" 2>&1 >/dev/null |
    awk -F, 'function n(x, pct) {return x ~ /^[0-9]+$/ ? sprintf("%.0f", x * pct / 100) : 0}
      /icestorm/ {e = n($1, $5)} /firestorm/ {p = n($1, $5)} END {printf "%s %s", e + 0, p + 0}'
}

echo "# S9 $(date '+%F %T'): cap, energy above idle (J), job time (s), idle W, E and P cycles" \
  > "$out"
for round in 1 2 3; do
  if (( round == 2 )); then order=(25 50 max); else order=(max 50 25); fi
  for cap in "${order[@]}"; do
    mark; sleep 15; read -r idle_j idle_s <<< "$(since_mark)"
    mark; read -r ecyc pcyc <<< "$(run_job "$cap")"; read -r job_j job_s <<< "$(since_mark)"
    line=$(awk -v ij="$idle_j" -v is="$idle_s" -v jj="$job_j" -v js="$job_s" -v c="$cap" \
      -v e="$ecyc" -v p="$pcyc" -v r="$round" \
      'BEGIN {w = ij / is; printf "round %d cap %-3s %7.2f J %6.2f s idle %.3f W E %s P %s",
        r, c, jj - w * js, js, w, e, p}')
    echo "$line" | tee -a "$out"
  done
done

python3 -I - "$out" >> "$out" <<'EOF'
import re, statistics as st, sys
rows = [l for l in open(sys.argv[1]) if l.startswith("round")]
data = {}
for l in rows:
    m = re.match(r"round (\d) cap (\S+)\s+([\d.-]+) J\s+([\d.]+) s idle ([\d.]+) W"
                 r" E (\d*) P (\d*)", l)
    if m:
        r, cap, j, s, _, e, p = m.groups()
        data.setdefault(cap, []).append((int(r), float(j), float(s), int(e or 0), int(p or 0)))
print("\nMean of the rounds (energy above idle; time; share of the job's cycles on the E-cores):")
for cap in ("max", "50", "25"):
    v = data.get(cap, [])
    if v:
        share = st.mean(e / (e + p) * 100 if e + p else 0 for _, _, _, e, p in v)
        print(f"  cap {cap:3}  {st.mean(j for _, j, _, _, _ in v):6.2f} J  "
              f"{st.mean(s for _, _, s, _, _ in v):6.2f} s  E-cores {share:5.1f} %")
print("Paired, against the same round's uncapped job:")
for cap in ("50", "25"):
    d = []
    for r in (1, 2, 3):
        a = [x for x in data.get("max", []) if x[0] == r]
        b = [x for x in data.get(cap, []) if x[0] == r]
        if a and b:
            d.append((b[0][1] / a[0][1] - 1, b[0][2] / a[0][2] - 1))
    if d:
        print(f"  cap {cap}: energy {st.mean(x for x, _ in d) * 100:+.0f} % "
              f"(rounds " + ", ".join(f"{x * 100:+.0f} %" for x, _ in d) + f"), time "
              f"{st.mean(y for _, y in d) * 100:+.0f} %")
EOF
cat "$out" | sed -n '/^Mean/,$p'
