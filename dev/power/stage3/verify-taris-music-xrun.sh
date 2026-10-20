#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Stage 3: checks taris-music's cpal patch (taris-cpal-xrun-recovery.patch) in the installed app.
# Freezes Taris Music's audio thread (cpal_alsa_out) once for 400 ms with ptrace while the rest
# of the app runs: pipewire-alsa keeps pulling, so the stream underruns while the thread waits
# for the device, as it can in normal use. Then watches the thread for 3 s: recovered (it sleeps
# between periods again, using a few % of a core at most) or stuck (100% of a core and no sleeps:
# the bug, which plays silence until the app is quit). What plays has a 0.4 s gap.
# Needs: Taris Music open with its own player started (play a track in it once). Run as root,
# since it traces another program's thread:
#   sudo dev/power/stage3/verify-taris-music-xrun.sh [pid]
# pid: another program instead of Taris Music (the throwaway test program, to check this script).

set -euo pipefail

pid=${1:-$(pgrep -x taris-music -o || true)}
if [[ -z $pid ]]; then
  echo "Taris Music isn't running: open it and play a track." >&2
  exit 1
fi
if [[ -z ${1:-} ]]; then
  echo "# $(pacman -Q taris-music)"
fi
tid=
for t in /proc/$pid/task/*; do
  if [[ $(<"$t/comm") == "cpal_alsa_out" ]]; then
    tid=${t##*/}
  fi
done
if [[ -z $tid ]]; then
  echo "No audio thread (cpal_alsa_out) in process $pid: play a track in Taris Music once (its" \
    "own player starts on first use)." >&2
  exit 1
fi
hz=$(getconf CLK_TCK)

# The thread's CPU time (ticks) and voluntary context switches (its sleeps)
stats() {
  local cpu vol
  cpu=$(awk '{sub(/^.*\) /, ""); print $12 + $13}' "/proc/$pid/task/$tid/stat")
  vol=$(awk '$1 == "voluntary_ctxt_switches:" {print $2}' "/proc/$pid/task/$tid/status")
  echo "$cpu $vol"
}

# Watches the thread for $1 seconds: "<% of a core> <sleeps per second>"
watch_thread() {
  local a b
  a=($(stats))
  sleep "$1"
  b=($(stats))
  awk -v c="$(( b[0] - a[0] ))" -v v="$(( b[1] - a[1] ))" -v s="$1" -v hz="$hz" \
    'BEGIN {printf "%.0f %.0f\n", 100 * c / hz / s, v / s}'
}

read -r cpu0 sleeps0 < <(watch_thread 1)
echo "audio thread $tid before: $cpu0% of a core, $sleeps0 sleeps/s"
if (( cpu0 > 80 && sleeps0 == 0 )); then
  echo "It's stuck already, before the test: this Taris Music doesn't have the fix (or wasn't" \
    "restarted after the update)."
  exit 1
fi

# Freeze only that thread (ptrace stops the traced thread, not its process) for 400 ms
if ! python3 -I - "$tid" <<'EOF'
import ctypes, os, sys, time

PTRACE_DETACH, PTRACE_SEIZE, PTRACE_INTERRUPT, WALL = 17, 0x4206, 0x4207, 0x40000000
libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.argtypes = [ctypes.c_long, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]
tid = int(sys.argv[1])
if libc.ptrace(PTRACE_SEIZE, tid, None, None) != 0:
    sys.exit("can't trace the audio thread (%s): run with sudo" % os.strerror(ctypes.get_errno()))
libc.ptrace(PTRACE_INTERRUPT, tid, None, None)
os.waitpid(tid, WALL)
time.sleep(0.4)
libc.ptrace(PTRACE_DETACH, tid, None, None)
EOF
then
  exit 1
fi

read -r cpu1 sleeps1 < <(watch_thread 3)
echo "audio thread $tid after the underrun: $cpu1% of a core, $sleeps1 sleeps/s"
if (( cpu1 > 80 && sleeps1 == 0 )); then
  echo "STUCK: the audio thread spins at 100% of a core and plays nothing (the bug)."
  exit 1
fi
if (( sleeps1 > 0 )); then
  echo "RECOVERED: the audio thread is back to normal."
else
  echo "UNCLEAR: the thread neither spins nor sleeps; check again."
  exit 1
fi
