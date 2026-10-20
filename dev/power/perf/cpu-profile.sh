#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 1 item 4: which work runs on which CPU cluster, and how fast. For SECONDS (default 60) of
# whatever the Mac is doing, perf samples cycles and instructions on the efficiency cores
# (apple_icestorm_pmu, cpus 0-3) and the performance cores (apple_firestorm_pmu, cpus 4-7),
# kernel included, at 250 samples a second while a core runs; /proc/stat gives each cluster's
# busy time. The report: per cluster the cycles, instructions, instructions per cycle, busy share
# and average clock while busy (cycles / busy time), and the threads and processes taking the most
# cycles on each cluster. Read-only: perf only counts.
# Results: results/cpu-profile-<time>.txt, with perf's own data next to it (.data, for perf
# report). Use the Mac as normal meanwhile, or leave it idle; the agent's own work shows as
# claude.
# Run by the maintainer, as root, from the checkout:
#   sudo dev/power/perf/cpu-profile.sh [SECONDS]

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
seconds=${1:-60}
if [[ ! $seconds =~ ^[0-9]+$ ]] || (( 10#$seconds < 10 || 10#$seconds > 3600 )); then
  echo "SECONDS is a whole number from 10 to 3600." >&2
  exit 1
fi
seconds=$(( 10#$seconds ))
if (( EUID != 0 )); then
  echo "Run as root: sudo $0 $*" >&2
  exit 1
fi
for pmu in apple_icestorm_pmu apple_firestorm_pmu; do
  if [[ ! -d /sys/bus/event_source/devices/$pmu ]]; then
    echo "No $pmu: this needs the M1's CPU counters." >&2
    exit 1
  fi
done
mkdir -p "$here/results"
stamp=$(date +%Y%m%d-%H%M%S)
data=$here/results/cpu-profile-$stamp.data
out=$here/results/cpu-profile-$stamp.txt
stat0=$here/results/.cpu-profile-$stamp.stat0
stat1=$here/results/.cpu-profile-$stamp.stat1
report=$here/results/.cpu-profile-$stamp.report
trap 'rm -f "$stat0" "$stat1" "$report"' EXIT

events=apple_icestorm_pmu/cycles/,apple_icestorm_pmu/instructions/
events+=,apple_firestorm_pmu/cycles/,apple_firestorm_pmu/instructions/

echo "Sampling for $seconds s..."
grep '^cpu[0-9]' /proc/stat > "$stat0"
perf record -q -a -F 250 -e "$events" -o "$data" -- sleep "$seconds" 2>/dev/null
grep '^cpu[0-9]' /proc/stat > "$stat1"

{
  echo "# $(date '+%F %T'), $seconds s, kernel $(uname -r), $(perf --version)"
  for sort in comm pid; do
    echo "## sort=$sort"
    perf report -i "$data" --stdio --sort "$sort" 2>/dev/null
  done
} > "$report"

python3 -I - "$stat0" "$stat1" "$report" > "$out" <<'EOF'
import re, sys
stat0, stat1, report = sys.argv[1], sys.argv[2], sys.argv[3]

def ticks(path):
    # Busy and all ticks (USER_HZ) per CPU: user nice system idle iowait irq softirq steal ...
    out = {}
    for line in open(path):
        f = line.split()
        v = [int(x) for x in f[1:9]]
        out[int(f[0][3:])] = (v[0] + v[1] + v[2] + v[5] + v[6] + v[7], sum(v))
    return out

t0, t1 = ticks(stat0), ticks(stat1)

def max_mhz(cpu):
    with open(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_max_freq") as f:
        return int(f.read()) / 1000

clusters = {"E": ("apple_icestorm_pmu", range(0, 4)), "P": ("apple_firestorm_pmu", range(4, 8))}
counts, tops, sort, event = {}, {}, None, None
header = ""
for line in open(report):
    if line.startswith("# 20"):
        header = line.strip("# \n")
    m = re.match(r"## sort=(\w+)", line)
    if m:
        sort = m.group(1)
        continue
    m = re.match(r"# Samples: \S+\s+of event .(\S+?)/(\w+)/.", line)
    if m:
        event = (m.group(1), m.group(2))
        continue
    m = re.match(r"# Event count \(approx\.\): (\d+)", line)
    if m and sort == "comm":
        counts[event] = int(m.group(1))
        continue
    m = re.match(r"\s+([\d.]+)%\s+(.+?)\s*$", line)
    if m and event and event[1] == "cycles":
        tops.setdefault((sort, event[0]), []).append((float(m.group(1)), m.group(2)))

print(f"CPU profile: {header}\n")
print("Per cluster (kernel included; clock = cycles / busy time, summed over its cores):")
print(f"  {'':8} {'cycles':>15} {'instructions':>15} {'IPC':>5} {'busy':>7}"
      f" {'clock while busy':>17}")
for name, (pmu, cpus) in clusters.items():
    cyc, ins = counts.get((pmu, "cycles"), 0), counts.get((pmu, "instructions"), 0)
    # A CPU missing from /proc/stat (none on this Mac) counts as idle rather than failing
    busy = sum(t1.get(c, (0, 0))[0] - t0.get(c, (0, 0))[0] for c in cpus) / 100
    allt = sum(t1.get(c, (0, 0))[1] - t0.get(c, (0, 0))[1] for c in cpus) / 100
    ipc = f"{ins / cyc:.2f}" if cyc else "-"
    mhz = f"{cyc / busy / 1e6:.0f} MHz" if busy else "-"
    share = f"{busy / allt * 100:.1f} %" if allt else "-"
    label = f"{name}-cores"
    print(f"  {label:8} {cyc:15,d} {ins:15,d} {ipc:>5} {share:>7} {mhz:>17}")
    # A clock above the cluster's top one is impossible: /proc/stat's busy time misses work the
    # counters see (interrupts handled while a core is idle are counted as idle time there)
    if busy and cyc / busy / 1e6 > max_mhz(cpus[0]):
        print(f"    (above the {name}-cores' top clock, {max_mhz(cpus[0]):.0f} MHz: the busy time"
              " misses work the counters saw, so this clock isn't reliable)")
print("\nswapper is each core's idle task: interrupts and softirqs handled while a core is idle,"
      " and the entry\nand exit of idle states, are counted under it.")
for sort, title in (("comm", "threads (by name)"), ("pid", "processes")):
    for name, (pmu, _) in clusters.items():
        rows = sorted(tops.get((sort, pmu), []), reverse=True)[:15]
        print(f"\nTop {title} by cycles on the {name}-cores:")
        for pct, who in rows:
            if pct >= 0.5:
                print(f"  {pct:6.2f} %  {who}")
EOF
cat "$out"
chown -R --reference="$here" "$here/results"
