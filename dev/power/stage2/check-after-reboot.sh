#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# After installing taris-hardware 1.0.0-8 (built from packaging/pkgbuilds/taris-hardware) and a
# reboot: checks that the Stage 2 changes took effect from boot (S1 and
# S2's values, PipeWire's audio threads without boost, kcompactd quiet, kernel auditing off, no
# journald complaints) and repeats the system-call timing of results/syscall-before-reboot.txt to
# measure S3. Read-only: it changes nothing. Writes results/after-reboot-<time>.txt.
# Run by the maintainer, as root:
#   sudo dev/power/stage2/check-after-reboot.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
before=$here/results/syscall-before-reboot.txt
bench=$here/tools/syscall-bench
out=$here/results/after-reboot-$(date +%Y%m%d-%H%M%S).txt

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ ! -f $before ]]; then
  echo "Missing $before: the timing taken before the reboot." >&2
  exit 1
fi
if [[ ! -x $bench ]]; then
  echo "Missing $bench: build it first (as your user):" \
    "gcc -O2 -o $bench $bench.c" >&2
  exit 1
fi

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

{
  echo "# $(date '+%F %T'), boot $(</proc/sys/kernel/random/boot_id)"
  if grep -q "boot $(</proc/sys/kernel/random/boot_id)" "$before"; then
    echo "  FAIL  this is the same boot as the timing before: reboot first"
    bad=$(( bad + 1 ))
  fi

  echo "S1 and S2, from /usr/lib/sysctl.d/50-taris-power.conf:"
  check "kernel.sched_util_clamp_min_rt_default" 0 \
    "$(sysctl -n kernel.sched_util_clamp_min_rt_default)"
  check "vm.compaction_proactiveness" 0 "$(sysctl -n vm.compaction_proactiveness)"
  for p in $(pgrep -x 'pipewire|wireplumber|pipewire-pulse'); do
    for t in /proc/$p/task/*; do
      if [[ $(<"$t/comm") == data-loop* ]]; then
        check "$(<"/proc/$p/comm") $(<"$t/comm") minimum" 0 \
          "$(awk '/effective uclamp.min/ {print $NF}' "$t/sched")"
      fi
    done
  done
  k=$(pgrep -x kcompactd0)
  a=$(awk '/ctxt_switches/ {s += $2} END {print s}' "/proc/$k/status")
  sleep 10
  b=$(awk '/ctxt_switches/ {s += $2} END {print s}' "/proc/$k/status")
  check "kcompactd0 wake-ups in 10 s" 0 "$(( b - a ))"

  echo "S3, from /usr/lib/systemd/journald.conf.d/50-taris-audit.conf:"
  check "kernel auditing (auditctl -s)" "enabled 0" "$(auditctl -s | grep -o '^enabled [0-9]*')"
  check "audit records this boot" 0 "$(journalctl -b -q -o cat _TRANSPORT=audit | wc -l)"
  check "journald warnings this boot" 0 "$(journalctl -b -q -p warning -u systemd-journald | wc -l)"

  echo "S4, the Wi-Fi's wake time after traffic (wifi-power-timeout at each connection):"
  check "helper installed" yes \
    "$([[ -x /usr/lib/taris/wifi-power-timeout ]] && echo yes || echo no)"
  check "dispatcher script installed" yes \
    "$([[ -x /usr/lib/NetworkManager/dispatcher.d/50-taris-wifi-power ]] && echo yes || echo no)"
  # The helper's own line, which the dispatcher logs from stderr; only when Wi-Fi is connected
  if [[ $(</sys/class/net/wld0/operstate) == "up" ]]; then
    check "set at this boot's connection" yes "$(journalctl -b -q -u NetworkManager-dispatcher \
      -o cat | grep -q 'wld0: power saving on, awake for 200 ms' && echo yes || echo no)"
  fi

  echo "System-call cost (ns per getppid, 5 runs of 20 million):"
  for c in 0 4; do
    was=$(awk -v c="cpu$c" '$1 == c {for (i = 3; i <= NF; i++) s = s " " $i; print s}' "$before")
    now=$(taskset -c "$c" "$bench" | tr '\n' ' ')
    echo "  cpu$c before:$was"
    echo "  cpu$c now:    $now"
    awk -v a="$was" -v b="$now" -v c="cpu$c" 'BEGIN {
      n = split(a, x); m = split(b, y); asort(x); asort(y)
      was = x[int((n + 1) / 2)]; now = y[int((m + 1) / 2)]
      printf "  cpu%s median %.2f -> %.2f ns: %+.1f %%\n", substr(c, 4), was, now,
        (now / was - 1) * 100
    }'
  done

  echo "$ok checks passed, $bad failed."
} 2>&1 | tee "$out"
chown --reference="$here" "$out"
