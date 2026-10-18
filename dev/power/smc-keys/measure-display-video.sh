#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Measures the screen's backlight at five levels, then video: a local recording in mpv, decoded
# on the CPU and on the M1's video decoder (AVD), and a YouTube video in Chromium. Every power key
# of taris_smc_keys is sampled once a second into results/display-video-<time>.csv, with how many
# processes have the decoder (/dev/video0) open. The brightness steps from the lowest lit level
# (1, never 0) to full, 45 s each; the videos play at half brightness, without sound, full screen.
# Your brightness is put back at the end, also if the script is interrupted. mpv's logs go to
# results/ to show which decoder it used.
# Chromium runs with your own profile and settings, plus three switches for this run: muted,
# autoplay allowed, full screen. It has to be closed before the start: a Chromium already running
# would take the window over without those switches, and this script closes the one it opens.
# Needs taris_smc_keys loaded (test-install.sh). Takes about 9 minutes; start it from a terminal
# on a normal workspace with the agent workspace hidden, then leave the Mac alone.
# Run by the maintainer, as root:
#   sudo dev/power/smc-keys/measure-display-video.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
power=/sys/kernel/debug/taris-smc/power
bl=/sys/class/backlight/apple-panel-bl
recording=/home/witcher/Videos/Recordings/recording_20261018_13-56-29.mp4
youtube=https://www.youtube.com/watch?v=TvQ7KXhrJAI
stamp=$(date +%Y%m%d-%H%M%S)
out=$here/results/display-video-$stamp.csv

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ ! -r $power ]]; then
  echo "taris_smc_keys isn't loaded: run test-install.sh first." >&2
  exit 1
fi
if [[ -z ${SUDO_USER:-} || $SUDO_USER == "root" ]]; then
  echo "Start it with sudo from your own account: the videos play in your session." >&2
  exit 1
fi
if [[ ! -f $recording ]]; then
  echo "No recording at $recording." >&2
  exit 1
fi
if pgrep -u "$SUDO_USER" -x chromium >/dev/null; then
  echo "Chromium is running: close it first (this script opens and closes its own)." >&2
  exit 1
fi
# The players get the session's own environment, the one apps opened from the shell get (sudo
# keeps almost none of it): taken from the shell's process
shell_pid=$(pgrep -u "$SUDO_USER" -x qs -o || true)
if [[ -z $shell_pid ]]; then
  echo "No Taris shell running for $SUDO_USER: log in to the desktop first." >&2
  exit 1
fi
mapfile -d '' session_env < "/proc/$shell_pid/environ"

max=$(<"$bl/max_brightness")
original=$(<"$bl/brightness")
player=
browser=

set_level() {
  echo "$1" > "$bl/brightness"
}

# Started straight from here, not through a function, so $! is runuser itself
as_user=(runuser -u "$SUDO_USER" -- env -i "${session_env[@]}")

play() {
  local name=$1 hwdec=$2
  "${as_user[@]}" mpv --no-config --fs --no-audio --osc=no --osd-level=0 --loop-file=inf \
    --hwdec="$hwdec" --log-file="$here/results/mpv-$name-$stamp.log" "$recording" \
    >/dev/null 2>&1 &
  player=$!
}

# runuser passes the signal on to mpv; pkill makes sure, matching only that account's mpv on
# the recording. runuser is only waited for once mpv is gone, so this can't hang.
stop_player() {
  kill "$player" 2>/dev/null || true
  pkill -u "$SUDO_USER" -f "mpv .*$recording" 2>/dev/null || true
  if ! pgrep -u "$SUDO_USER" -f "mpv .*$recording" >/dev/null; then
    wait "$player" 2>/dev/null || true
  fi
  player=
}

browse() {
  "${as_user[@]}" chromium --mute-audio --autoplay-policy=no-user-gesture-required \
    --start-fullscreen --new-window "$youtube" >/dev/null 2>&1 &
  browser=$!
}

# SIGTERM to the browser process (the oldest chromium) is a normal quit: no crash notice at the
# next start. Only the Chromium this script started can be running here (checked at the start).
# runuser is only waited for once Chromium is gone, so this can't hang.
stop_browser() {
  local i
  pkill -TERM -o -u "$SUDO_USER" -x chromium 2>/dev/null || true
  for (( i = 0; i < 20; i++ )); do
    if ! pgrep -u "$SUDO_USER" -x chromium >/dev/null; then
      break
    fi
    sleep 0.5
  done
  if pgrep -u "$SUDO_USER" -x chromium >/dev/null; then
    echo "Chromium didn't quit within 10 s; close it yourself." >&2
  else
    wait "$browser" 2>/dev/null || true
  fi
  browser=
}

restore() {
  if [[ -n $player ]]; then
    stop_player
  fi
  if [[ -n $browser ]]; then
    stop_browser
  fi
  echo "$original" > "$bl/brightness"
}
trap restore EXIT

# Processes holding the M1's video decoder open
decoder_users() {
  { fuser /dev/video0 2>/dev/null || true; } | wc -w
}

keys=$(awk '!/^#/ {printf ",%s", $1}' "$power")
echo "t,phase,ac,brightness,decoder_users,freq_e_khz,freq_p_khz$keys" > "$out"
start=$(date +%s.%N)

sample() {
  local phase=$1 seconds=$2 i
  echo "  $phase, ${seconds} s"
  for (( i = 0; i < seconds; i++ )); do
    printf '%.1f,%s,%s,%s,%s,%s,%s%s\n' \
      "$(awk -v a="$(date +%s.%N)" -v b="$start" 'BEGIN {print a - b}')" "$phase" \
      "$(</sys/class/power_supply/macsmc-ac/online)" "$(<"$bl/actual_brightness")" \
      "$(decoder_users)" \
      "$(</sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)" \
      "$(</sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq)" \
      "$(awk '!/^#/ {printf ",%s", $2}' "$power")" >> "$out"
    sleep 1
  done
}

echo "Sampling into $out (brightness now $original of $max):"
for pct in 0 25 50 75 100; do
  level=$(( max * pct / 100 ))
  if (( level < 1 )); then
    level=1
  fi
  set_level "$level"
  sample "bl-$pct" 45
done

set_level $(( max / 2 ))
sample idle 30
play mpv-cpu no; sample mpv-cpu 60; stop_player; sample idle 20
play mpv-avd vaapi,vaapi-copy; sample mpv-avd 60; stop_player; sample idle 20
browse; sample youtube-loading 20; sample youtube 90; stop_browser; sample idle 20

restore
chown -R --reference="$here" "$here/results"
echo "Done. Brightness is back at $original. The module stays loaded until test-revert.sh."
