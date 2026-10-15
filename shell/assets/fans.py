#!/usr/bin/env python3
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

"""Reads and sets the fans of an Apple Silicon Mac through the kernel's
macsmc_hwmon driver.

  fans.py read            print the fans and temperature sensors as JSON
  fans.py watch SECONDS   print them as a JSON line every SECONDS, until stopped
                          (one process for the shell to read, rather than one per reading)
  fans.py set N RPM       run fan N at RPM (between its min and max)
  fans.py set N auto      hand fan N back to the SMC

Setting a speed needs the driver loaded with macsmc_hwmon.fan_control=1 (a
kernel option; fanN_target is read-only without it) and write access to
fanN_target, which packaging/90-taris-fans.rules gives the wheel group.
"""

import glob
import json
import os
import sys
import time

SMC_NAME = "macsmc_hwmon"
PARAM = "/sys/module/macsmc_hwmon/parameters/fan_control"


def read(path, default=None):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def smc_hwmon():
    for path in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        if read(path + "/name") == SMC_NAME:
            return path
    return None


def number(path):
    try:
        return int(read(path, ""))
    except ValueError:
        return None


def fans(hwmon):
    out = []
    if not hwmon:
        return out
    for path in sorted(glob.glob(hwmon + "/fan*_input")):
        n = os.path.basename(path)[3:].split("_")[0]
        base = hwmon + "/fan" + n
        target = base + "_target"
        out.append({
            "n": int(n),
            "label": read(base + "_label", "Fan " + n),
            "rpm": number(base + "_input"),
            "min": number(base + "_min"),
            "max": number(base + "_max"),
            "target": number(target),
            "writable": os.access(target, os.W_OK),
        })
    return out


# Every temperature any hwmon device reports. The id is the device's own
# name plus the channel, which stays the same across boots (hwmonN doesn't).
def temps():
    out = []
    for hwmon in sorted(glob.glob("/sys/class/hwmon/hwmon*"), key=lambda p: int(p.rsplit("hwmon", 1)[1])):
        name = read(hwmon + "/name", "")
        # The speaker amps' sensors never change.
        if name == "tas2770":
            continue
        device = os.path.basename(os.path.realpath(hwmon + "/device"))
        for path in sorted(glob.glob(hwmon + "/temp*_input")):
            channel = os.path.basename(path).split("_")[0]
            value = number(path)
            if value is None:
                continue
            label = read(hwmon + "/" + channel + "_label")
            if not label or label == "temp":
                label = {"macsmc_battery": "Battery"}.get(name, name)
            out.append({"id": device + "/" + channel, "label": label, "celsius": round(value / 1000, 1)})
    return out


def snapshot():
    hwmon = smc_hwmon()
    return json.dumps({
        "present": hwmon is not None,
        "control": read(PARAM) == "Y",
        "fans": fans(hwmon),
        "temps": temps(),
    })


def cmd_read():
    print(snapshot())


def cmd_watch(seconds):
    try:
        while True:
            print(snapshot(), flush=True)
            time.sleep(seconds)
    except (BrokenPipeError, KeyboardInterrupt):
        # The reader went away: nothing left to flush to
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())


def cmd_set(n, value):
    hwmon = smc_hwmon()
    if not hwmon:
        sys.exit("fans: no " + SMC_NAME + " device")
    target = hwmon + "/fan" + str(int(n)) + "_target"
    rpm = 0 if value == "auto" else int(value)
    try:
        with open(target, "w") as f:
            f.write(str(rpm))
    except OSError as e:
        sys.exit("fans: " + target + ": " + e.strerror)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["read"]:
        cmd_read()
    elif len(args) == 2 and args[0] == "watch":
        cmd_watch(max(0.5, float(args[1])))
    elif len(args) == 3 and args[0] == "set":
        cmd_set(args[1], args[2])
    else:
        sys.exit(__doc__.strip())
