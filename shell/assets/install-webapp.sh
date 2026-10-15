#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Add a web app to the apps (the launcher's >install): install-webapp.sh <name> <url> [icon file]
# Writes a launcher of yours (~/.local/share/applications) that opens the site in its own browser
# window (assets/launch-webapp.sh), with the site's own icon (fetched, unless an icon file is
# given: the preinstalled web apps bring theirs). assets/remove-app.sh removes both.
# Prints why on stderr when it can't.
set -euo pipefail

name=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"${1:-}")
url="${2:-}"
icon_file="${3:-}"

fail() {
  echo "$1" >&2
  exit 1
}

[[ -n $name ]] || fail "The web app needs a name."
[[ $name != *[[:cntrl:]]* ]] || fail "The name can't have control characters."

# A plain address gets https://; only http(s) is accepted (Chromium's --app runs javascript: and
# file: too), and nothing that would need quoting in the launcher's Exec line
[[ $url =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]] || url="https://$url"
[[ ${url,,} =~ ^https?://[^/[:space:]]+ ]] || fail "$url isn't a web address."
[[ $url != *[[:space:]\"\'\`\$\\]* ]] || fail "$url isn't a web address."

id="webapp-$(tr '[:upper:]' '[:lower:]' <<<"$name" | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')"
[[ $id != webapp- ]] || fail "The name needs a letter or number."

data="${XDG_DATA_HOME:-$HOME/.local/share}"
desktop="$data/applications/$id.desktop"
[[ ! -e $desktop ]] || fail "$name is already installed."
mkdir -p "$data/applications" "$data/icons/webapps"

# The site's icon: the page's apple-touch-icon (180px or more), the usual place for one, then
# Google's favicon service
origin=$(sed -E 's|^(https?://[^/]+).*|\1|' <<<"$url")
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

download() {
  curl -fsSL --max-time 10 -o "$tmp" "$1" 2>/dev/null && [[ -s $tmp && $(file -b --mime-type "$tmp") == image/* ]]
}

touch_icon=""
[[ -f $icon_file ]] || touch_icon=$(curl -fsSL --max-time 5 "$url" 2>/dev/null | head -c 200000 | tr '\n' ' ' |
  grep -oiE "<link[^>]*rel=[\"'][^\"']*apple-touch-icon[^\"']*[\"'][^>]*>" | grep -oiE "href=[\"'][^\"']+" |
  head -1 | sed -E "s/^href=[\"']//") || true
case $touch_icon in
http://* | https://*) ;;
//*) touch_icon="https:$touch_icon" ;;
/*) touch_icon="$origin$touch_icon" ;;
?*) touch_icon="$origin/$touch_icon" ;;
esac

icon="applications-internet"
if [[ -f $icon_file ]] && cp "$icon_file" "$tmp" && [[ $(file -b --mime-type "$tmp") == image/* ]] ||
  { [[ -n $touch_icon ]] && download "$touch_icon"; } || download "$origin/apple-touch-icon.png" ||
  download "https://www.google.com/s2/favicons?domain=$origin&sz=256"; then
  case $(file -b --mime-type "$tmp") in
  image/svg+xml) ext=svg ;;
  image/jpeg) ext=jpg ;;
  image/webp) ext=webp ;;
  image/vnd.microsoft.icon | image/x-icon) ext=ico ;;
  *) ext=png ;;
  esac
  icon="$data/icons/webapps/$id.$ext"
  install -m644 "$tmp" "$icon"
fi

# Desktop entry values: a backslash is an escape there; % is a field code in Exec
name_value=${name//\\/\\\\}
cat >"$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name_value
Comment=$name_value
Exec=$(dirname "$(readlink -f "$0")")/launch-webapp.sh "${url//%/%%}"
Icon=$icon
Terminal=false
StartupNotify=true
EOF
update-desktop-database "$data/applications" &>/dev/null || true
