#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Builds a program of Asahi's repository with TarisOS's patches, for the version installed, so the
# patches follow every version Asahi releases without a new TarisOS package. Asahi's own package
# stays installed; this builds its binary again from Asahi's own packaging for that exact version
# (asahi-alarm/PKGBUILDs: their sources, checksums and patches) with TarisOS's patches applied on
# top, and keeps it in /var/lib/taris/asahi-package/<package>/. The program's service runs it in
# place of the stock binary through a systemd drop-in (a bind mount over it) only while there's
# one for the installed version: otherwise the stock binary runs. A patch the source already has is
# skipped; one that doesn't apply stops the build, and the stock binary stays; so does it without a
# network (the next install or upgrade of the package tries again). Applied again, nothing changes:
# a build for the same version and patches is kept. Run as root by the package's pacman hook
# (90-taris-<package>.hook) after the package or TarisOS's is installed or upgraded; the build
# itself runs as nobody (makepkg). The same script is in speakersafetyd-taris and tiny-dfr-taris;
# what each needs is in its asahi-package.conf, next to it.
# Usage: asahi-package.sh

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=https://github.com/asahi-alarm/PKGBUILDs.git
# pkg: Asahi's package; binary: the file in /usr/bin it builds; patches: TarisOS's, in order,
# against the program's source
source "$here/asahi-package.conf"

state=/var/lib/taris/asahi-package/$pkg
current=$state/current
log() {
	echo "asahi-package: $pkg: $*" >&2
}

# The stock binary until a build for this version exists
installed=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
if [[ -z $installed ]]; then
	log "not installed"
	rm -f "$current"
	exit 0
fi
stamp=$(cat "${patches[@]/#/$here/}" | sha256sum | cut -c1-12)
build=$state/$installed-$stamp
if [[ -x $build/$binary ]]; then
	ln -sfn "$build/$binary" "$current"
	exit 0
fi
rm -f "$current"

work=$(mktemp -d /var/cache/taris-asahi-package.XXXXXX)
trap 'rm -rf "$work"' EXIT
chown nobody: "$work"
as_nobody() {
	runuser -u nobody -- env HOME="$work" CARGO_HOME="$work/cargo" BUILDDIR="$work/build" \
		SRCDEST="$work/sources" PKGDEST="$work/pkgs" "$@"
}

# Asahi's packaging for the package, as it is in their repository now
if ! as_nobody git -c advice.detachedHead=false clone -q --depth 1 --filter=blob:none --sparse \
	"$repo" "$work/pkgbuilds" || ! as_nobody git -C "$work/pkgbuilds" sparse-checkout set "$pkg"; then
	log "Asahi's packaging couldn't be fetched: the stock binary stays"
	exit 0
fi
dir=$work/pkgbuilds/$pkg
# makepkg's own folders for it (BUILDDIR set: not next to the PKGBUILD)
srcdir=$work/build/$pkg/src
pkgdir=$work/build/$pkg/pkg/$pkg
theirs=$(as_nobody bash -c 'source "$1"; echo "${epoch:+$epoch:}$pkgver-$pkgrel"' _ "$dir/PKGBUILD")
if [[ $theirs != "$installed" ]]; then
	log "Asahi's packaging is at $theirs, $installed is installed: the stock binary stays"
	exit 0
fi

# Their sources, checksums and prepare() (their own patches), then TarisOS's on top
if ! (cd "$dir" && as_nobody makepkg --nodeps --nobuild --noconfirm >"$work/makepkg.log" 2>&1); then
	log "Asahi's sources couldn't be prepared (see makepkg's output below): the stock binary stays"
	tail -n 20 "$work/makepkg.log" >&2
	exit 0
fi
mapfile -t sources < <(find "$srcdir" -mindepth 1 -maxdepth 1 -type d)
if (( ${#sources[@]} != 1 )); then
	log "no single source folder in Asahi's build: the stock binary stays"
	exit 0
fi
for patch in "${patches[@]}"; do
	if as_nobody patch -d "${sources[0]}" -p1 -R -f -s --dry-run <"$here/$patch" >/dev/null 2>&1; then
		log "$installed already has $patch"
	elif as_nobody patch -d "${sources[0]}" -p1 -N -f -s --dry-run <"$here/$patch" >/dev/null 2>&1; then
		as_nobody patch -d "${sources[0]}" -p1 -N -f -s <"$here/$patch"
		log "$patch applied to $installed"
	else
		log "$patch doesn't apply to $installed: the stock binary stays"
		exit 0
	fi
done

# Their build() and package(), into a folder only (no package file)
if ! (cd "$dir" && as_nobody makepkg --nodeps --noextract --noarchive --noconfirm >"$work/makepkg.log" 2>&1); then
	log "the build failed (see makepkg's output below): the stock binary stays"
	tail -n 20 "$work/makepkg.log" >&2
	exit 0
fi
built=$pkgdir/usr/bin/$binary
if [[ ! -x $built ]]; then
	log "the build left no /usr/bin/$binary: the stock binary stays"
	exit 0
fi

mkdir -p "$build"
install -m755 "$built" "$build/$binary"
ln -sfn "$build/$binary" "$current"
# Only the build for the installed version and patches is kept
for old in "$state"/*/; do
	[[ ${old%/} == "$build" ]] || rm -rf "$old"
done
log "built for $installed with TarisOS's patches; used from the service's next start"
