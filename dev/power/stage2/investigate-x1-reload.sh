#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 2 X1: the Wi-Fi driver's reload under different L1.1/L1.2 conditions, tested on the chip one
# at a time, with the link's registers and the kernel log recorded at every step. (Its run and
# repeat-x1-reload.sh's showed reloads fail now and then with or without L1.1/L1.2: not X1's doing.)
#   A: a reload as things are (L1.1/L1.2 on until the driver unloads). Expected to fail.
#   Recovery: the driver unloaded, a PCIe function-level reset (FLR) of the Wi-Fi function, the
#     driver loaded: does the firmware start, and is Bluetooth (the chip's other function) still
#     up? If not, a reset of the whole link (the root port's secondary bus reset, Bluetooth's
#     driver unloaded around it).
#   B: if the FLR worked, A and the FLR once more, to see both repeat.
#   C1, C2: L1.1/L1.2 blocked through sysfs right before the unload, then the reload.
#   D: only if C fails (after a recovery): blocked 6 s before the unload, as the one reload that
#     worked.
# A trial works when the driver is bound and the Wi-Fi interface is there within 25 s, and fails
# when the kernel logs "Dongle setup failed". When no recovery works it stops: then reboot.
# It ends with L1.1/L1.2 unblocked and the driver loaded.
# Results: results/x1-investigate-<time>/ (summary.txt, a snapshot per step, the kernel log per
# trial). A few minutes; Wi-Fi drops and comes back several times.
# Run by the maintainer, as root, from anywhere:
#   sudo ~/Projects/tarisOS/dev/power/stage2/investigate-x1-reload.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dev=/sys/bus/pci/devices/0000:01:00.0
port=/sys/bus/pci/devices/0000:00:00.0
link=$dev/link
out=$here/results/x1-investigate-$(date +%Y%m%d-%H%M%S)
summary=$out/summary.txt

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ $(basename "$(readlink "$dev/driver" 2>/dev/null)") != "brcmfmac" ]] ||
  ! compgen -G "$dev/net/*" >/dev/null; then
  echo "The Wi-Fi driver isn't up on $dev: start from working Wi-Fi (reboot first)." >&2
  exit 1
fi
if [[ $(<"$link/l1_2_aspm") != "1" ]]; then
  echo "L1.2 isn't on ($(<"$link/l1_2_aspm")): this needs the state that fails." >&2
  exit 1
fi
mkdir -p "$out"
trap 'chown -R --reference="$here" "$here/results"' EXIT

say() {
  echo "$(date +%T) $*" | tee -a "$summary"
}

bound() {
  [[ $(basename "$(readlink "$dev/driver" 2>/dev/null)") == "brcmfmac" ]]
}

bt_state() {
  echo "$([[ -d /sys/class/bluetooth/hci0 ]] && echo present || echo missing)" \
    "$(timeout 5 bluetoothctl show 2>/dev/null | grep -o 'Powered: [a-z]*')"
}

# The link and both functions as the kernel and the hardware have them
snap() {
  local d
  {
    echo "# $1: $(date '+%F %T.%N'), uptime $(cut -d' ' -f1 /proc/uptime)"
    echo "driver: $(basename "$(readlink "$dev/driver" 2>/dev/null)")"
    echo "interfaces: $(ls "$dev/net" 2>/dev/null | tr '\n' ' ')"
    echo "policy: $(</sys/module/pcie_aspm/parameters/policy)"
    for d in clkpm l1_aspm l1_1_aspm l1_2_aspm l1_1_pcipm l1_2_pcipm; do
      echo "sysfs $d=$(<"$link/$d")"
    done
    echo "bluetooth: $(bt_state)"
    for d in 0000:00:00.0 0000:01:00.0 0000:01:00.1; do
      echo "## lspci -vvv -s $d"
      lspci -vvv -s "$d"
    done
  } >"$out/$1.txt" 2>&1
}

# The journal's position now: what comes after it is from this step on (an exact position, where
# a time in seconds could take in the step before)
cursor() {
  journalctl -q -n 0 --show-cursor 2>/dev/null | sed -n 's/^-- cursor: //p'
}

kernel_since() {
  journalctl -k -q --after-cursor "$1" -o short-monotonic 2>/dev/null
}

# 0: up; 1: the firmware didn't start; 2: neither within 25 s
wait_up() {
  local since=$1 i
  for (( i = 0; i < 50; i++ )); do
    if bound && compgen -G "$dev/net/*" >/dev/null; then
      return 0
    fi
    if kernel_since "$since" | grep -q 'Dongle setup failed'; then
      return 1
    fi
    sleep 0.5
  done
  return 2
}

unload() {
  local m
  for m in brcmfmac_wcc brcmfmac; do
    if [[ -d /sys/module/$m ]]; then
      modprobe -r "$m" || say "  modprobe -r $m failed"
    fi
  done
}

load() {
  modprobe brcmfmac || say "  modprobe brcmfmac failed"
}

block() {
  echo 0 >"$link/l1_2_aspm" && echo 0 >"$link/l1_1_aspm"
}

unblock() {
  echo 1 >"$link/l1_1_aspm" && echo 1 >"$link/l1_2_aspm"
}

# trial NAME [block|block6]: a reload; 0 when the firmware came up
trial() {
  local name=$1 pre=${2:-} mark rc
  mark=$(cursor)
  snap "$name-1-before"
  if [[ $pre == block* ]]; then
    block || say "  $name: blocking L1.1/L1.2 failed"
    say "  $name: L1.1/L1.2 blocked at uptime $(cut -d' ' -f1 /proc/uptime)"
    snap "$name-2-blocked"
    if [[ $pre == "block6" ]]; then
      sleep 6
    fi
  fi
  say "  $name: unloading at uptime $(cut -d' ' -f1 /proc/uptime)"
  unload
  snap "$name-3-unloaded"
  load
  wait_up "$mark"
  rc=$?
  snap "$name-4-after"
  kernel_since "$mark" >"$out/$name-kernel.txt"
  case $rc in
    0) say "$name ($pre): firmware up" ;;
    1) say "$name ($pre): FAILED (Dongle setup failed)" ;;
    *) say "$name ($pre): FAILED (nothing within 25 s)" ;;
  esac
  return $rc
}

# recover NAME: FLR of the Wi-Fi function, then the whole link if that didn't do it
recover() {
  local name=$1 mark rc
  mark=$(cursor)
  unload
  snap "$name-1-unloaded"
  if echo 1 >"$dev/reset"; then
    say "$name: FLR done"
  else
    say "$name: FLR refused"
  fi
  snap "$name-2-after-flr"
  load
  wait_up "$mark"
  rc=$?
  snap "$name-3-loaded"
  kernel_since "$mark" >"$out/$name-kernel.txt"
  if (( rc == 0 )); then
    say "$name: firmware up after the FLR; Bluetooth $(bt_state)"
    return 0
  fi
  say "$name: firmware still not up after the FLR; trying a reset of the whole link"
  mark=$(cursor)
  unload
  modprobe -r hci_bcm4377 || say "  modprobe -r hci_bcm4377 failed"
  if echo 1 >"$port/reset_subordinate"; then
    say "$name: link reset done"
  else
    say "$name: link reset refused"
  fi
  snap "$name-4-after-link-reset"
  modprobe hci_bcm4377 || say "  modprobe hci_bcm4377 failed"
  load
  wait_up "$mark"
  rc=$?
  snap "$name-5-loaded"
  kernel_since "$mark" >"$out/$name-link-kernel.txt"
  if (( rc == 0 )); then
    say "$name: firmware up after the link reset; Bluetooth $(bt_state)"
    return 0
  fi
  say "$name: firmware still not up: no recovery without a reboot"
  return 1
}

finish() {
  unblock 2>/dev/null
  snap final
  say "End: driver $(basename "$(readlink "$dev/driver" 2>/dev/null)")," \
    "L1.1=$(<"$link/l1_1_aspm") L1.2=$(<"$link/l1_2_aspm"), Bluetooth $(bt_state)"
  say "Results: $out"
  exit "$1"
}

say "X1 reload investigation, kernel $(uname -r), $(dkms status 2>/dev/null | grep brcmfmac)"
snap start

if ! trial A; then
  recover R1 || finish 1
  if trial B; then
    say "B: the reload worked this time"
  else
    recover R2 || finish 1
  fi
fi

if trial C1 block; then
  unblock || say "  unblocking failed"
  if trial C2 block; then
    unblock || say "  unblocking failed"
  else
    recover R3 || finish 1
  fi
else
  recover R3 || finish 1
  unblock || say "  unblocking failed"
  if trial D block6; then
    unblock || say "  unblocking failed"
  else
    recover R4 || finish 1
  fi
fi

# Wi-Fi connected again before handing back
for (( i = 0; i < 30; i++ )); do
  if iw dev wld0 link 2>/dev/null | grep -q '^Connected to'; then
    break
  fi
  sleep 1
done
finish 0
