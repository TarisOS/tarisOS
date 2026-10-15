#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Publishes the sources and licence notices (step 5 of a release), after build-repo.sh and
# build-image.sh: checks every package carries its licence text, writes the image's package list,
# uploads out/sources to the "sources" release of TarisOS/tarisOS-packages (created the first time)
# with its notes, points the "packages" release at it, and writes out/source-offer.md for the
# image's release notes.
# Usage: distro/publish-sources.sh <image version, e.g. 1.0.0>
set -euo pipefail

V="${1:?usage: $0 <image version, e.g. 1.0.0>}"
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.."
R=TarisOS/tarisOS-packages

# Licence texts: a line only for a package missing one
for p in distro/out/repo/*.pkg.tar.xz; do
	lic=$(bsdtar -xOf "$p" .PKGINFO | awk '/^license/ { print $3 }')
	grep -qE 'MIT|BSD|Apache|OFL|custom|LicenseRef' <<<"$lic" || continue
	bsdtar -tf "$p" | grep -q '^usr/share/licenses/..*/.' || echo "no licence text: $p ($lic)"
done

# The image's package list, and the notes
pacman -Qi --dbpath distro/out/image/root/var/lib/pacman |
	awk -F' *: ' '/^Name/ { n = $2 } /^Version/ { v = $2 } /^Licenses/ { print n " " v "  " $2 }' \
	>"distro/out/sources/tarisos-$V-image-packages.txt"
ver() { bsdtar -xOf distro/out/repo/"$1"-[0-9]*.pkg.tar.xz .PKGINFO | awk '/^pkgver/ { sub(/-[^-]*$/, "", $3); print $3 }'; }
nord=$(ver nordvpn-bin)
tor=$(ver tor-browser-bin)
cat >distro/out/sources-notes.md <<EOF
Source code for TarisOS's package repository (the [packages](https://github.com/$R/releases/tag/packages) release) and installer images ([TarisOS/tarisOS](https://github.com/TarisOS/tarisOS/releases)).

- **TarisOS's own code:** https://github.com/TarisOS/tarisOS
- **Every package built from source:** its \`.src.tar.gz\` below: its PKGBUILD, TarisOS's patches and the upstream source at the version built (\`makepkg\` builds it once unpacked).
- **nordvpn-bin $nord:** https://github.com/NordSecurity/nordvpn-linux/tree/$nord
- **tor-browser-bin $tor:** https://archive.torproject.org/tor-package-archive/torbrowser/$tor/
- **Installer images:** \`tarisos-<version>-image-packages.txt\` lists every package in that image, with its version and licence. For three years after an image was last published, anyone can have the complete corresponding source of the GPL and LGPL software in it: ask in this repository's issues (https://github.com/$R/issues).
EOF
cat >distro/out/source-offer.md <<EOF
## Source code

TarisOS's own code is in this repository. The source of every package TarisOS builds, the list of every package in the image with its licence, and the written offer of the source of the rest of its GPL software are in the [sources release](https://github.com/$R/releases/tag/sources) of $R.
EOF

# Upload
if ! gh release view sources -R "$R" >/dev/null 2>&1; then
	gh release create sources -R "$R" --target main --latest=false --title "TarisOS sources" --notes-file distro/out/sources-notes.md
fi
gh release edit sources -R "$R" --notes-file distro/out/sources-notes.md >/dev/null
gh release upload sources -R "$R" --clobber distro/out/sources/*
gh release edit packages -R "$R" --notes "TarisOS package repository. Source code: https://github.com/$R/releases/tag/sources" >/dev/null

# Check
missing=$(comm -13 <(gh release view sources -R "$R" --json assets --jq '.assets[].name' | sort) <(ls distro/out/sources | sort))
if [[ -z $missing ]]; then
	echo "Done: every source is in the release"
else
	echo "Missing from the release:"
	echo "$missing"
	exit 1
fi
