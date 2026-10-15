#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# The base system for Apple Silicon only: Arch Linux ARM's generic kernel and every firmware
# package for other hardware go (a Mac's firmware comes from macOS, copied by the installer)
set -euo pipefail
. /taris-build/lib.sh

mkdir -p /boot/efi/EFI/BOOT /boot/efi/m1n1
touch /boot/efi/.builder

pacman --noconfirm -Rdd linux-aarch64 || true
mapfile -t firmware < <(pacman -Qq | grep -E '^linux-firmware' || true)
((${#firmware[@]} == 0)) || pacman --noconfirm -Rdd "${firmware[@]}"

pacman_retry --noconfirm -Syu
pacman_retry --noconfirm --needed -S asahi-scripts asahi-fwextract m1n1 uboot-asahi mkinitcpio grub sudo \
	man-db man-pages btrfs-progs networkmanager
