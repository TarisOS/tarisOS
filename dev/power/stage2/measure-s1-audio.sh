#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Audio safety check for Stage 2 S1 (kernel.sched_util_clamp_min_rt_default = 0): how long the
# audio graph and the speaker DSP take per cycle, with the value as found and with S1, at three
# period lengths (2048, 256 and 128 frames at 48 kHz: 42.7, 5.3 and 2.7 ms). Digital silence
# plays through the speakers (nothing is heard) while pw-profiler logs 20 s of cycles for each
# combination. A cycle whose graph runs past its period is an overrun: audio would glitch.
# The value found at the start is put back at the end, also if the script is interrupted.
# Results in results/s1-audio-<time>/ (profiler logs, pw-dump, summary.txt). About 3 minutes.
# Run by the maintainer, as root:
#   sudo dev/power/stage2/measure-s1-audio.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir=$here/results/s1-audio-$(date +%Y%m%d-%H%M%S)
key=kernel.sched_util_clamp_min_rt_default

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
  echo "Start it with sudo from your own account: the audio plays in your session." >&2
  exit 1
fi
shell_pid=$(pgrep -u "$SUDO_USER" -x qs -o || true)
if [[ -z $shell_pid ]]; then
  echo "No Taris shell running for $SUDO_USER: log in to the desktop first." >&2
  exit 1
fi
mapfile -d '' session_env < "/proc/$shell_pid/environ"
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")

orig=$(sysctl -n "$key")
if (( orig == 0 )); then
  echo "S1 is already applied ($key=0): the comparison needs the kernel's default" \
    "(taris-hardware 1.0.0-7, or the value set back to 1024 for the run)." >&2
  exit 1
fi
mkdir -p "$dir"
chown --reference="$here" "$dir"
player=

stop_player() {
  if [[ -n $player ]]; then
    kill "$player" 2>/dev/null || true
    pkill -u "$SUDO_USER" -f '^pw-cat -p --raw' 2>/dev/null || true
    if ! pgrep -u "$SUDO_USER" -f '^pw-cat -p --raw' >/dev/null; then
      wait "$player" 2>/dev/null || true
    fi
    player=
  fi
}

restore() {
  stop_player
  sysctl -q -w "$key=$orig"
}
trap restore EXIT

echo "Profiling into $dir:"
for frames in 2048 256 128; do
  for setting in found s1; do
    if [[ $setting == "s1" ]]; then
      sysctl -q -w "$key=0"
    else
      sysctl -q -w "$key=$orig"
    fi
    "${as_user[@]}" pw-cat -p --raw --format s16 --rate 48000 --channels 2 --latency="$frames" \
      /dev/zero >/dev/null 2>&1 &
    player=$!
    sleep 3
    "${as_user[@]}" pw-dump > "$dir/dump-$frames-$setting.json" 2>/dev/null
    "${as_user[@]}" timeout 20 pw-profiler -o "$dir/prof-$frames-$setting.log" \
      >/dev/null 2>&1 || true
    stop_player
    echo "  $frames frames, $setting"
  done
done
restore
echo "$key is back at $(sysctl -n "$key")."

{
  for frames in 2048 256 128; do
    for setting in found s1; do
      echo "== $frames frames, $setting"
      "$here/tools/profile-summary.py" "$dir/prof-$frames-$setting.log" \
        "$dir/dump-$frames-$setting.json" || true
    done
  done
} > "$dir/summary.txt"
chown -R --reference="$here" "$dir"
cat "$dir/summary.txt"
