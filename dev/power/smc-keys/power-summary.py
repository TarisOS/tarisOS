#!/usr/bin/python3 -I
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Turns power-log.sh's logs into the figures for the Stage 1 baseline: battery energy and average
# power on battery (from the battery's coulomb counter), the projected time on a full charge, the
# SMC keys' averages, power by brightness and by focused app, CPU clock and idle behaviour, disk
# and Wi-Fi traffic, and the log's own cost. Only intervals between two rows on battery, without
# a suspend and without a gap, count; the rest is listed as left out.
# Run by anyone, on one or more logs:
#   dev/power/smc-keys/power-summary.py results/powerlog-*.csv

import csv
import re
import sys
from collections import defaultdict

USER_HZ = 100  # getconf CLK_TCK on this machine


def load(path):
    """Header comments, then the rows as dicts (strings)."""
    comments, lines = [], []
    with open(path, newline="") as f:
        for line in f:
            (comments if line.startswith("#") else lines).append(line)
    return comments, list(csv.DictReader(lines))


def num(row, key):
    v = row.get(key, "")
    return float(v) if v not in ("", None) else None


def intervals(path):
    """Consecutive row pairs of one log, each marked usable or with the reason it isn't."""
    comments, rows = load(path)
    m = re.search(r"every (\d+) s", "".join(comments))
    step = int(m.group(1)) if m else 30
    m = re.search(r"energy_full (\d+) uWh", "".join(comments))
    full_wh = int(m.group(1)) / 1e6 if m else None
    m = re.search(r"brightness max (\d+)", "".join(comments))
    blmax = int(m.group(1)) if m else None
    out = []
    for a, b in zip(rows, rows[1:]):
        # Interval lengths from /proc/uptime: it only moves forward and counts suspends, while
        # the wall clock can jump (NTP, Tor's time sync)
        dt = float(b["uptime"]) - float(a["uptime"])
        if a["suspends"] != b["suspends"]:
            why = "suspend"
        elif not 0.5 * step <= dt <= 2.5 * step:
            why = "gap"
        elif a["ac"] != "0" or b["ac"] != "0":
            why = "on AC"
        elif a["status"] != "Discharging" or b["status"] != "Discharging":
            why = "not discharging"
        elif num(a, "charge_counter") is None or num(b, "charge_counter") is None:
            why = "no battery reading"
        else:
            why = None
        out.append((a, b, dt, why))
    return out, step, full_wh, blmax


def duration(s):
    """Seconds as h:mm:ss."""
    s = round(s)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}"


def mean2(a, b, key):
    va, vb = num(a, key), num(b, key)
    if va is None or vb is None:
        return None
    return (va + vb) / 2


def delta(a, b, key):
    va, vb = num(a, key), num(b, key)
    if va is None or vb is None:
        return None
    return vb - va


def main(paths):
    usable, left_out = [], defaultdict(float)
    full_wh = blmax = None
    keys, tis_e, tis_p = [], [], []
    for path in paths:
        ivs, step, fw, bm = intervals(path)
        full_wh = fw or full_wh
        blmax = bm or blmax
        for a, b, dt, why in ivs:
            if why:
                left_out[why] += dt
            else:
                usable.append((a, b, dt))
        if ivs:
            names = list(ivs[0][0].keys())
            keys = keys or [k for k in names if k.startswith("smc_")]
            tis_e = tis_e or [k for k in names if k.startswith("tis_e_")]
            tis_p = tis_p or [k for k in names if k.startswith("tis_p_")]
    if not usable:
        print("No usable intervals on battery.")
        for why, s in sorted(left_out.items()):
            print(f"  left out: {why}, {duration(s)}")
        return

    # Battery: the coulomb counter is in mA*s; times the mean voltage of the interval, joules
    total_s = sum(dt for _, _, dt in usable)
    joules = 0.0
    counted_mas = current_mas = power_now_j = checked_s = 0.0
    per_iv = []
    for a, b, dt in usable:
        dq_c = -delta(a, b, "charge_counter") / 1000
        v = mean2(a, b, "voltage_uv") / 1e6
        j = dq_c * v
        joules += j
        per_iv.append((a, b, dt, j / dt))
        i, p = mean2(a, b, "current_ua"), mean2(a, b, "power_uw")
        if i is not None and p is not None:
            counted_mas += -delta(a, b, "charge_counter")
            current_mas += -i / 1000 * dt
            power_now_j += -p / 1e6 * dt
            checked_s += dt
    avg_w = joules / total_s

    print(f"On battery, usable: {duration(total_s)} in {len(usable)} intervals")
    for why, s in sorted(left_out.items()):
        print(f"  left out: {why}, {duration(s)}")
    print(f"Energy from the battery: {joules / 3600:.2f} Wh, average {avg_w:.3f} W")
    if checked_s:
        print(f"  cross-checks: power_now average {power_now_j / checked_s:.3f} W; "
              f"charge counter / current x time = {counted_mas / current_mas:.4f} (1.0 = mA*s)")
    first, last = usable[0][0], usable[-1][1]
    if full_wh:
        print(f"Projected on a full charge ({full_wh:.1f} Wh now, battery health included): "
              f"{full_wh / avg_w:.1f} h at this average")
    print(f"Charge: {first['capacity']} % to {last['capacity']} %")

    # SMC keys: time-weighted means of the samples at both ends of each interval
    print("\nSMC keys (time-weighted means of the samples, W):")
    for k in keys:
        acc = [(mean2(a, b, k), dt) for a, b, dt in usable]
        acc = [(v, dt) for v, dt in acc if v is not None]
        if acc:
            t = sum(dt for _, dt in acc)
            print(f"  {k[4:]:5} {sum(v * dt for v, dt in acc) / t:7.3f}"
                  f"   ({t / total_s * 100:.0f} % of the time sampled)")

    # Brightness bands and focused apps, by the battery power of each interval
    def by(label, groups):
        print(f"\n{label}:")
        for name, ivs in sorted(groups.items(), key=lambda g: -sum(dt for _, dt in g[1])):
            t = sum(dt for _, dt in ivs)
            w = sum(p * dt for p, dt in ivs) / t
            print(f"  {name:32} {t / total_s * 100:5.1f} % of the time   {w:6.3f} W")

    blmax = blmax or 509
    bands = defaultdict(list)
    apps = defaultdict(list)
    for a, b, dt, p in per_iv:
        br = mean2(a, b, "brightness") or 0
        q = min(3, int(br / blmax * 4))
        bands[f"brightness {q * 25}-{q * 25 + 25} %"].append((p, dt))
        apps[f"{a['window'] or '(none)'} [{a['workspace'] or '-'}]"].append((p, dt))
    by("By brightness", bands)
    by("By the app focused at the start of the interval (attribution is rough)", apps)

    # Audio outputs
    spk = sum(dt for a, b, dt in usable if "RUNNING" in (a["audio_speakers"], b["audio_speakers"]))
    jack = sum(dt for a, b, dt in usable if "RUNNING" in (a["audio_jack"], b["audio_jack"]))
    print(f"\nAudio playing: speakers {spk / total_s * 100:.1f} % of the time, "
          f"headphone jack {jack / total_s * 100:.1f} % (Bluetooth not seen)")

    # CPU from the kernel's running totals, over the usable intervals only
    def total(key):
        return sum(delta(a, b, key) or 0 for a, b, _ in usable)

    busy_keys = ["ticks_user", "ticks_nice", "ticks_system", "ticks_irq", "ticks_softirq"]
    busy = sum(total(k) for k in busy_keys)
    allt = busy + total("ticks_idle") + total("ticks_iowait")
    print(f"\nCPU busy {busy / allt * 100:.2f} % of 8 cores; per second: "
          f"{total('ctxt') / total_s:.0f} context switches, {total('intr') / total_s:.0f} "
          f"interrupts, {total('forks') / total_s:.2f} new processes")
    for label, cols in (("E-cluster", tis_e), ("P-cluster", tis_p)):
        d = {c: total(c) for c in cols}
        s = sum(d.values())
        if s:
            steps = ", ".join(f"{int(c.split('_')[2]) // 1000} {v / s * 100:.1f}%"
                              for c, v in d.items() if v / s >= 0.001)
            print(f"  {label} clock (MHz, share of time): {steps}")
    for label, p in (("E-cores", "idle_e"), ("P-cores", "idle_p")):
        wt, wn = total(f"{p}_wfi_us"), total(f"{p}_wfi_n")
        pt, pn = total(f"{p}_pd_us"), total(f"{p}_pd_n")
        if wt + pt:
            print(f"  {label} idle: {pt / (wt + pt) * 100:.1f} % in CPU PD; mean stretch "
                  f"WFI {wt / max(wn, 1) / 1000:.2f} ms, CPU PD {pt / max(pn, 1) / 1000:.2f} ms")

    hours = total_s / 3600
    print(f"\nDisk: {total('disk_read') * 512 / 1e6 / hours:.1f} MB read, "
          f"{total('disk_written') * 512 / 1e6 / hours:.1f} MB written per hour")
    print(f"Wi-Fi: {total('wifi_rx') / 1e6 / hours:.1f} MB in, "
          f"{total('wifi_tx') / 1e6 / hours:.1f} MB out per hour")
    print(f"The log's own CPU time: {total('self_cpu_ticks') / USER_HZ / hours:.2f} s per hour")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: power-summary.py LOG.csv [LOG.csv ...]", file=sys.stderr)
        sys.exit(1)
    main(sys.argv[1:])
