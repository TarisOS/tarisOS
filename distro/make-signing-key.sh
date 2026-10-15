#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# TarisOS's package signing key, made once in your own GnuPG keyring on the machine that builds
# the repository (GnuPG asks for a passphrase to protect it). Its public half goes into
# packaging/pkgbuilds/taris-keyring, which installed systems trust it through. Run it again to
# re-export an existing key. Back up the private key (the command is printed at the end): losing it
# means every installed system has to be told to trust a new one.
set -euo pipefail

uid="TarisOS Packages <packages@tarisos.com>"
keyring="$(cd "$(dirname "$0")/.." && pwd)/packaging/pkgbuilds/taris-keyring"

# (gpg fails when there's no such key yet: that's an empty answer, not the end of the script)
fingerprint() {
	{ gpg --list-secret-keys --with-colons "=$uid" 2>/dev/null || true; } | awk -F: '$1 == "fpr" { print $10; exit }'
}

fpr=$(fingerprint)
if [[ -z $fpr ]]; then
	echo "Making the TarisOS signing key ($uid)…"
	gpg --quick-generate-key "$uid" ed25519 sign never
	fpr=$(fingerprint)
fi
[[ -n $fpr ]] || {
	echo "The key wasn't made." >&2
	exit 1
}

gpg --export "$fpr" >"$keyring/taris.gpg"
echo "$fpr:4:" >"$keyring/taris-trusted"
: >"$keyring/taris-revoked"
(cd "$keyring" && updpkgsums >/dev/null)

echo "Signing key: $fpr"
echo "Its public half is in $keyring."
echo "Back up the private key somewhere safe, e.g.:"
echo "  gpg --export-secret-keys --armor $fpr > tarisos-signing-key.asc"
