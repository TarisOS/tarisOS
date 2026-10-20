#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# An idle measurement to compare across a reboot, for changes that only take effect at boot
# (Stage 2 S5's workqueue.power_efficient, later S9-S11 and X3): run it once before, once after,
# with a LABEL for each. After 20 s to settle, 120 s of the idle desktop: battery power (coulomb
# counter), system power (PSTR through macsmc_hwmon, no module needed), cross-core interrupts
# (IPIs) and device interrupts per CPU, context switches, the E- and P-cores' share of idle time
# in deep idle (CPU PD), and every kernel work item queued (perf, workqueue:workqueue_queue_work):
# per workqueue, how many went to a CPU-bound pool and how many to an unbound one (cpu=-1).
# Read-only. Results: results/boot-idle-<LABEL>-<time>.txt (and perf's data). Needs the Mac on
# battery for the battery figure; leave it alone meanwhile, at the brightness it'll have in the
# other run.
# Run by the maintainer, as root, from the checkout:
#   sudo dev/power/stage2/measure-boot-idle.sh LABEL

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
label=${1:-}
if [[ ! $label =~ ^[A-Za-z0-9_.-]{1,40}$ ]]; then
  echo "Usage: sudo $0 LABEL   (letters, digits, . _ -; e.g. s5-off, s5-on)" >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo "Run as root: sudo $0 $*" >&2
  exit 1
fi
hwmon=
for h in /sys/class/hwmon/hwmon*; do
  if [[ $(<"$h/name") == "macsmc_hwmon" ]]; then
    hwmon=$h/power1_input
  fi
done
if [[ -z $hwmon ]]; then
  echo "No macsmc_hwmon power sensor found." >&2
  exit 1
fi
mkdir -p "$here/results"
stamp=$(date +%Y%m%d-%H%M%S)
base=$here/results/boot-idle-$label-$stamp
bat=/sys/class/power_supply/macsmc-battery
seconds=120

snapshot() {
  # /proc/interrupts, per-CPU /proc/stat lines, the cpuidle times, the battery
  {
    echo "## interrupts"; cat /proc/interrupts
    echo "## stat"; grep -E '^(cpu[0-9]|ctxt)' /proc/stat
    echo "## idle"
    for c in /sys/devices/system/cpu/cpu[0-9]*; do
      echo "${c##*/} $(<"$c/cpuidle/state0/time") $(<"$c/cpuidle/state1/time")"
    done
    echo "## battery $(<"$bat/charge_counter") $(<"$bat/voltage_now") ${EPOCHREALTIME/./}"
    echo "## ac $(</sys/class/power_supply/macsmc-ac/online)"
    echo "## brightness $(</sys/class/backlight/apple-panel-bl/actual_brightness)"
  } > "$1"
}

echo "Settling 20 s, then measuring $seconds s (label $label)..."
sleep 20
snapshot "$base.before"
perf record -q -a -e workqueue:workqueue_queue_work -o "$base.data" -- \
  bash -c 'for (( i = 0; i < '"$seconds"'; i++ )); do cat '"$hwmon"'; sleep 1; done' \
  > "$base.pstr" 2>/dev/null
snapshot "$base.after"
perf script -i "$base.data" -F cpu,trace 2>/dev/null > "$base.work"

python3 -I - "$base" "$label" "$seconds" "$(uname -r)" "$(</proc/cmdline)" > "$base.txt" <<'EOF'
import collections, re, statistics as st, sys
base, label, kernel, cmdline = sys.argv[1], sys.argv[2], sys.argv[4], sys.argv[5]
seconds = float(sys.argv[3])

def sections(path):
    out, cur = {}, None
    for line in open(path):
        if line.startswith("## "):
            parts = line[3:].split()
            cur = parts[0]
            out[cur] = parts[1:] if len(parts) > 1 else []
        elif cur:
            out.setdefault(cur + "_lines", []).append(line.rstrip("\n"))
    return out

a, b = sections(base + ".before"), sections(base + ".after")
ncpu = 8

def irqs(sec):
    out = {}
    for line in sec["interrupts_lines"][1:]:
        f = line.split()
        name = f[0].rstrip(":")
        counts = [int(x) for x in f[1:1 + ncpu] if x.isdigit()]
        if len(counts) == ncpu:
            out[name] = (counts, " ".join(f[1 + ncpu:]))
    return out

ia, ib = irqs(a), irqs(b)
q0, v0, t0 = (int(x) for x in a["battery"])
q1, v1, t1 = (int(x) for x in b["battery"])
dt = (t1 - t0) / 1e6
battery = None
if a["ac"][0] == "0" and b["ac"][0] == "0":
    battery = (q0 - q1) / 1000 * (v0 + v1) / 2e6 / dt
pstr = [int(x) / 1e6 for x in open(base + ".pstr") if x.strip()]

print(f"Idle at boot, label {label}: {seconds:.0f} s, kernel {kernel}")
print(f"  command line: {cmdline}")
print(f"  AC {a['ac'][0]}/{b['ac'][0]}, brightness {a['brightness'][0]} -> {b['brightness'][0]}")
print(f"  battery {battery:.3f} W" if battery is not None else "  battery: on AC, not measured")
print(f"  PSTR mean {st.mean(pstr):.3f} W (sd {st.pstdev(pstr):.3f}, {len(pstr)} samples)")

def rate(name):
    ca, cb = ia[name][0], ib[name][0]
    return [(y - x) / dt for x, y in zip(ca, cb)]

print("\nInterrupts per second, CPU 0-7 (E-cores 0-3, P-cores 4-7):")
for name in ("IPI0", "IPI1", "IPI4", "IPI5"):
    if name in ia:
        r = rate(name)
        print(f"  {name} {ia[name][1][:28]:28} " + " ".join(f"{x:6.1f}" for x in r)
              + f"  total {sum(r):7.1f}")
dev = [0.0] * ncpu
for name in ia:
    if not name.startswith("IPI") and name in ib:
        for i, x in enumerate(rate(name)):
            dev[i] += x
print(f"  device interrupts                  " + " ".join(f"{x:6.1f}" for x in dev)
      + f"  total {sum(dev):7.1f}")
top = sorted(((sum(rate(n)), n) for n in ia if not n.startswith("IPI") and n in ib), reverse=True)
print("  busiest device interrupts:")
for r, n in top[:8]:
    if r >= 0.5:
        print(f"    {r:7.1f}/s  {n}: {ia[n][1][-60:]}")

ctxt = (int(b["stat_lines"][-1].split()[1]) - int(a["stat_lines"][-1].split()[1])) / dt
print(f"\nContext switches {ctxt:.0f}/s")

def idle(sec):
    return {l.split()[0]: (int(l.split()[1]), int(l.split()[2])) for l in sec["idle_lines"]}
da, db = idle(a), idle(b)
for cl, cpus in (("E-cores", range(0, 4)), ("P-cores", range(4, 8))):
    wfi = sum(db[f"cpu{c}"][0] - da[f"cpu{c}"][0] for c in cpus)
    pd = sum(db[f"cpu{c}"][1] - da[f"cpu{c}"][1] for c in cpus)
    print(f"{cl}: {pd / max(1, wfi + pd) * 100:.1f} % of idle time in deep idle (CPU PD)")

wq = collections.defaultdict(lambda: [0, 0])
fn = collections.Counter()
for line in open(base + ".work"):
    m = re.search(r"function=(\S+) workqueue=(\S+) req_cpu=(-?\d+) cpu=(-?\d+)", line)
    if not m:
        continue
    function, name, cpu = m.group(1), m.group(2), int(m.group(4))
    wq[name][0 if cpu >= 0 else 1] += 1
    if "power_efficient" in name or "pwr_efficient" in name:
        fn[(name, function)] += 1
total = sum(x + y for x, y in wq.values())
print(f"\nWork items queued: {total / seconds:.1f}/s. Per workqueue (per second; to a CPU-bound"
      " pool / to an unbound one):")
for name, (bound, unbound) in sorted(wq.items(), key=lambda x: -sum(x[1]))[:15]:
    print(f"  {name:32} {(bound + unbound) / seconds:7.2f}/s   bound {bound / seconds:7.2f}"
          f"  unbound {unbound / seconds:7.2f}")
print("\nThe power-efficient workqueues' work items (per second):")
for (name, function), n in fn.most_common(15):
    print(f"  {n / seconds:7.2f}/s  {name}  {function}")
EOF
rm -f "$base.before" "$base.after" "$base.pstr"
chown -R --reference="$here" "$here/results"
cat "$base.txt"
