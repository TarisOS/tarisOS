#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Finds which SMC power key follows which component: loads one component at a time (one P-core,
# four P-cores, four E-cores, memory, the SSD), with idle gaps between, and samples every power
# key of taris_smc_keys once a second into results/identify-<time>.csv. Read-only: the loads
# are busy loops and reads (the SSD is read with O_DIRECT, never written); nothing is changed.
# Needs taris_smc_keys loaded (test-install.sh). Takes about 4 minutes; use the machine as
# little as possible meanwhile, on battery or AC as it is (the CSV records which).
# Run by the maintainer, as root:
#   sudo dev/power/smc-keys/identify-rails.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
power=/sys/kernel/debug/taris-smc/power
out=$here/results/identify-$(date +%Y%m%d-%H%M%S).csv
disk=/dev/nvme0n1

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ ! -r $power ]]; then
  echo "taris_smc_keys isn't loaded: run test-install.sh first." >&2
  exit 1
fi
if [[ ! -b $disk ]]; then
  echo "No $disk." >&2
  exit 1
fi

loads=()
stop_loads() {
  local pid
  for pid in "${loads[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  loads=()
}
trap stop_loads EXIT

busy() {
  local cpu
  for cpu in "$@"; do
    taskset -c "$cpu" bash -c 'while :; do :; done' &
    loads+=($!)
  done
}

# 16 MiB blocks are larger than either cluster's L2 cache, so the copy goes through DRAM
memory() {
  taskset -c 4 dd if=/dev/zero of=/dev/null bs=16M count=1000000 status=none &
  loads+=($!)
}

ssd() {
  taskset -c 0 dd if="$disk" of=/dev/null bs=4M iflag=direct count=1000000 status=none &
  loads+=($!)
}

keys=$(awk '!/^#/ {printf ",%s", $1}' "$power")
echo "t,phase,ac,freq_e_khz,freq_p_khz$keys" > "$out"
start=$(date +%s.%N)

sample() {
  local phase=$1 seconds=$2 i
  echo "  $phase, ${seconds} s"
  for (( i = 0; i < seconds; i++ )); do
    printf '%.1f,%s,%s,%s,%s%s\n' \
      "$(awk -v a="$(date +%s.%N)" -v b="$start" 'BEGIN {print a - b}')" "$phase" \
      "$(</sys/class/power_supply/macsmc-ac/online)" \
      "$(</sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)" \
      "$(</sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq)" \
      "$(awk '!/^#/ {printf ",%s", $2}' "$power")" >> "$out"
    sleep 1
  done
}

echo "Sampling into $out:"
sample idle 30
busy 4; sample p1 20; stop_loads; sample idle 15
busy 4 5 6 7; sample p4 20; stop_loads; sample idle 15
busy 0 1 2 3; sample e4 20; stop_loads; sample idle 15
memory; sample memory 20; stop_loads; sample idle 15
ssd; sample ssd 20; stop_loads; sample idle 15

chown --reference="$here" "$out"
echo "Done. Nothing was changed; the module stays loaded until test-revert.sh."
