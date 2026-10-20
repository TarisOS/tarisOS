#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 2 X1: the Wi-Fi/Bluetooth chip's PCIe link with its L1.1 and L1.2 substates on (ASPM),
# against the link as found (L1 only). Under the kernel's "default" ASPM policy only the link's
# boot-time states apply (drivers/pci/pcie/aspm.c policy_to_aspm_state), so writing l1_2_aspm alone
# changes nothing: the substates need the "powersupersave" policy, which would also switch on clock
# power management (policy_to_clkpm_state). So clock PM and the PCI-PM substates are blocked on the
# link first (clkpm, l1_1_pcipm, l1_2_pcipm = 0), then the policy is set, then l1_1_aspm and
# l1_2_aspm are written 1: writing 0 to them blocks those states until the next boot
# (aspm_attr_store_common sets aspm_disable), which an earlier version of this script did on its
# way out, and 1 lifts that block. The link's state is checked before anything is measured. This
# Mac has only this PCIe link (the Wi-Fi's root port). Never written 0 here.
# Back as found: the "default" policy again (the link's boot-time L1 only); the three blocks stay
# until the next boot (those features were off anyway). The Apple PCIe controller's driver handles
# no clock request (CLKREQ#), which L1.2 relies on, so the link might not wake: before every block
# a health check
# (Wi-Fi associated, the router answering pings, the Bluetooth controller there, no new PCIe,
# Wi-Fi or Bluetooth errors in the kernel log); if it fails, the link goes back as found at once
# and the run stops. Three rounds in alternating order, 60 s of idle each: battery power (coulomb
# counter), the Wi-Fi's SMC keys (PW3C, PO3R), PSTR. The link is put back as found at the end, also
# if interrupted; nothing outlasts a reboot.
# Results: results/x1-<time>.txt. Needs taris_smc_keys loaded (dev/power/smc-keys/
# test-install.sh), Wi-Fi connected, the Mac on battery. About 5 minutes; leave it alone.
# Run by the maintainer, as root, from the checkout:
#   sudo dev/power/stage2/measure-x1.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
link=/sys/bus/pci/devices/0000:01:00.0/link
policy=/sys/module/pcie_aspm/parameters/policy
power=/sys/kernel/debug/taris-smc/power
bat=/sys/class/power_supply/macsmc-battery
iface=wld0
out=$here/results/x1-$(date +%Y%m%d-%H%M%S).txt

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ ! -r $power ]]; then
  echo "taris_smc_keys isn't loaded: run dev/power/smc-keys/test-install.sh first." >&2
  exit 1
fi
if [[ ! -w $link/l1_2_aspm ]]; then
  echo "No L1.2 control for the Wi-Fi link ($link)." >&2
  exit 1
fi
if [[ $(</sys/class/power_supply/macsmc-ac/online) != "0" ]]; then
  echo "Unplug the charger first: the energy comes from the battery's counter." >&2
  exit 1
fi
gateway=$(ip -4 route show default dev "$iface" | awk '{print $3; exit}')
if [[ -z $gateway ]]; then
  echo "No default route over $iface: connect to Wi-Fi first." >&2
  exit 1
fi
mkdir -p "$here/results"
since=$(date '+%Y-%m-%d %H:%M:%S')
found_l11=$(<"$link/l1_1_aspm")
found_l12=$(<"$link/l1_2_aspm")
# With taris-brcmfmac-dkms's driver they're on from boot, and there'd be nothing to compare
if [[ $found_l11 == "1" || $found_l12 == "1" ]]; then
  echo "L1.1/L1.2 are on already (l1_1=$found_l11 l1_2=$found_l12): this compares the link" \
    "without them (the kernel's own driver, no taris-brcmfmac-dkms) against with them." >&2
  exit 1
fi
if ! grep -q '\[default\]' "$policy"; then
  echo "The ASPM policy isn't the default ($(<"$policy")): this compares against the default." >&2
  exit 1
fi

restore() {
  echo default > "$policy" 2>/dev/null || true
}

state() {
  echo "l1_1=$(<"$link/l1_1_aspm") l1_2=$(<"$link/l1_2_aspm") clkpm=$(<"$link/clkpm")"
}
trap 'restore; chown -R --reference="$here" "$here/results" 2>/dev/null || true' EXIT

# The substates on (and clock PM off), or the link as found; either way checked afterwards. Each
# write is checked itself: set -e doesn't apply inside a function called from an if.
apply() {
  if [[ $1 == "l1ss" ]]; then
    echo 0 > "$link/clkpm" || return 1
    echo 0 > "$link/l1_1_pcipm" || return 1
    echo 0 > "$link/l1_2_pcipm" || return 1
    echo powersupersave > "$policy" || return 1
    echo 1 > "$link/l1_1_aspm" || return 1
    echo 1 > "$link/l1_2_aspm" || return 1
    [[ $(state) == "l1_1=1 l1_2=1 clkpm=0" ]]
  else
    echo default > "$policy" || return 1
    [[ $(state) == "l1_1=$found_l11 l1_2=$found_l12 clkpm=0" ]]
  fi
}

# Wi-Fi associated, 5 of 5 pings answered, the Bluetooth controller present, no new errors
healthy() {
  local why=
  if ! iw dev "$iface" link 2>/dev/null | grep -q '^Connected to'; then
    why+=" wifi-not-associated"
  fi
  if [[ $(ping -n -c 5 -i 0.2 -W 1 "$gateway" 2>/dev/null | grep -c 'time=') != 5 ]]; then
    why+=" pings-lost"
  fi
  if [[ ! -d /sys/class/bluetooth/hci0 ]]; then why+=" no-bluetooth"; fi
  if journalctl -k -q --since "$since" --no-pager -o cat 2>/dev/null |
      grep -qiE 'brcmf.*(error|fail|timeout)|AER|pcie.*(error|link down)|bcm4377.*(error|fail)'
  then
    why+=" kernel-errors"
  fi
  echo "${why# }"
}

block() {
  local q0 v0 t0 q1 v1 t1 i
  q0=$(<"$bat/charge_counter"); v0=$(<"$bat/voltage_now"); t0=${EPOCHREALTIME/./}
  for (( i = 0; i < 60; i++ )); do
    awk '$1 ~ /^(PSTR|PW3C|PO3R)$/ {printf "%s ", $2} END {print ""}' "$power"
    sleep 1
  done | awk -v q0="$q0" -v v0="$v0" -v t0="$t0" -v bat="$bat" '
    {for (j = 1; j <= 3; j++) s[j] += $j; n++}
    END {
      getline q1 < (bat "/charge_counter"); getline v1 < (bat "/voltage_now")
      "date +%s%6N" | getline t1
      w = (q0 - q1) / 1000 * (v0 + v1) / 2e6 / ((t1 - t0) / 1e6)
      printf "battery %.3f W  PO3R %.3f  PSTR %.3f  PW3C %.3f", w, s[1] / n, s[2] / n, s[3] / n
    }'
}

{
  echo "# X1 $(date '+%F %T'): link as found l1_1_aspm=$found_l11 l1_2_aspm=$found_l12"
  echo "# (the SMC keys are listed in the power file's order: PO3R, PSTR, PW3C)"
  for round in 1 2 3; do
    if (( round == 2 )); then order=(l1ss found); else order=(found l1ss); fi
    for setting in "${order[@]}"; do
      if ! apply "$setting"; then
        restore
        echo "round $round $setting: the link didn't take the setting ($(state)); stopping."
        exit 1
      fi
      sleep 10
      why=$(healthy)
      if [[ -n $why ]]; then
        restore
        echo "round $round $setting: UNHEALTHY ($why): the link is back as found; stopping."
        journalctl -k -q --since "$since" --no-pager -o short-monotonic 2>/dev/null |
          grep -iE 'brcmf|pcie|AER|bcm4377|hci' | tail -20
        exit 1
      fi
      echo "round $round $setting ($(state)): $(block)"
    done
  done
  restore
  echo "Link back as found: $(state), policy $(<"$policy")."
  echo "Kernel messages about the link, Wi-Fi or Bluetooth during the run:"
  journalctl -k -q --since "$since" --no-pager -o short-monotonic 2>/dev/null |
    grep -iE 'brcmf|pcie|AER|bcm4377|hci' || echo "  none"
} 2>&1 | tee "$out"
