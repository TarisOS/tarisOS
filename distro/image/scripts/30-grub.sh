#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# GRUB as the EFI boot loader U-Boot starts: its core image finds the root by UUID and reads the
# rest from /boot/grub in @ (its menu is made with the image, once the root exists)
set -euo pipefail

mkdir -p /boot/grub /boot/efi
cat >/tmp/grub-core.cfg <<CFG
search.fs_uuid $ROOT_UUID root
set prefix=(\$root)'/@/boot/grub'
CFG

touch /boot/grub/device.map
dd if=/dev/zero of=/boot/grub/grubenv bs=1024 count=1 status=none
cp -r /usr/share/grub/themes /boot/grub
cp -r /usr/lib/grub/arm64-efi /boot/grub/
rm -f /boot/grub/arm64-efi/*.module
mkdir -p /boot/grub/fonts /boot/grub/locale
cp /usr/share/grub/unicode.pf2 /boot/grub/fonts
shopt -s nullglob
for mo in /usr/share/locale/*/LC_MESSAGES/grub.mo; do
	lc=${mo#/usr/share/locale/}
	cp "$mo" "/boot/grub/locale/${lc%%/*}.mo"
done

grub-mkimage --directory /usr/lib/grub/arm64-efi -c /tmp/grub-core.cfg --prefix /boot/grub \
	--output /boot/grub/arm64-efi/core.efi --format arm64-efi --compression auto \
	ext2 part_gpt search btrfs
rm -f /tmp/grub-core.cfg

# (No UEFI firmware settings entry: there's none to go to on a Mac)
rm -f /etc/grub.d/30_uefi-firmware
sed -i '/efi_uga/d' /etc/grub.d/00_header
