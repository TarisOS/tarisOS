#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Builds TarisOS's package repository on this Mac (Apple Silicon, aarch64): this repository's
# PKGBUILDs and the AUR's (config.sh), each signed with the TarisOS key (make-signing-key.sh), into
# out/repo with the signed package list; and the source of every package built from source (the
# GPL asks for it next to the binaries) into out/sources. A package that a later one needs to build
# is installed here once it's built (pacman asks for the password).
#
# Then upload out/repo (every package and its .sig) to the GitHub release config.sh's
# TARIS_REPO_SERVER points at, and the package list as the names pacman asks for: release assets
# can't be links, so taris.db and taris.files (and their .sig) are copies of the .tar.gz files.
#
#   build-repo.sh              everything
#   build-repo.sh <pkg>...     just these (then the package list again)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/config.sh"
pkgbuilds=$(cd "$here/../packaging/pkgbuilds" && pwd)
repo=$TARIS_OUT/repo
sources=$TARIS_OUT/sources
aur=$TARIS_OUT/aur
mkdir -p "$repo" "$sources" "$aur"

# Built here and needed installed by a later build
needed_to_build=(libcava)

die() {
	echo "build-repo: $*" >&2
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

key=$(cut -d: -f1 "$pkgbuilds/taris-keyring/taris-trusted" 2>/dev/null || true)
[[ -n $key ]] && gpg --list-secret-keys "$key" >/dev/null 2>&1 ||
	die "no signing key: run distro/make-signing-key.sh first"
export GPGKEY=$key

# No transparent huge pages for malloc (the Asahi kernel has none): asking for them fails with
# EINVAL, which glibc leaves in errno, and CMake takes that for a failed directory read, so a
# lookup in /usr/lib (a library, a Qt module) fails now and then
export GLIBC_TUNABLES=glibc.malloc.hugetlb=0

is_ours() {
	local p
	for p in "${TARIS_PACKAGES[@]}" "${TARIS_AUR_PACKAGES[@]}"; do
		[[ $p == "$1" ]] && return 0
	done
	return 1
}

# What a PKGBUILD needs to build and isn't installed: from the official repositories (ours have to
# be built and installed before it)
install_build_deps() {
	local deps missing=() dep
	deps=$(makepkg --printsrcinfo | awk -F' = ' '/^\t(makedepends|depends|checkdepends) = / { print $2 }' | sort -u)
	[[ -n $deps ]] || return 0
	# shellcheck disable=SC2086
	for dep in $(pacman -T $deps || true); do
		if is_ours "${dep%%[<>=]*}"; then
			continue # runtime only (installed together on TarisOS); build-time ones are in needed_to_build
		fi
		missing+=("$dep")
	done
	((${#missing[@]} == 0)) || retry sudo pacman -S --needed --asdeps "${missing[@]}"
}

# This machine's pacman trusts the TarisOS key (as TarisOS systems do through taris-keyring), so
# the signed packages built here install here too (once)
trusted=0
trust_key() {
	((trusted)) && return 0
	if ! sudo pacman-key --list-keys "$key" >/dev/null 2>&1; then
		sudo pacman-key --add "$pkgbuilds/taris-keyring/taris.gpg"
		sudo pacman-key --lsign-key "$key"
	fi
	trusted=1
}

pkgname_of() {
	bsdtar -xOf "$1" .PKGINFO | sed -n 's/^pkgname = //p'
}

# A package into the repository folder, instead of any other version of it there
replace_in_repo() {
	local new="$1" name old
	name=$(pkgname_of "$new")
	for old in "$repo"/*.pkg.tar.*; do
		[[ -e $old && $old != *.sig ]] || continue
		if [[ $(pkgname_of "$old") == "$name" ]]; then
			rm -f "$old" "$old.sig"
		fi
	done
	cp -f "$new" "$new.sig" "$repo/"
}

build_in() {
	local dir="$1" name="$2" file
	echo "==> $name"
	(
		cd "$dir"
		rm -f ./*.pkg.tar.* ./*.src.tar.gz
		install_build_deps
		# The keys a package's download is signed with (keys/pgp, Arch's convention), for makepkg to
		# check it against
		if [[ -d keys/pgp ]]; then
			gpg --quiet --import keys/pgp/*.asc
		fi
		# The keys its PKGBUILD trusts (validpgpkeys: an AUR package's carry no keys/pgp), from a
		# keyserver when they aren't in the keyring yet
		local fpr
		for fpr in $(makepkg --printsrcinfo | awk -F' = ' '/^\tvalidpgpkeys = / { print $2 }'); do
			gpg --list-keys "$fpr" >/dev/null 2>&1 ||
				retry gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$fpr" ||
				retry gpg --keyserver hkps://keys.openpgp.org --recv-keys "$fpr" ||
				die "couldn't get the key $fpr that $name's download is signed with"
		done
		# Its sources first, on their own, so a dropped download is retried instead of failing the build
		retry makepkg --verifysource -f -d ||
			die "couldn't download $name's sources"
		makepkg -f -d --sign --noconfirm
		# The source, for packages built from it (not for repackaged binaries, *-bin)
		if [[ $name != *-bin ]]; then
			makepkg --allsource -f -d >/dev/null
			mv -f ./*.src.tar.gz "$sources/"
		fi
		for file in ./*.pkg.tar.*; do
			[[ $file == *.sig ]] && continue
			replace_in_repo "$file"
		done
	)
	local n built=()
	for n in "${needed_to_build[@]}"; do
		if [[ $n == "$name" ]]; then
			for file in "$dir"/*.pkg.tar.*; do
				[[ $file == *.sig ]] || built+=("$file")
			done
			trust_key
			# Even at the version installed already: what's built next has to be built against
			# exactly what ships (a same-version build from elsewhere can differ: libcava.so.2)
			sudo pacman -U --noconfirm "${built[@]}"
		fi
	done
}

# An AUR package: its current PKGBUILD fetched, shown for review when it changed since the last
# one built, then built like ours
build_aur() {
	local name="$1" new cur answer
	new="$aur/$name.new"
	cur="$aur/$name"
	rm -rf "$new"
	mkdir -p "$new"
	# To a file with retries: the AUR often resets connections part-way, and a stream into tar can't retry
	curl -fsSL --retry 8 --retry-all-errors --retry-delay 5 -o "$new.tar.gz" \
		"https://aur.archlinux.org/cgit/aur.git/snapshot/$name.tar.gz" &&
		tar -xzf "$new.tar.gz" -C "$new" --strip-components=1 ||
		die "couldn't fetch $name from the AUR"
	rm -f "$new.tar.gz"
	if [[ -d $cur ]] && diff -r -q -x '*.pkg.tar.*' -x src -x pkg -x '*.deb' -x '*.tar.*' "$cur" "$new" >/dev/null 2>&1; then
		rm -rf "$new"
	else
		if [[ -d $cur ]]; then
			diff -ru -x '*.pkg.tar.*' -x src -x pkg -x '*.deb' -x '*.tar.*' "$cur" "$new" | ${PAGER:-less} || true
		else
			${PAGER:-less} "$new/PKGBUILD"
		fi
		read -rp "Build $name from this PKGBUILD? [y/N] " answer
		[[ $answer == [Yy]* ]] || die "$name not built"
		rm -rf "$cur"
		mv "$new" "$cur"
	fi
	build_in "$cur" "$name"
}

build() {
	local name="$1" p
	# The settings search's index, up to date with the settings pages
	if [[ $name == taris-shell ]]; then
		python3 -I "$pkgbuilds/../../shell/scripts/settings-index.py" || die "the settings search index couldn't be made"
	fi
	for p in "${TARIS_AUR_PACKAGES[@]}"; do
		[[ $p == "$name" ]] && { build_aur "$name"; return; }
	done
	[[ -d $pkgbuilds/$name ]] || die "no such package: $name"
	build_in "$pkgbuilds/$name" "$name"
}

if (($#)); then
	for name in "$@"; do build "$name"; done
else
	for name in "${TARIS_PACKAGES[@]}" "${TARIS_AUR_PACKAGES[@]}"; do build "$name"; done
fi

# The package list (signed): every package in the folder (one version of each)
echo "==> The package list"
rm -f "$repo/$TARIS_REPO".{db,files}{,.tar.gz,.sig,.tar.gz.sig,.tar.gz.old,.tar.gz.old.sig}
shopt -s nullglob
packages=()
for file in "$repo"/*.pkg.tar.*; do
	[[ $file == *.sig ]] || packages+=("$file")
done
repo-add --sign --key "$key" "$repo/$TARIS_REPO.db.tar.gz" "${packages[@]}"
echo "Done: $repo (and the sources in $sources)."
