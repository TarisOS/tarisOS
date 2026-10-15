#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Builds TarisOS's installer image on this Mac (as root: sudo distro/build-image.sh), in the format
# the Asahi Linux installer installs, as Asahi's own Arch Linux ARM images are made: Arch Linux
# ARM's root tarball, set up in a chroot by image/scripts (from the TarisOS repository build-repo.sh
# made, out/repo), copied into a btrfs root.img (@ for the system, @home for the home folders,
# snapper's .snapshots, and @factory, a read-only snapshot of the system as installed, for factory
# reset) next to the EFI system partition's files, zipped (deflate; nothing else), with the
# installer_data.json that offers it and the macOS command that starts the installer with it
# (install.sh, published with the image). Out: out/images. Big: everything is under out/, not /tmp.
set -euo pipefail

[[ $EUID -eq 0 ]] || {
	echo "Run it as root: sudo $0" >&2
	exit 1
}

# Runs a command that downloads something, up to 5 times: servers (the AUR, GitLab, keyservers,
# mirrors) often reset connections part-way
retry() {
	local try
	for try in 1 2 3 4 5; do
		"$@" && return 0
		((try < 5)) || break
		echo "$1 failed (try $try of 5); trying again in 20 s..." >&2
		sleep 20
	done
	return 1
}

here=$(cd "$(dirname "$0")" && pwd)
. "$here/config.sh"
keyring=$(cd "$here/../packaging/pkgbuilds/taris-keyring" && pwd)

base_url=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
work=$TARIS_OUT/image
dl=$work/dl
root=$work/root
mnt=$work/mnt
images=$TARIS_OUT/images
repo=$TARIS_OUT/repo

# The root filesystem's UUID is the image's (Asahi's first boot can't change a mounted btrfs's), a
# new one each build; the EFI partition's is the installer's (installer_data.json's volume_id) until
# the first boot changes it
ROOT_UUID=$(uuidgen)
EFI_UUID=2ABF-9F91
export ROOT_UUID EFI_UUID

die() {
	echo "build-image: $*" >&2
	exit 1
}

[[ -f $repo/$TARIS_REPO.db.tar.gz ]] || die "no repository: run distro/build-repo.sh first"
[[ -s $keyring/taris.gpg && -s $keyring/taris-trusted ]] || die "no signing key: run distro/make-signing-key.sh first"
retry pacman -S --needed --noconfirm arch-install-scripts btrfs-progs rsync zip dosfstools util-linux >/dev/null

clean_mounts() {
	local target
	while grep -q " ${root}[/ ]\| ${mnt}[/ ]" /proc/mounts; do
		grep -o " \(${root}\|${mnt}\)[^ ]*" /proc/mounts | sort -r | while read -r target; do
			umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null || true
		done
		sleep 0.1
	done
}
trap clean_mounts EXIT

# Arch Linux ARM's root, with Asahi's keyring and what the setup scripts need
init() {
	clean_mounts
	mkdir -p "$dl" "$mnt" "$images"
	if [[ ! -e $dl/base.tar.gz ]]; then
		echo "## Downloading Arch Linux ARM..."
		curl -fL --retry 8 --retry-all-errors --retry-delay 5 "$base_url" -o "$dl/base.tar.gz.part"
		curl -fsSL --retry 8 --retry-all-errors --retry-delay 5 "$base_url.md5" | awk '{ print $1 "  '"$dl"'/base.tar.gz.part" }' | md5sum -c - >/dev/null ||
			die "the download is damaged"
		mv "$dl/base.tar.gz.part" "$dl/base.tar.gz"
	fi
	rm -rf "$root"
	mkdir -p "$root"
	echo "## Unpacking..."
	bsdtar -xpf "$dl/base.tar.gz" -C "$root"
	mount --bind "$root" "$root"
	# Every Arch Linux ARM mirror while building (pacman moves on to the next when one fails), and
	# the downloaded packages kept between builds (a build that failed doesn't download them again)
	cp "$root/etc/pacman.d/mirrorlist" "$root/etc/pacman.d/mirrorlist.orig"
	sed -i -E 's/^#[[:space:]]*(Server = )/\1/' "$root/etc/pacman.d/mirrorlist"
	mkdir -p "$work/pkgcache"
	mount --bind "$work/pkgcache" "$root/var/cache/pacman/pkg"
	pacstrap -G "$root" asahi-alarm-keyring >/dev/null

	# For the setup scripts: their files, and the repository (pacman's [taris] while building)
	mkdir -p "$root/taris-build" "$root/taris-repo"
	cp "$here"/image/files/* "$keyring/taris.gpg" "$keyring/taris-trusted" "$root/taris-build/"
	mount --bind "$repo" "$root/taris-repo"
}

# Mounts a setup script left inside the root (a pacman hook that failed half way can leave one,
# and the next run of that hook then fails on it), but not the build's own
clean_root_mounts() {
	local target
	grep -o " ${root}/[^ ]*" /proc/mounts | sed 's/^ //' | sort -r | while read -r target; do
		case $target in "$root/taris-repo" | "$root/var/cache/pacman/pkg") continue ;; esac
		umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null || true
	done
}

run_scripts() {
	local script
	for script in "$here"/image/scripts/*.sh; do
		echo "## ${script##*/}"
		arch-chroot "$root" /bin/bash <"$script"
		clean_root_mounts
	done
}

# The pacman settings an installed system keeps: the published repository
finish_root() {
	sed -i "s|^Server = file:///taris-repo$|Server = $TARIS_REPO_SERVER|" "$root/etc/pacman.conf"
	umount "$root/taris-repo"
	umount "$root/var/cache/pacman/pkg"
	rm -rf "$root/taris-build" "$root/taris-repo"
	mv -f "$root/etc/pacman.d/mirrorlist.orig" "$root/etc/pacman.d/mirrorlist"
	rm -f "$root"/var/cache/pacman/pkg/*
}

# A command inside the image's root (mounted at $mnt), with /dev, /proc and /sys, which come off
# again straight after (arch-chroot's extra mounts, EFI variables included, can stay busy and keep
# the image mounted)
in_image() {
	local status=0
	mount --bind /dev "$mnt/dev"
	mount -t proc proc "$mnt/proc"
	mount -t sysfs sys "$mnt/sys"
	chroot "$mnt" "$@" || status=$?
	# Something the command started can still be exiting: a few tries before giving up
	local target tries
	for target in "$mnt/sys" "$mnt/proc" "$mnt/dev"; do
		for ((tries = 0; tries < 10; tries++)); do
			umount "$target" 2>/dev/null && break
			sleep 0.5
		done
		! mountpoint -q "$target" || die "$target is still busy"
	done
	return "$status"
}

# The image's filesystem must be off before it's snapshotted, checked and zipped
unmount_image() {
	sync
	umount "$mnt"
	! mountpoint -q "$mnt" || die "the image is still mounted at $mnt"
}

make_image() {
	local name="$TARIS_IMAGE_NAME" img size
	img="$images/$name"
	rm -rf "$img" "$images/$name.zip"
	mkdir -p "$img/esp/EFI/BOOT"

	echo "## Making root.img..."
	size=$(du -B M -s -x "$root" | cut -dM -f1)
	size=$((size + size / 8 + 256))
	truncate -s "${size}M" "$img/root.img"
	mkfs.btrfs -q -U "$ROOT_UUID" -L taris-root "$img/root.img"

	mount -o loop,subvolid=5 "$img/root.img" "$mnt"
	btrfs subvolume create "$mnt/@" >/dev/null
	btrfs subvolume create "$mnt/@home" >/dev/null
	unmount_image

	mount -o loop,subvol=@ "$img/root.img" "$mnt"
	rsync -aHAX --exclude /etc/machine-id --exclude '/boot/efi/*' --exclude '/tmp/*' "$root/" "$mnt/"
	# snapper's settings for the root, and its folder (a subvolume of its own)
	in_image snapper --no-dbus -c root create-config -t taris /
	in_image grub-mkconfig -o /boot/grub/grub.cfg
	unmount_image

	# The system as installed, for factory reset
	mount -o loop,subvolid=5 "$img/root.img" "$mnt"
	btrfs subvolume snapshot -r "$mnt/@" "$mnt/@factory" >/dev/null
	unmount_image
	echo "## Checking the filesystem..."
	btrfs check --readonly "$img/root.img" >/dev/null || die "root.img's filesystem has errors"

	echo "## The EFI system partition's files..."
	cp "$root/boot/grub/arm64-efi/core.efi" "$img/esp/EFI/BOOT/BOOTAA64.EFI"
	mkdir -p "$img/esp/m1n1"
	cp "$root/boot/efi/m1n1/boot.bin" "$img/esp/m1n1/boot.bin"
	# (What the Mac starts: m1n1 with the device trees and U-Boot, then GRUB)
	[[ -s $img/esp/EFI/BOOT/BOOTAA64.EFI ]] || die "GRUB's EFI file is missing"
	[[ $(stat -c %s "$img/esp/m1n1/boot.bin") -gt $(stat -c %s "$root/usr/lib/asahi-boot/m1n1.bin") ]] ||
		die "m1n1's boot image is incomplete"

	# The Mac's startup options icon (installer_data.json's "icon")
	cp "$here/image/logo.icns" "$img/logo.icns"

	echo "## Zipping..."
	(cd "$img" && zip -q -9 -r "../$name.zip" -- *)
	installer_data "$name" "$(stat -c %s "$img/root.img")"
	# The macOS command (install.sh, published with the image), pointing at this list
	sed "s|@INSTALLER_DATA@|$TARIS_IMAGE_BASE/installer_data.json|" "$here/install.sh" >"$images/install.sh"
	rm -rf "$img"
	echo "## Done: $images/$name.zip ($(du -h "$images/$name.zip" | cut -f1)), installer_data.json and install.sh"
}

# What the installer offers: TarisOS, with an EFI system partition and the root (grown to the
# space given to it)
installer_data() {
	cat >"$images/installer_data.json" <<JSON
{
  "os_list": [
    {
      "name": "TarisOS",
      "default_os_name": "TarisOS",
      "icon": "logo.icns",
      "boot_object": "m1n1.bin",
      "next_object": "m1n1/boot.bin",
      "package": "$TARIS_IMAGE_BASE/$1.zip",
      "supported_fw": ["12.3", "12.3.1", "13.5", "14.8.3"],
      "extras": {},
      "partitions": [
        {
          "name": "EFI",
          "type": "EFI",
          "size": "524288000B",
          "format": "fat",
          "volume_id": "0x2abf9f91",
          "copy_firmware": true,
          "copy_installer_data": true,
          "source": "esp"
        },
        {
          "name": "Root",
          "type": "Linux",
          "size": "${2}B",
          "expand": true,
          "image": "root.img"
        }
      ]
    }
  ]
}
JSON
}

init
run_scripts
finish_root
make_image
