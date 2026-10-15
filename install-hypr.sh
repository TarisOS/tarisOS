#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# This account's Hyprland config: ~/.config/hypr/hyprland.lua loads TarisOS's
# (/usr/share/taris/hypr, from taris-desktop), as a new account's does (/etc/skel). A hyprland.lua
# that isn't that is kept as a backup; the links older versions of this script made go.
set -euo pipefail

conf="${XDG_CONFIG_HOME:-$HOME/.config}"
hypr="$conf/hypr/hyprland.lua"
skel=/etc/skel/.config/hypr/hyprland.lua

[[ -f $skel ]] || {
  echo "taris-desktop isn't installed (no $skel)" >&2
  exit 1
}
mkdir -p "$conf/hypr"
[[ -L $conf/taris/hypr-taris.lua ]] && rm -f "$conf/taris/hypr-taris.lua"
if [[ ! -L $hypr ]] && cmp -s "$hypr" "$skel"; then
  echo "The TarisOS Hyprland config is already at $hypr"
  exit 0
fi
[[ -f $hypr && ! -L $hypr ]] && cp -p "$hypr" "$hypr.bak.$(date +%s)"
# Replaced in one step: a running Hyprland reloads when its config changes, and a moment without
# the file leaves it on an error it doesn't recover from (the file it watched is gone)
install -m644 "$skel" "$hypr.new"
mv -fT "$hypr.new" "$hypr"
echo "Installed the TarisOS Hyprland config at $hypr"
