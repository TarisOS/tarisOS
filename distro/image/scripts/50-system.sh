#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# The system as it boots for the first time: services, language, console, no accounts (the setup
# screen makes the first), and the greeter's look until someone has logged in
set -euo pipefail

# Services: only what's needed, started when needed
systemctl enable NetworkManager.service bluetooth.service greetd.service systemd-timesyncd.service \
	power-profiles-daemon.service
systemctl disable systemd-networkd.service systemd-networkd.socket iwd.service 2>/dev/null || true
# Arch Linux ARM's tarball turns remote login on: it stays off until it's turned on in Settings
systemctl disable sshd.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service
systemctl set-default graphical.target

# Language and console: US English until the setup screen picks a keyboard; a font that's
# readable on a Retina screen (the decrypt prompt, the TTYs)
sed -i -e 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' >/etc/locale.conf
printf 'KEYMAP=us\nFONT=ter-132b\n' >/etc/vconsole.conf
echo tarisos >/etc/hostname

# Accounts: none to log in to (Arch Linux ARM's alarm and root's default password go)
userdel -r alarm 2>/dev/null || true
passwd -l root

# First boot: the setup screen (until it has made the first account); factory reset can come back
# here (@factory, made with the image)
mkdir -p /var/lib/taris /etc/taris
touch /var/lib/taris/setup-pending /etc/taris/factory

# The greeter's look before anyone has logged in: a new account's (the Taris theme, its
# wallpaper). In a PID namespace of its own: applying a theme signals running apps (btop, cava)
# to reload theirs, which would reach the build machine's.
look=$(mktemp -d)
unshare --pid --fork --mount-proc env -i PATH=/usr/bin HOME="$look" XDG_CONFIG_HOME="$look/.config" \
	XDG_STATE_HOME="$look/.local/state" XDG_DATA_HOME="$look/.local/share" LANG=en_US.UTF-8 \
	/usr/lib/taris/user-defaults >/dev/null 2>&1 || true
mkdir -p /var/lib/taris/greeter/state/taris/wallpaper
[[ -f $look/.local/state/taris/scheme.json ]] && install -m644 "$look/.local/state/taris/scheme.json" /var/lib/taris/greeter/state/taris/scheme.json
echo /usr/share/backgrounds/taris/17.webp >/var/lib/taris/greeter/state/taris/wallpaper/path.txt
rm -rf "$look"
chown -R root:wheel /var/lib/taris/greeter
chmod -R g+w /var/lib/taris/greeter
find /var/lib/taris/greeter -type d -exec chmod 2775 {} +

# Asahi's first boot (fresh UUIDs, the boot loader, pacman's keys), then TarisOS's key again;
# systemd's first boot asks nothing
mkdir -p /etc/systemd/system/first-boot.service.d /etc/systemd/system/systemd-firstboot.service.d
cat >/etc/systemd/system/first-boot.service.d/taris.conf <<CONF
[Service]
ExecStartPost=/usr/bin/pacman-key --populate taris
CONF
cat >/etc/systemd/system/systemd-firstboot.service.d/no-prompt.conf <<CONF
[Service]
ExecStart=
ExecStart=systemd-firstboot
CONF

# m1n1's boot image on the EFI partition (m1n1, the Macs' device trees and U-Boot: what the Mac
# starts), made now that the kernel and its device trees are in. Its pacman hook ran when m1n1 was
# installed, before the kernel, and couldn't.
rm -f /boot/efi/m1n1/boot.bin.new
update-m1n1 /boot/efi/m1n1/boot.bin
[[ $(stat -c %s /boot/efi/m1n1/boot.bin) -gt $(stat -c %s /usr/lib/asahi-boot/m1n1.bin) ]] ||
	{ echo "m1n1's boot image has no device trees or U-Boot in it" >&2; exit 1; }

# The initramfs and its settings as they are now; one without the asahi hook (Apple Silicon's
# storage and firmware) wouldn't boot
mkinitcpio -P
grep -Eq '^HOOKS=\(.*\basahi\b' /etc/mkinitcpio.conf || { echo "mkinitcpio.conf has no asahi hook" >&2; exit 1; }
for image in /boot/initramfs-*.img; do
	lsinitcpio "$image" | grep 'hooks/asahi$' >/dev/null || { echo "$image has no asahi hook" >&2; exit 1; }
done
