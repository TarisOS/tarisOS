#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# A/B measurement of Stage 2 S4: how long the Wi-Fi radio stays awake after traffic (2000 ms, the
# driver's choice today, against 500 and 200 ms), set with packaging/pkgbuilds/taris-hardware/
# wifi-power-timeout. After 20 s to settle: 30 s idle, 30 s of a 4 MB/s download, 30 s idle, to
# see which SMC key follows the Wi-Fi. Then each value three times, in the orders 2000/500/200,
# 200/500/2000, 2000/500/200 (so a slow drift favours no value): 10 s to settle, then 90 s with
# only the desktop's own traffic for battery power (coulomb counter) and every SMC power key.
# Every block records the brightness at its start and end; a block in which it changed is left
# out of the summary, since the backlight alone moves the total by watts.
# The driver's choice is put back at the end, also if interrupted.
# Results: results/s4-<time>.csv and results/s4-<time>.txt. Needs taris_smc_keys loaded
# (dev/power/smc-keys/test-install.sh), Wi-Fi connected with power saving on, and the Mac on
# battery. Takes about 17 minutes. Set the brightness first and leave the Mac alone meanwhile.
# Run by the maintainer, as root, from the checkout:
#   sudo dev/power/stage2/measure-s4.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
helper=$(cd "$here/../../.." && pwd)/packaging/pkgbuilds/taris-hardware/wifi-power-timeout
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
bl=/sys/class/backlight/apple-panel-bl/actual_brightness
iface=wld0
stamp=$(date +%Y%m%d-%H%M%S)
out=$here/results/s4-$stamp.csv
summary=$here/results/s4-$stamp.txt
# Cloudflare refuses (HTTP 403) anything above 50 MB here; the download phase repeats it
download=https://speed.cloudflare.com/__down?bytes=50000000

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ ! -r $power ]]; then
  echo "taris_smc_keys isn't loaded: run dev/power/smc-keys/test-install.sh first." >&2
  exit 1
fi
if [[ $(iw dev "$iface" get power_save 2>/dev/null) != "Power save: on" ]]; then
  echo "Power saving isn't on for $iface: the timeout only matters with it on." >&2
  exit 1
fi
if [[ -z $(ip -4 route show default dev "$iface") ]]; then
  echo "No default route over $iface: connect to Wi-Fi first." >&2
  exit 1
fi
mkdir -p "$here/results"

restore() {
  "$helper" "$iface" default >/dev/null || echo "Couldn't put the driver's choice back." >&2
}
trap restore EXIT

keys=$(awk '!/^#/ {printf ",%s", $1}' "$power")
echo "phase,value_ms,round,ac,brightness_start,brightness_end,battery_w$keys" > "$out"

# Mean of every power key over N seconds, comma-separated in the file's key order
sample_keys() {
  local n=$1 i
  for (( i = 0; i < n; i++ )); do
    awk '!/^#/ {printf "%s ", $2} END {print ""}' "$power"
    sleep 1
  done | awk '{for (j = 1; j <= NF; j++) s[j] += $j; n = NF} END {
    for (j = 1; j <= n; j++) printf ",%.4f", s[j] / NR}'
}

# One measured block: the brightness at both ends, battery W from the coulomb counter (mA*s, as
# macsmc-power passes SMC BAAC on), the keys' means; appended as a CSV line after LABEL
block() {
  local label=$1 seconds=$2 b0 b1 q0 q1 v0 v1 t0 t1 vals bw ac
  b0=$(<"$bl")
  q0=$(<"$bat/charge_counter"); v0=$(<"$bat/voltage_now"); t0=${EPOCHREALTIME/./}
  vals=$(sample_keys "$seconds")
  q1=$(<"$bat/charge_counter"); v1=$(<"$bat/voltage_now"); t1=${EPOCHREALTIME/./}
  b1=$(<"$bl")
  ac=$(</sys/class/power_supply/macsmc-ac/online)
  bw=
  if [[ $ac == "0" ]]; then
    bw=$(awk -v q0="$q0" -v q1="$q1" -v v0="$v0" -v v1="$v1" -v t0="$t0" -v t1="$t1" \
      'BEGIN {printf "%.4f", (q0 - q1) / 1000 * (v0 + v1) / 2e6 / ((t1 - t0) / 1e6)}')
  fi
  echo "$label,$ac,$b0,$b1,$bw$vals" >> "$out"
  echo "  ${label//,/ }: battery ${bw:-n/a} W, brightness $b0 -> $b1"
}

# The speed-test downloads still running: only processes named curl, and of those only the ones
# fetching that URL (pkill -f would also match any other command line containing it)
stop_downloads() {
  local p
  for p in $(pgrep -x curl); do
    if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'speed\.cloudflare\.com/__down'; then
      kill "$p" 2>/dev/null || true
    fi
  done
}

echo "Measuring into $out:"
"$helper" "$iface" default >/dev/null
sleep 20

# Which key follows the Wi-Fi: idle, a rate-limited download, idle again
block "idle,,0" 30
# curl reports what each download received, so one that didn't happen can't pass as one; 50 MB
# at 4 MB/s lasts 12.5 s, so they repeat until the phase ends (the loop is killed then)
(
  while :; do
    curl -s -o /dev/null --limit-rate 4M --max-time 40 \
      -w '%{size_download} bytes, HTTP %{http_code}, curl exit %{exitcode} %{errormsg}\n' \
      "$download"
  done
) > "$here/results/s4-$stamp-download.txt" 2>&1 &
dl=$!
sleep 3
block "download,,0" 30
# The loop first, so it starts no new download, then the download it left running
kill "$dl" 2>/dev/null || true
stop_downloads
wait "$dl" 2>/dev/null || true
received=$(tr '\n' ';' < "$here/results/s4-$stamp-download.txt" 2>/dev/null || true)
echo "  downloads received: ${received:-nothing}"
sleep 5
block "idle,,1" 30

for round in 1 2 3; do
  if (( round == 2 )); then order=(200 500 2000); else order=(2000 500 200); fi
  for ms in "${order[@]}"; do
    "$helper" "$iface" "$ms" >/dev/null
    sleep 10
    block "timeout,$ms,$round" 90
  done
done
restore
echo "Wi-Fi timeout back to the driver's choice."

python3 -I - "$out" > "$summary" <<'EOF'
import csv, statistics as st, sys
rows = list(csv.DictReader(open(sys.argv[1])))
keys = [k for k in rows[0] if k[:1] == "P"]
steady = [r for r in rows if r["brightness_start"] == r["brightness_end"]]
moved = [r for r in rows if r not in steady]

def mean(rs, k):
    v = [float(r[k]) for r in rs if r[k] not in ("", None)]
    return st.mean(v) if v else float("nan")

print("Blocks left out because the brightness changed during them:",
      ", ".join(f"{r['phase']} {r['value_ms']} r{r['round']}" for r in moved) or "none")

idle = [r for r in steady if r["phase"] == "idle"]
dl = [r for r in steady if r["phase"] == "download"]
# The keys that followed the Wi-Fi timeout on 2026-10-18 (PW3C, and PO3R above it), always shown;
# others the download finds are added
watch = [k for k in ("PW3C", "PO3R") if k in keys]
# The CPU clusters and the totals follow everything, so they don't tell the Wi-Fi apart
general = ("PP0", "PPb", "PP7", "PST", "PPB", "Pb0", "PMV", "PPM", "PHP")
if idle and dl:
    print("\nKeys that rose with the download (W, mean of the idles -> download):")
    for k in keys:
        d = mean(dl, k) - mean(idle, k)
        if d > 0.02:
            print(f"  {k:5} {mean(idle, k):7.3f} -> {mean(dl, k):7.3f}  ({d:+.3f})")
            if k not in watch and not k.startswith(general):
                watch.append(k)
    print(f"  battery {mean(idle, 'battery_w'):.3f} -> {mean(dl, 'battery_w'):.3f}")
else:
    print("\nNo steady idle and download blocks: no Wi-Fi key identified.")

print("\nPer timeout, mean of the steady rounds (battery W; PSTR; the Wi-Fi keys and any other")
print("key that followed the download, other than the CPU and totals):")
hdr = "  %-7s %6s %8s %7s " % ("timeout", "rounds", "battery", "PSTR")
print(hdr + " ".join("%7s" % k for k in watch))
for ms in ("2000", "500", "200"):
    r = [x for x in steady if x["phase"] == "timeout" and x["value_ms"] == ms]
    if not r:
        print("  %-7s no steady rounds" % (ms + " ms"))
        continue
    line = "  %-7s %6d %8.3f %7.3f " % (ms + " ms", len(r), mean(r, "battery_w"), mean(r, "PSTR"))
    print(line + " ".join("%7.3f" % mean(r, k) for k in watch))
# Paired: within each round whose three blocks share one brightness, each value against that
# round's 2000 ms block, so a brightness (or anything else) that differs between rounds cancels
print("\nPaired, per round at one brightness (battery W against the round's 2000 ms):")
deltas = {"500": [], "200": []}
for rnd in sorted({x["round"] for x in rows if x["phase"] == "timeout"}):
    r = {x["value_ms"]: x for x in rows if x["phase"] == "timeout" and x["round"] == rnd}
    ok = len(r) == 3 and all(x in steady and x["battery_w"] for x in r.values()) and \
        len({x["brightness_start"] for x in r.values()}) == 1
    if not ok:
        print(f"  round {rnd}: left out (brightness changed, or a reading is missing)")
        continue
    base = float(r["2000"]["battery_w"])
    for ms in ("500", "200"):
        deltas[ms].append(float(r[ms]["battery_w"]) - base)
    print(f"  round {rnd} (brightness {r['2000']['brightness_start']}): " + ", ".join(
        f"{ms} ms {float(r[ms]['battery_w']) - base:+.3f}" for ms in ("500", "200")))
for ms in ("500", "200"):
    d = deltas[ms]
    if d:
        spread = f", rounds from {min(d):+.3f} to {max(d):+.3f}" if len(d) > 1 else ""
        print(f"  {ms} ms against 2000 ms: mean {st.mean(d):+.3f} W over {len(d)} rounds{spread}")

print("\nRound by round (battery W, brightness), to judge the noise:")
for x in rows:
    if x["phase"] == "timeout":
        flag = "" if x in steady else "  (left out)"
        print(f"  round {x['round']} {x['value_ms']:>4} ms: {x['battery_w'] or 'n/a'}"
              f"  brightness {x['brightness_start']}->{x['brightness_end']}{flag}")
EOF
chown -R --reference="$here" "$here/results"
cat "$summary"
