# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# TarisOS's distribution settings, shared by the repository and image builds (sourced)

# The package repository (pacman's [taris]): a GitHub release's assets, in a repo of their own so
# the source repo's releases stay TarisOS's
TARIS_REPO=taris
TARIS_REPO_SERVER=https://github.com/TarisOS/tarisOS-packages/releases/download/packages

# Where the installer image (the zip), installer_data.json and install.sh are published: the latest
# TarisOS release on the source repo (versioned releases, v1.0.0 and on; not pre-releases, which
# "latest" skips)
TARIS_IMAGE_BASE=https://github.com/TarisOS/tarisOS/releases/latest/download
TARIS_IMAGE_NAME=tarisos

# Built from the AUR into the repository (fetched when the repository is built; a changed
# PKGBUILD is shown for review before it's built)
TARIS_AUR_PACKAGES=(yay vscodium-bin nordvpn-bin lyrebird-proxy tela-icon-theme whitesur-icon-theme fluent-icon-theme-git evdi-dkms)

# This repository's own packages, in build order (each needs the ones before it installed to build)
TARIS_PACKAGES=(
	libcava qt6-m3shapes-git ttf-rubik-vf python-materialyoucolor mise-bin libva-v4l2-request-avd obs-studio tor-browser-bin taris-music
	quickshell-taris taris-cli qmltermwidget-taris taris-shell
	taris-keyring smi-usbdisplay-taris taris-tipd-dkms taris-appledrm-dkms tiny-dfr-taris taris-hardware taris-desktop taris-login taris-chromium taris-snapshots taris-firewall taris-tor taris-thumbnails taris-wallpapers taris-dev taris
)

# Where builds go (big: not in /tmp, which is RAM here)
TARIS_OUT="${TARIS_OUT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/out}"
