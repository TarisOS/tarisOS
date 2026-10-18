#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Loads the draft read-only SMC key reader (taris_smc_keys.ko, built here with make) and saves
# its key list and the power keys' values into results/ next to this script. Nothing is written
# to the SMC and nothing on the system is replaced; test-revert.sh unloads the module.
# Run by the maintainer, as root:
#   sudo dev/power/smc-keys/test-install.sh [KEY,KEY,...]
# KEY,KEY,...: optional float keys to expose in /sys/kernel/taris-smc/sample (at most 16)

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
ko=$here/taris_smc_keys.ko
dbg=/sys/kernel/debug/taris-smc
out=$here/results

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 $*" >&2
  exit 1
fi
if [[ -d /sys/module/taris_smc_keys ]]; then
  echo "taris_smc_keys is already loaded: run test-revert.sh first." >&2
  exit 1
fi
if [[ ! -f $ko ]]; then
  echo "No $ko: run make in $here first (as your own user)." >&2
  exit 1
fi
vermagic=$(modinfo -F vermagic "$ko")
if [[ ${vermagic%% *} != "$(uname -r)" ]]; then
  echo "The module was built for ${vermagic%% *}, this kernel is $(uname -r): run make again." >&2
  exit 1
fi

if [[ -n ${1:-} ]]; then
  insmod "$ko" "sample=$1"
else
  insmod "$ko"
fi
echo "Loaded. Kernel log:"
dmesg | grep 'taris_smc_keys:' | tail -n 5

mkdir -p "$out"
stamp=$(date +%Y%m%d-%H%M%S)
cp "$dbg/keys" "$out/keys-$stamp.txt"
# Read PSTR from the existing hwmon driver right next to our own read, as a cross-check. Its
# number can change between boots, so it's found by name.
hwmon=
for h in /sys/class/hwmon/hwmon*; do
  if [[ $(<"$h/name") == "macsmc_hwmon" && -r $h/power1_input ]]; then
    hwmon=$(awk '{printf "%.6f", $1/1e6}' "$h/power1_input")
  fi
done
cp "$dbg/power" "$out/power-$stamp.txt"
chown -R --reference="$here" "$out"

echo
echo "Saved $out/keys-$stamp.txt ($(grep -vc '^#' "$out/keys-$stamp.txt") keys)"
echo "Saved $out/power-$stamp.txt ($(grep -vc '^#' "$out/power-$stamp.txt") power keys)"
echo
echo "Cross-check, total system power (PSTR), read moments apart:"
echo "  hwmon power1_input: ${hwmon:-unavailable} W"
echo "  taris_smc_keys:     $(awk '$1 == "PSTR" {print $2}' "$out/power-$stamp.txt") W"
if [[ -n ${1:-} ]]; then
  echo
  echo "/sys/kernel/taris-smc/sample:"
  cat /sys/kernel/taris-smc/sample
fi
echo
echo "The module stays loaded until test-revert.sh. Nothing else changed."
