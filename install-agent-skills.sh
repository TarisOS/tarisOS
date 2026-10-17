#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Instructions for coding agents, for this account: taris-desktop's agent-setup links TarisOS's
# skills where the agents look for them and puts TarisOS's rules in the file each agent reads at
# the start of every session (see /usr/lib/taris/agent-setup). A new account gets them from
# taris-desktop's user-defaults; this sets them up for this one. Safe to re-run.
# Usage: ./install-agent-skills.sh
set -euo pipefail

if [[ ! -x /usr/lib/taris/agent-setup ]]; then
  echo "taris-desktop isn't installed, or is older than its agent-setup (update it first)" >&2
  exit 1
fi
/usr/lib/taris/agent-setup
echo "Agent skills linked: $(ls /usr/share/taris/agent-skills | tr '\n' ' ')"
echo "Agent rules: /usr/share/taris/agent-rules.md"
