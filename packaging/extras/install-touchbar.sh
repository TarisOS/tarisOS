#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Touch Bar layout for MacBooks running tiny-dfr (media/brightness keys and a screenshot key), from
# taris-hardware's files (on TarisOS that package installs it).
set -euo pipefail
hw="$(cd "$(dirname "$0")/../pkgbuilds/taris-hardware" && pwd)"
[[ -d /etc/tiny-dfr || -x /usr/bin/tiny-dfr ]] || { echo "tiny-dfr is not installed; nothing to do"; exit 0; }
sudo install -Dm644 "$hw/tiny-dfr.toml" /etc/tiny-dfr/config.toml
sudo install -Dm644 "$hw/tiny-dfr-screenshot.png" /etc/tiny-dfr/screenshot.png
sudo systemctl restart tiny-dfr 2>/dev/null || true
echo "Touch Bar layout installed"
