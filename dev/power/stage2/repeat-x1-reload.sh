#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 2 X1: how often the Wi-Fi driver's reload fails, under the conditions named (default: off,
# before, asis, in that order), COUNT reloads each (default 10). Before every reload Wi-Fi is
# connected again and left idle for 10 s, as in the reloads that failed.
#   off:    L1.1/L1.2 blocked (sysfs) for the whole condition.
#   before: on while the firmware runs, blocked right before each unload, on again after.
#   asis:   on; the patched driver (taris-brcmfmac-dkms) switches them off at the chip reset.
#   plain:  L1.1/L1.2 not touched: for a boot with the kernel's own driver, where they're never
#           on (without X1 at all).
# A reload that fails gets a recovery: a function-level reset (FLR) of the Wi-Fi function, then a
# reset of the whole link; whether either brings the firmware back is recorded. A condition stops
# after 3 failures; the run stops when no recovery works (then reboot). It ends with L1.1/L1.2
# unblocked and the driver loaded.
# Results: results/x1-repeat-<time>/ (summary.txt; for each failure the link's registers and the
# kernel log). About 8 minutes with the default; Wi-Fi drops at every reload.
# Run by the maintainer, as root, from anywhere:
#   sudo ~/Projects/tarisOS/dev/power/stage2/repeat-x1-reload.sh [COUNT [CONDITION...]]

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dev=/sys/bus/pci/devices/0000:01:00.0
port=/sys/bus/pci/devices/0000:00:00.0
link=$dev/link
count=${1:-10}
conditions=(off before asis)
if (( $# > 1 )); then
  conditions=("${@:2}")
fi
out=$here/results/x1-repeat-$(date +%Y%m%d-%H%M%S)
summary=$out/summary.txt

if [[ ! $count =~ ^[1-9][0-9]?$ ]]; then
  echo "COUNT is 1 to 99." >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ $(basename "$(readlink "$dev/driver" 2>/dev/null)") != "brcmfmac" ]] ||
  ! compgen -G "$dev/net/*" >/dev/null; then
  echo "The Wi-Fi driver isn't up on $dev: start from working Wi-Fi (reboot first)." >&2
  exit 1
fi
for c in "${conditions[@]}"; do
  case $c in
    off | before | asis)
      if [[ $(<"$link/l1_2_aspm") != "1" ]]; then
        echo "L1.2 isn't on ($(<"$link/l1_2_aspm")): $c needs the installed state." >&2
        exit 1
      fi
      ;;
    plain) ;;
    *)
      echo "Unknown condition $c (off, before, asis, plain)." >&2
      exit 1
      ;;
  esac
done
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

connected() {
  iw dev wld0 link 2>/dev/null | grep -q '^Connected to'
}

# Wi-Fi connected again, then 10 s idle
settle() {
  local i
  for (( i = 0; i < 30; i++ )); do
    if connected; then
      break
    fi
    sleep 1
  done
  sleep 10
}

# One reload; 0 when the firmware came up. A failure's registers and kernel log are kept.
reload_once() {
  local name=$1 mark rc
  mark=$(cursor)
  unload
  load
  wait_up "$mark"
  rc=$?
  if (( rc != 0 )); then
    snap "$name-after"
    kernel_since "$mark" >"$out/$name-kernel.txt"
  fi
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
  if [[ " ${conditions[*]} " != *" plain "* ]]; then
    unblock 2>/dev/null
  fi
  snap final
  say "End: driver $(basename "$(readlink "$dev/driver" 2>/dev/null)")," \
    "L1.1=$(<"$link/l1_1_aspm") L1.2=$(<"$link/l1_2_aspm"), Bluetooth $(bt_state)"
  say "Results: $out"
  exit "$1"
}

# condition NAME: COUNT reloads, or fewer after 3 failures
condition() {
  local cond=$1 i ok=0 bad=0 name
  if [[ $cond == "off" ]]; then
    block || say "  off: blocking L1.1/L1.2 failed"
  fi
  for (( i = 1; i <= count; i++ )); do
    name=$cond-$i
    settle
    if [[ $cond == "before" ]]; then
      block || say "  $name: blocking L1.1/L1.2 failed"
    fi
    if reload_once "$name"; then
      ok=$(( ok + 1 ))
      say "$name: worked (L1.1=$(<"$link/l1_1_aspm") L1.2=$(<"$link/l1_2_aspm") after)"
    else
      bad=$(( bad + 1 ))
      say "$name: FAILED"
      if ! recover "$name-R"; then
        say "$cond: $ok worked, $bad failed of $(( ok + bad )) (stopped: no recovery)"
        finish 1
      fi
    fi
    if [[ $cond == "before" ]]; then
      unblock || say "  $name: unblocking L1.1/L1.2 failed"
    fi
    if (( bad >= 3 )); then
      break
    fi
  done
  if [[ $cond == "off" ]]; then
    unblock || say "  off: unblocking L1.1/L1.2 failed"
  fi
  say "$cond: $ok worked, $bad failed of $(( ok + bad ))"
}

say "X1 reload repeat, $count per condition (${conditions[*]}), kernel $(uname -r)," \
  "driver $(modinfo -n brcmfmac), L1.1=$(<"$link/l1_1_aspm") L1.2=$(<"$link/l1_2_aspm")"
snap start
for c in "${conditions[@]}"; do
  condition "$c"
done
settle
finish 0
