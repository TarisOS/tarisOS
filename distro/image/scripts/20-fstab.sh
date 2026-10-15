#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# The root (@) and the home folders (@home) on btrfs, the EFI system partition at /boot/efi (Asahi's
# first boot writes this again with the installed system's own UUIDs)
set -euo pipefail

cat >/etc/fstab <<FSTAB
UUID=$ROOT_UUID / btrfs rw,relatime,x-systemd.growfs,compress=zstd:1,subvol=@ 0 0
UUID=$ROOT_UUID /home btrfs rw,relatime,x-systemd.growfs,compress=zstd:1,subvol=@home 0 0
UUID=$EFI_UUID /boot/efi vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 2
FSTAB
