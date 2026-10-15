#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# The Asahi kernel and its initramfs (btrfs root; the asahi hook loads the firmware early)
set -euo pipefail
. /taris-build/lib.sh

sed -i -e 's/^HOOKS=(base.*/HOOKS=(base asahi udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' \
	-e 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
mkdir -p /boot/efi/m1n1
pacman_retry --noconfirm --needed -S linux-asahi asahi-meta
