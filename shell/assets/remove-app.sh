#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Remove an app from the app drawer's menu (Remove…): remove-app.sh <desktop-id> <name>
# What it removes:
# - a launcher of your own (~/.local/share/applications: web apps, TUIs, AppImages...) is deleted,
#   with its icon when that's one of yours, and the AppImage it starts
# - a package's app is uninstalled in a terminal (sudo pacman -Rns, asking for your password)
# - a flatpak is uninstalled in a terminal
# - TarisOS's entry for another package's app (X-Taris-Package=: KDE Connect's, NordVPN's) uninstalls
#   that package
# For those two it prints "run <command>": the shell runs it in its own terminal, in the overlay
# like its settings.
# Anything else says why in a notification.

id="${1%.desktop}"
name="${2:-$id}"

fail() {
  notify-send -a TarisOS -u normal "Couldn't remove $name" "$1" 2>/dev/null
  echo "$1" >&2
  exit 1
}

[[ -n $id ]] || fail "No app was given."

user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
dirs=("$user_dir")
IFS=: read -ra data_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for d in "${data_dirs[@]}"; do dirs+=("$d/applications"); done

# The launcher: <dir>/<id>.desktop, or one in a subfolder (an id like kde-foo is kde/foo.desktop)
file=""
for d in "${dirs[@]}"; do
  if [[ -f $d/$id.desktop ]]; then
    file="$d/$id.desktop"
    break
  fi
  if [[ $id == *-* && -f $d/${id/-//}.desktop ]]; then
    file="$d/${id/-//}.desktop"
    break
  fi
done
[[ -n $file ]] || fail "Its launcher ($id.desktop) wasn't found."

# For the shell's terminal (sudo asks for the password there)
in_terminal() {
  printf 'run %s\n' "$1"
  exit 0
}

if [[ $(readlink -f "$file") == "$(readlink -f "$user_dir")"/* ]]; then
  icon=$(sed -n 's/^Icon=//p' "$file" | head -1)
  exec_line=$(sed -n 's/^Exec=//p' "$file" | head -1)
  # An AppImage of yours goes with its launcher
  appimage=$(grep -o '[^" ]*\.[Aa]pp[Ii]mage' <<<"$exec_line" | head -1)
  appimage="${appimage/#\~/$HOME}"
  rm -f "$file"
  [[ $icon == /* && $(readlink -f "$icon") == "$HOME"/* ]] && rm -f "$icon"
  [[ -n $appimage && $(readlink -f "$appimage") == "$HOME"/* ]] && rm -f "$appimage"
  update-desktop-database "$user_dir" &>/dev/null || true
  exit 0
fi

# The entry's own package is TarisOS's here (taris-shell), not the app's
package=$(sed -n 's/^X-Taris-Package=//p' "$file" | head -1)
if [[ -n $package ]]; then
  in_terminal "echo $(printf '%q' "Uninstalling $name ($package)..."); sudo pacman -Rns $(printf '%q' "$package")"
fi

if package=$(pacman -Qqo "$(readlink -f "$file")" 2>/dev/null | head -1) && [[ -n $package ]]; then
  in_terminal "echo $(printf '%q' "Uninstalling $name ($package)..."); sudo pacman -Rns $(printf '%q' "$package")"
fi

if command -v flatpak >/dev/null && flatpak info "$id" &>/dev/null; then
  in_terminal "flatpak uninstall $(printf '%q' "$id")"
fi

fail "It isn't one of your launchers, a package's or a flatpak's, so there's nothing here to uninstall."
