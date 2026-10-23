#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 1 item 5, the re-trace after each stage: what wakes the machine while it's idle. Writes
# results/trace-<time>.txt next to this script with
# - a snapshot: power domains, the CPU energy model, the Wi-Fi link's ASPM states, wakeup sources,
#   CPU clock residency, interrupts;
# - a 20 s kernel trace of interrupts, timers, work items, task wakeups and cross-core interrupts
#   (IPIs, by call site and callback), each counted per second, the top of each list.
# With --sound, digital silence plays through the default output during the trace (pw-cat, as the
# user who owns this folder): the audio path's own wake-ups. Read-only: the tracing state (events,
# buffer size, on/off) and the debug file system are put back as they were.
# Written again 2026-10-23 for collect-root.sh and collect-root-3.sh, lost with the old install.
# Run as root, with the machine left alone:
#   sudo dev/power/trace/collect-root.sh [--sound]

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
seconds=20
sound=""
if [[ ${1:-} == "--sound" ]]; then
  sound=1
fi
if (( EUID != 0 )); then
  echo "Run as root: sudo $0 $*" >&2
  exit 1
fi

owner=$(stat -c %U "$here")
out=$here/results/trace-$(date +%Y%m%d-%H%M%S)${sound:+-sound}.txt
mkdir -p "$here/results"
tr=/sys/kernel/tracing
dbg_mounted=""
if [[ ! -d /sys/kernel/debug/pm_genpd ]]; then
  mount -t debugfs none /sys/kernel/debug 2>/dev/null && dbg_mounted=1
fi

events=(irq:irq_handler_entry timer:timer_expire_entry timer:hrtimer_expire_entry
  workqueue:workqueue_execute_start sched:sched_wakeup ipi:ipi_send_cpu ipi:ipi_send_cpumask)

# The tracing state as found, put back on any exit
old_on=$(<"$tr/tracing_on")
# "7 (expanded: 1408)" before tracing is first used: the size it takes then, a number either way
old_size=$(sed -E 's/.*expanded: ([0-9]+).*/\1/; s/^([0-9]+).*/\1/' "$tr/buffer_size_kb")
old_events=$(<"$tr/set_event")
player=""
restore() {
  [[ -n $player ]] && kill "$player" 2>/dev/null
  echo 0 >"$tr/tracing_on"
  : >"$tr/set_event"
  [[ -n $old_events ]] && printf '%s\n' "$old_events" >"$tr/set_event"
  echo "$old_size" >"$tr/buffer_size_kb"
  : >"$tr/trace"
  echo "$old_on" >"$tr/tracing_on"
  [[ -n $dbg_mounted ]] && umount /sys/kernel/debug
  chown "$owner": "$out" 2>/dev/null
}
trap restore EXIT

section() {
  printf '\n## %s\n\n' "$1" >>"$out"
}

{
  echo "# Trace $(date '+%F %T'), kernel $(uname -r), ${seconds} s${sound:+, digital silence playing}"
  echo "# Battery: $(cat /sys/class/power_supply/macsmc-battery/status 2>/dev/null)," \
    "$(awk '{printf "%.2f W", -$1/1e6}' /sys/class/power_supply/macsmc-battery/power_now 2>/dev/null)," \
    "brightness $(cat /sys/class/backlight/*/brightness 2>/dev/null | head -n 1)"
} >"$out"

section "Power domains (on)"
grep -E '^\S+\s+on' /sys/kernel/debug/pm_genpd/pm_genpd_summary >>"$out" 2>&1
section "Energy model"
for pd in /sys/kernel/debug/energy_model/*/; do
  printf '%s: ' "$(basename "$pd")"
  for ps in "$pd"ps:*/; do
    printf '%s MHz %s mW; ' "$(( $(<"$ps/frequency") / 1000 ))" "$(( $(<"$ps/power") / 1000 ))"
  done
  echo
done >>"$out" 2>&1
section "Wi-Fi link (ASPM)"
for dev in /sys/class/net/*/device; do
  [[ -d $dev/link ]] || continue
  printf '%s: ' "$(basename "$(dirname "$dev")")"
  for state in "$dev"/link/*aspm; do
    printf '%s=%s ' "$(basename "$state")" "$(<"$state")"
  done
  echo
done >>"$out" 2>&1
section "Wakeup sources (active count, event count)"
awk '$2 ~ /^[0-9]+$/ && $2 > 0' /sys/kernel/debug/wakeup_sources 2>/dev/null | sort -k3 -n -r | head -n 25 >>"$out"
section "CPU clock residency since boot (MHz: seconds)"
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
  printf '%s: ' "$(basename "$policy")"
  awk '{printf "%d: %.0f s; ", $1/1000, $2/100}' "$policy/stats/time_in_state"
  echo
done >>"$out"

# The trace
if [[ $sound ]]; then
  uid=$(id -u "$owner")
  runuser -u "$owner" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
    pw-cat -p --raw --format s16 --rate 48000 --channels 2 /dev/zero &
  player=$!
  sleep 3
fi
irq_before=$(mktemp)
cp /proc/interrupts "$irq_before"
echo 0 >"$tr/tracing_on"
: >"$tr/trace"
echo 16384 >"$tr/buffer_size_kb"
: >"$tr/set_event"
for e in "${events[@]}"; do
  echo "$e" >>"$tr/set_event" 2>/dev/null || echo "($e not in this kernel)" >>"$out"
done
echo 1 >"$tr/tracing_on"
sleep "$seconds"
echo 0 >"$tr/tracing_on"
raw=$(mktemp)
cat "$tr/trace" >"$raw"

section "Interrupts in ${seconds} s, per second (/proc/interrupts)"
python3 -I - "$irq_before" /proc/interrupts "$seconds" >>"$out" <<'PY'
import sys
def read(path):
    rows = {}
    for line in open(path).read().splitlines()[1:]:
        parts = line.split()
        if not parts:
            continue
        counts = [int(p) for p in parts[1:] if p.isdigit()]
        rows[parts[0].rstrip(":") + " " + " ".join(p for p in parts[1 + len(counts):])] = sum(counts)
    return rows
before, after, secs = read(sys.argv[1]), read(sys.argv[2]), float(sys.argv[3])
diff = sorted(((after[k] - before.get(k, 0)) / secs, k) for k in after)
for rate, name in reversed(diff[-25:]):
    if rate > 0:
        print(f"{rate:8.1f}/s  {name}")
PY

section "Trace, per second (top 25 of each)"
python3 -I - "$raw" "$seconds" >>"$out" <<'PY'
import re, sys
from collections import Counter
counts = {}
pattern = re.compile(r"^\s*(\S+)-\d+\s+\[\d+\].*?\s(\w+): (.*)$")
for line in open(sys.argv[1], errors="replace"):
    m = pattern.match(line)
    if not m:
        continue
    task, event, rest = m.groups()
    if event == "irq_handler_entry":
        key = re.search(r"name=(\S+)", rest)
    elif event in ("timer_expire_entry", "hrtimer_expire_entry"):
        key = re.search(r"function=(\S+)", rest)
    elif event == "workqueue_execute_start":
        key = re.search(r"function (\S+)", rest)
    elif event == "sched_wakeup":
        key = re.search(r"comm=(.*?) pid=", rest)
    elif event in ("ipi_send_cpu", "ipi_send_cpumask"):
        site = re.search(r"callsite=(\S+)", rest)
        back = re.search(r"callback=(\S+)", rest)
        key = None
        name = f"{site.group(1) if site else '?'} -> {back.group(1) if back else '?'} (from {task})"
        counts.setdefault("ipi", Counter())[name] += 1
        continue
    else:
        continue
    counts.setdefault(event, Counter())[key.group(1) if key else rest[:60]] += 1
secs = float(sys.argv[2])
for event, counter in counts.items():
    print(f"### {event}: {sum(counter.values()) / secs:.1f}/s\n")
    for name, n in counter.most_common(25):
        print(f"{n / secs:8.1f}/s  {name}")
    print()
PY
rm -f "$raw" "$irq_before"
echo "Saved $out"
