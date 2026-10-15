#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Coding agent installs for Settings > Apps > Agent:
#   install.sh <agent> [name]   install it (run in a terminal Settings opens; with
#                               TARIS_AGENT_INLINE=1, by something that runs it right after: no
#                               closing prompt)
#   install.sh --check <agent>  exit 0 when it's installed
#   install.sh --installed      print the installed agents, one per line
# All through mise.

agents=(claude codex agy copilot crush grok hermes omp opencode ori pi)

# mise puts what it installs on PATH through its shims; the session doesn't have them on PATH by
# itself
mise_shims="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
[[ :$PATH: == *":$mise_shims:"* ]] || export PATH="$mise_shims:$PATH"

# Hermes pins its dependencies and Python (>=3.11,<3.14), so mise builds it a private
# environment on a pinned interpreter, with uv
hermes_tool="pipx:hermes-agent[extras=all]"
hermes_python="3.13"

package_of() {
  case "$1" in
  omp) echo "github:can1357/oh-my-pi" ;;
  ori) echo "github:OpenRouterLabs/ori-releases" ;;
  grok) echo "npm:@xai-official/grok" ;;
  agy) echo "antigravity-cli" ;;
  hermes) echo "$hermes_tool" ;;
  claude | codex | copilot | crush | opencode | pi) echo "$1" ;;
  *) return 1 ;;
  esac
}

# What mise has installed, one package per line (one quick call; `mise where` is slow for a
# package it doesn't have)
mise_installed=$(command -v mise >/dev/null && mise ls --installed --json 2>/dev/null |
  python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)))' 2>/dev/null)

# A command on PATH can be a stub that installs the agent on first run (it runs `mise use -g`), so it
# doesn't mean the agent is installed: ask mise, and only count a command that isn't such a stub
installed() {
  local agent="$1" package path
  package=$(package_of "$agent") || return 1
  # mise lists the Hermes tool without its extras
  grep -qxF "${package%%\[*}" <<<"$mise_installed" && return 0
  path=$(command -v "$agent") || return 1
  ! grep -q "mise use -g" "$path" 2>/dev/null
}

case "${1:-}" in
--check)
  installed "${2:-}"
  exit
  ;;
--installed)
  for agent in "${agents[@]}"; do
    installed "$agent" && echo "$agent"
  done
  exit 0
  ;;
esac

agent="${1:-}"
name="${2:-$agent}"
after="Press Restart in the dashboard's Agent tab to start it."

finish() {
  if [[ -n ${TARIS_AGENT_INLINE:-} ]]; then
    [[ ${2:-0} -ne 0 ]] && printf '\n%s\n' "$1"
    exit "${2:-0}"
  fi
  printf '\n%s\nPress Enter to close.' "$1"
  read -r
  exit "${2:-0}"
}

package=$(package_of "$agent") || finish "Unsupported agent: $agent" 1

command -v mise >/dev/null || finish "Installing $name needs mise (https://mise.jdx.dev). Install mise, or install $name yourself, then: $after" 1

# Agents mise builds from npm need Node, and Hermes needs uv; get them through mise when missing
if [[ $package == npm:* ]] && ! command -v npm >/dev/null; then
  printf 'Installing Node (needed for %s) with mise…\n\n' "$name"
  mise use -g node@lts || finish "Could not install Node, which $name needs." 1
fi
if [[ $agent == hermes ]] && ! command -v uv >/dev/null; then
  printf 'Installing uv (needed for %s) with mise…\n\n' "$name"
  mise use -g uv@latest || finish "Could not install uv, which $name needs." 1
fi

printf 'Installing %s with mise (%s)…\n\n' "$name" "$package"
if [[ $agent == hermes ]]; then
  # Hermes ships several times a week; mise's release cooldown would hold the new one back
  UV_PYTHON="$hermes_python" MISE_MINIMUM_RELEASE_AGE=0 mise use -g --force "$package" || finish "Could not install $name with mise." 1
else
  mise use -g "$package" || finish "Could not install $name with mise." 1
fi
finish "$name is installed. $after"
