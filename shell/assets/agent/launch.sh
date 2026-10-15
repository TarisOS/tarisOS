#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Run a coding agent in the Agent tab's terminal: launch.sh <agent>

agent="${1:-}"

# The shell may have been started from another terminal (`taris shell -r` in kitty) and pass its
# identity on; agents then use that terminal's extras (kitty's image protocol), which this one
# prints as text. Say what it is: an xterm.
for var in $(compgen -v | grep -E '^(KITTY|GHOSTTY|WEZTERM|ALACRITTY|KONSOLE|VTE|ITERM|WT)_'); do
  unset "$var"
done
unset TERMINFO TERM_PROGRAM TERM_PROGRAM_VERSION
export TERM=xterm-256color COLORTERM=truecolor

# mise puts the agents it installs on PATH through its shims; the session doesn't have them on PATH
# by itself
mise_shims="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
[[ :$PATH: == *":$mise_shims:"* ]] || export PATH="$mise_shims:$PATH"

# Agents refuse to remember trust for $HOME, so start in the Projects folder when there is one:
# trust given there once is kept. xdg-user-dirs makes it at setup, named in the account's language
projects_dir=$(xdg-user-dir PROJECTS)
[[ $PWD == "$HOME" && $projects_dir != "$HOME" && -d $projects_dir ]] && cd "$projects_dir"

wait_and_exit() {
  printf '\n%s\n' "$1"
  printf 'Press Enter to close.'
  read -r
  exit 1
}

[[ -z $agent ]] && wait_and_exit "No default agent yet. Pick one in Settings → Apps → Agent, then press Restart."

case "$agent" in
opencode) command=(opencode --auto) ;;
agy) command=(agy --dangerously-skip-permissions) ;;
copilot) command=(copilot --allow-all) ;;
crush) command=(crush --yolo) ;;
claude) command=(claude --permission-mode auto) ;;
grok) command=(grok --permission-mode bypassPermissions) ;;
codex) command=(codex --approve-for-me) ;;
hermes) command=(hermes --yolo) ;;
omp) command=(omp --auto-approve) ;;
ori) command=(ori code) ;; # Ori is a harness launcher; `ori code` is the agent it runs itself
pi) command=(pi) ;;
*) wait_and_exit "Unsupported agent: $agent" ;;
esac

# Not installed yet (Claude Code, the default, is installed on first use): installed here first
if ! command -v "${command[0]}" >/dev/null; then
  TARIS_AGENT_INLINE=1 "$(dirname "$(readlink -f "$0")")/install.sh" "$agent" ||
    wait_and_exit "$agent couldn't be installed (is there a network connection?). Press Restart to try again, or pick another agent in Settings → Apps → Agent."
  hash -r
  command -v "${command[0]}" >/dev/null || wait_and_exit "$agent is not installed. Install it, or pick another agent in Settings → Apps → Agent."
fi

exec "${command[@]}"
