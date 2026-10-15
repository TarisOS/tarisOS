#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# pacman: Asahi's repository and TarisOS's (the local build while the image is made: the
# published one is set at the end), the keys they're signed with
set -euo pipefail

sed -i -e 's/^#ParallelDownloads = .*/ParallelDownloads = 5/' /etc/pacman.conf
grep -q '^\[asahi-alarm\]' /etc/pacman.conf ||
	sed -i -e '/^\[core\]/i [asahi-alarm]\nInclude = /etc/pacman.d/mirrorlist.asahi-alarm\n' /etc/pacman.conf
grep -q '^\[taris\]' /etc/pacman.conf ||
	sed -i -e '/^\[asahi-alarm\]/i [taris]\nServer = file:///taris-repo\n' /etc/pacman.conf
install -m644 /taris-build/mirrorlist.asahi-alarm /etc/pacman.d/mirrorlist.asahi-alarm

# pacman.conf's DownloadUser (alpm) and the other system users
systemd-sysusers

pacman-key --init
pacman-key --populate archlinuxarm asahi-alarm
# TarisOS's key, until taris-keyring (signed with it) is installed
pacman-key --add /taris-build/taris.gpg
pacman-key --lsign-key "$(cut -d: -f1 /taris-build/taris-trusted)"
