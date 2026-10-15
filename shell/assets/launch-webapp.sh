#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Open a web app (launch-webapp.sh <url>) in its own window: in the default browser when that's
# Chromium-based (they all have --app), otherwise in Chromium
browser=$(xdg-settings get default-web-browser 2>/dev/null)
case $browser in
chromium* | google-chrome* | brave* | microsoft-edge* | vivaldi* | helium*) ;;
*) browser=chromium.desktop ;;
esac

bin=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "${XDG_DATA_HOME:-$HOME/.local/share}/applications/$browser" \
  /usr/share/applications/"$browser" 2>/dev/null | head -1)
exec "${bin:-chromium}" --app="$1"
