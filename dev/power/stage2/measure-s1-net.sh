#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Network check for Stage 2 S1 (kernel.sched_util_clamp_min_rt_default = 0): S1 also lowers the
# clocks the threaded interrupt handlers ask for, the Wi-Fi's included, so this measures what
# that does to a download and to latency. Three rounds, each with the kernel's default (1024)
# and with S1 (0) in turn (the middle round in reverse, so a drift favours neither), switched at
# runtime: a 50 MB download as fast as it goes (as the user, from Cloudflare's speed test), then
# 50 pings to the router 0.2 s apart. The value found at the start is put back at the end, also if
# the script is interrupted.
# Results: results/s1-net-<time>.txt. About 3 minutes.
# Run by the maintainer, as root, from the checkout:
#   sudo dev/power/stage2/measure-s1-net.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
key=kernel.sched_util_clamp_min_rt_default
iface=wld0
out=$here/results/s1-net-$(date +%Y%m%d-%H%M%S).txt
# Cloudflare refuses (HTTP 403) anything above 50 MB here
download=https://speed.cloudflare.com/__down?bytes=50000000

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
  echo "Start it with sudo from your own account: the download runs as you." >&2
  exit 1
fi
gateway=$(ip -4 route show default dev "$iface" | awk '{print $3; exit}')
if [[ -z $gateway ]]; then
  echo "No default route over $iface: connect to Wi-Fi first." >&2
  exit 1
fi
mkdir -p "$here/results"
orig=$(sysctl -n "$key")
trap 'sysctl -q -w "$key=$orig"' EXIT

# Throughput in Mbit/s of one download, as the user, with curl's result, so a failed download
# says why (two earlier runs asked for more than Cloudflare gives and received nothing)
fetch() {
  runuser -u "$SUDO_USER" -- curl -s -o /dev/null --max-time 120 \
    -w '%{speed_download} %{size_download} %{http_code} %{exitcode} %{errormsg}' "$download" |
    awk '{err = ""; for (i = 5; i <= NF; i++) err = err " " $i
      printf "%.1f Mbit/s (%d MB, HTTP %s, curl exit %s%s)", $1 * 8 / 1e6, $2 / 1e6, $3, $4,
        err == "" ? "" : ":" err}'
}

# Median and highest round trip of 50 pings 0.2 s apart
pings() {
  { ping -n -c 50 -i 0.2 "$gateway" 2>/dev/null || true; } |
    awk -F'time=' '/time=/ {split($2, a, " "); print a[1]}' | sort -n |
    awk '{v[NR] = $1} END {if (NR) printf "median %.2f ms, max %.2f ms (%d of 50 answered)",
      v[int((NR + 1) / 2)], v[NR], NR; else printf "no answers"}'
}

{
  echo "# $(date '+%F %T'), $key found at $orig"
  for round in 1 2 3; do
    if (( round == 2 )); then order=(0 1024); else order=(1024 0); fi
    for value in "${order[@]}"; do
      sysctl -q -w "$key=$value"
      sleep 3
      echo "round $round, $key=$value: download $(fetch); ping $(pings)"
    done
  done
} | tee "$out"
sysctl -q -w "$key=$orig"
echo "$key is back at $(sysctl -n "$key")."
chown -R --reference="$here" "$here/results"
