#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Regenerate the agent usage records the Agent tab shows: [--force] [--limits-only] [--no-stats] [agent...]
# Each usage-<agent>.py collector next to this prints one display-ready JSON record; this writes
# them to ~/.local/state/taris/agents/usage/<agent>.json, which the tab watches.

usage_dir="${XDG_STATE_HOME:-$HOME/.local/state}/taris/agents/usage"

# The collectors run the agents (codex), which mise puts on PATH through its shims; the session
# doesn't have them on PATH by itself
mise_shims="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
[[ :$PATH: == *":$mise_shims:"* ]] || export PATH="$mise_shims:$PATH"

here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$usage_dir"

flags=()
only=()
while (($# > 0)); do
  case "$1" in
  --force | --limits-only | --no-stats) flags+=("$1") ;;
  *) only+=("$1") ;;
  esac
  shift
done

wanted() {
  ((${#only[@]} == 0)) && return 0
  local candidate
  for candidate in "${only[@]}"; do
    [[ $candidate == "$1" ]] && return 0
  done
  return 1
}

collect() {
  local collector="$1" agent="$2" record tmp
  if ! record=$("$collector" "${flags[@]}") || [[ -z $record ]] || ! python3 -c 'import json, sys; json.loads(sys.stdin.read())' <<<"$record" 2>/dev/null; then
    echo "taris agent usage: $agent collector failed" >&2
    return 1
  fi
  tmp=$(mktemp "$usage_dir/.$agent.XXXXXX")
  printf '%s\n' "$record" >"$tmp"
  mv "$tmp" "$usage_dir/$agent.json"
}

pids=()
for collector in "$here"/usage-*.py; do
  [[ -x $collector ]] || continue
  agent="${collector##*/usage-}"
  agent="${agent%.py}"
  wanted "$agent" || continue
  collect "$collector" "$agent" &
  pids+=($!)
done

status=0
for pid in "${pids[@]}"; do
  wait "$pid" || status=1
done
exit $status
