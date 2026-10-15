#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Instructions and rules for coding agents (skills, from taris-desktop: /usr/share/taris/agent-skills),
# linked where the agents look for them: ~/.agents, ~/.claude, ~/.codex, ~/.pi (and ~/.gemini,
# ~/.hermes when those agents are set up). A new account gets them from taris-desktop's
# user-defaults; this links them for this one. Safe to re-run.
set -euo pipefail

share=/usr/share/taris/agent-skills
[[ -d $share ]] || {
  echo "taris-desktop isn't installed (no $share)" >&2
  exit 1
}

dirs=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.pi/agent/skills")
[[ -d $HOME/.gemini ]] && dirs+=("$HOME/.gemini/config/skills")
if [[ -d $HOME/.hermes ]]; then
  dirs+=("$HOME/.hermes/skills")
  for profile in "$HOME"/.hermes/profiles/*/; do
    [[ -d $profile ]] && dirs+=("${profile}skills")
  done
fi

# The copies older versions of this script made
old="${XDG_DATA_HOME:-$HOME/.local/share}/taris/agent-skills"

for dir in "${dirs[@]}"; do
  mkdir -p "$dir"
  for link in "$dir"/*; do
    [[ -L $link && $(readlink "$link") == "$old/"* ]] && rm -f "$link"
    [[ -L $link && $(readlink "$link") == "$share/"* && ! -e $link ]] && rm -f "$link"
  done
  for skill in "$share"/*/; do
    skill=${skill%/}
    link="$dir/${skill##*/}"
    if [[ -e $link && ! -L $link ]]; then
      echo "Skipping $link: it exists and is not a link"
      continue
    fi
    ln -sfn "$skill" "$link"
  done
done
rm -rf "$old"

echo "Agent skills linked: $(ls "$share" | tr '\n' ' ')"
