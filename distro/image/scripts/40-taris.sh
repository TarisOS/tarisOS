#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# TarisOS (the taris meta package) and the default apps, each installed on its own (explicitly) so
# any of them can be removed. VSCodium and Claude Code aren't in the image: they're installed the
# first time they're used. VLC and Tor Browser aren't either (the image has to fit in a GitHub
# release's 2 GiB): they're installed in the background as the first account logs in
# (taris-desktop's first-apps). CJK fonts and input methods come when a language needs them.
set -euo pipefail
. /taris-build/lib.sh

pacman_retry --noconfirm -S taris-keyring
# PipeWire's JACK server and LV2 host first: left to choose, pacman takes the first of their other
# providers (jack2, and Ardour)
pacman_retry --noconfirm --needed -S pipewire-jack pipewire-audio
pacman_retry --noconfirm --needed -S taris

apps=(
	kitty                  # terminal
	nautilus localsearch   # files, and their search index
	sushi                  # Nautilus's previews (Space)
	fuzzel                 # app launcher, when the shell isn't running
	swappy                 # screenshot editor
	chromium widevine      # browser, and DRM'd video (Spotify, Netflix)
	gnome-text-editor      # text editor
	neovim                 # editor in the terminal
	imv                    # images
	mpv                    # video
	taris-music            # music: YouTube Music (TarisOS's repository, based on Zuno)
	evince                 # PDFs
	gnome-disk-utility     # disks (Disks)
	qbittorrent            # torrents
	# The phone (KDE Connect, in the shell; sshfs browses its files), with Qt's FFmpeg media backend:
	# left to choose, pacman would ask between it and GStreamer
	qt6-multimedia-ffmpeg kdeconnect sshfs
	flatpak                # apps from Flathub (the App Store)
	yay base-devel git     # the AUR (the App Store, >install)
	github-cli             # GitHub from the terminal (gh)
	xdg-user-dirs          # Documents, Downloads, Pictures…
	noto-fonts noto-fonts-emoji
	power-profiles-daemon
)
pacman_retry --noconfirm --needed -S "${apps[@]}"

# Flathub, for every account (system-wide: snapshots and factory reset cover it)
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
