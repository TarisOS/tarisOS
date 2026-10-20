#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 2 X1 as taris-brcmfmac-dkms's driver sets it (L1.1 and L1.2 on once the firmware runs, off
# before every reset of the chip): after a reboot, a driver reload or a driver reset, checks that
# the patched driver is the one loaded, that the Wi-Fi chip's PCIe link has L1.1 and L1.2 on with
# clock PM and the PCI-PM substates off and the ASPM policy left at the kernel's default, both as
# the kernel has it (sysfs) and in the hardware's own registers on both ends of the link (lspci),
# and that Wi-Fi, Bluetooth and the link are fine. Read-only: it changes nothing. Writes
# results/x1-check-<time>.txt.
# Run by the maintainer, as root, from the checkout:
#   sudo dev/power/stage2/check-x1.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
wifi=0000:01:00.0
port=0000:00:00.0
link=/sys/bus/pci/devices/$wifi/link
out=$here/results/x1-check-$(date +%Y%m%d-%H%M%S).txt

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
mkdir -p "$here/results"

ok=0 bad=0
check() {
  # check LABEL EXPECTED ACTUAL
  if [[ $3 == "$2" ]]; then
    echo "  ok    $1: $3"
    ok=$(( ok + 1 ))
  else
    echo "  FAIL  $1: $3 (expected $2)"
    bad=$(( bad + 1 ))
  fi
}

# The L1 PM Substates control register and the link control's ASPM and clock PM, as lspci decodes
# them
l1ss() {
  lspci -vvv -s "$1" | grep -o 'L1SubCtl1:.*' | head -1 | awk '{print $2, $3, $4, $5}'
}
lnkctl() {
  lspci -vvv -s "$1" | awk '/LnkCtl:/ {on = 1} on {print} on && /ClockPM/ {exit}' |
    grep -oE 'ASPM [^;]*|ClockPM[+-]' | paste -sd ' '
}

{
  echo "# $(date '+%F %T'), boot $(</proc/sys/kernel/random/boot_id), up $(uptime -p)"
  echo "The kernel's view:"
  # DKMS's build (in updates/, ahead of the kernel's own), and the module running is that file:
  # its build ID among the running module's notes
  ko=$(modinfo -n brcmfmac)
  id=$(readelf -n "$ko" | awk '/Build ID:/ {print $3}')
  check "patched driver loaded" yes "$([[ $ko == */updates/* && -n $id && $(od -An -tx1 \
    /sys/module/brcmfmac/notes/.note.gnu.build-id | tr -d ' \n') == *"$id"* ]] &&
    echo yes || echo "no ($ko)")"
  check "ASPM policy" "default" \
    "$(grep -o '\[[a-z]*\]' /sys/module/pcie_aspm/parameters/policy | tr -d '[]')"
  check "Wi-Fi link (sysfs)" "l1_aspm=1 l1_1_aspm=1 l1_2_aspm=1 l1_1_pcipm=0 l1_2_pcipm=0 clkpm=0" \
    "$(for f in l1_aspm l1_1_aspm l1_2_aspm l1_1_pcipm l1_2_pcipm clkpm; do
         printf '%s=%s ' "$f" "$(<"$link/$f")"; done | sed 's/ $//')"
  echo "The hardware's registers (lspci):"
  for dev in "$port" "$wifi"; do
    check "$dev L1 substates" "PCI-PM_L1.2- PCI-PM_L1.1- ASPM_L1.2+ ASPM_L1.1+" "$(l1ss "$dev")"
    check "$dev link control" "ASPM L1 Enabled ClockPM-" "$(lnkctl "$dev")"
  done
  echo "Health:"
  check "Wi-Fi" "connected" "$(iw dev wld0 link 2>/dev/null | grep -q '^Connected to' &&
    echo connected || echo "not connected")"
  check "Bluetooth controller" "present" "$([[ -d /sys/class/bluetooth/hci0 ]] &&
    echo present || echo missing)"
  # Every boot logs "AER: enabled with IRQ"
  check "PCIe errors this boot (AER, link down)" 0 "$(journalctl -k -b -q -o cat |
    grep -iE 'AER:|PCIe Bus Error|link down' | grep -vc 'AER: enabled')"
  echo "  Wi-Fi and Bluetooth driver errors this boot (some come with every wake from sleep):"
  journalctl -k -b -q -o short-monotonic |
    grep -iE 'brcmf.*(error|fail|timeout)|bcm4377.*(error|fail)' | tail -10 | sed 's/^/    /'
  echo "$ok checks passed, $bad failed."
} 2>&1 | tee "$out"
chown -R --reference="$here" "$here/results"
