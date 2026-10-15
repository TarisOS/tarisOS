#!/bin/sh
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# TarisOS's installer, run in macOS: curl -fsSL https://github.com/TarisOS/tarisOS/releases/latest/download/install.sh | sh
# Starts the TarisOS installer with TarisOS's list of systems to install (installer_data.json).
# The installer is Asahi Linux's (its Arch Linux ARM build), named TarisOS and with TarisOS chosen
# for the user (the only system it offers). It makes room next to macOS, installs TarisOS there
# and walks through Apple's step of allowing it to start (in recoveryOS).

# Nothing runs unless the whole script arrived
if true; then
	set -e

	if [ ! -e /System ]; then
		echo "TarisOS is installed from macOS (on an Apple Silicon Mac): run this in macOS's Terminal."
		exit 1
	fi
	if [ "$(uname -m)" != arm64 ]; then
		echo "TarisOS is for Apple Silicon Macs (M1, M2) only."
		exit 1
	fi
	if ! curl --no-progress-meter file:/// >/dev/null 2>&1; then
		echo "This Mac's macOS is too old: the installer needs macOS 13.5 or newer."
		exit 1
	fi

	export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
	export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

	# The installer (Asahi's Arch Linux ARM build, a fixed version: the changes below are made to
	# that version's text) and TarisOS's list for it. No install report: it'd go to Asahi Linux.
	installer_version=v0.9.2
	export INSTALLER_BASE=https://asahi-alarm.org
	export REPO_BASE=https://asahi-alarm.org
	export INSTALLER_DATA=@INSTALLER_DATA@
	export DISTRO=TarisOS
	export DISTRO_DOCS=https://github.com/TarisOS/tarisOS

	tmp=/tmp/tarisos-install
	[ -e "$tmp" ] && mv "$tmp" "$tmp-$(date +%Y%m%d-%H%M%S)"
	mkdir -p "$tmp"
	cd "$tmp"

	echo
	echo "Getting the installer..."
	package="installer-$installer_version.tar.gz"
	curl --no-progress-meter -fL -o "$package" "$INSTALLER_BASE/$package"
	if ! curl --no-progress-meter -fL -o installer_data.json "$INSTALLER_DATA"; then
		echo "TarisOS's installer list couldn't be downloaded (is GitHub reachable from here?)."
		exit 1
	fi
	tar xf "$package"

	# TarisOS's name instead of Asahi Linux's and "the new OS", and TarisOS chosen without asking
	sed -i '' \
		-e 's/Asahi Linux developers/TarisOS developers/' \
		-e 's/the Asahi Linux Blog/TarisOS'"'"'s page/' \
		-e 's|https://asahilinux.org/blog/|https://github.com/TarisOS/tarisOS|' \
		-e 's/Install an OS into free space/Install TarisOS in the free space/' \
		-e 's/Install an OS into an existing APFS container/Install TarisOS into an existing APFS container/' \
		-e 's/Resize an existing partition to make space for a new OS/Resize an existing partition to make space for TarisOS/' \
		-e 's/Minimum required space for this OS:/Minimum required space for TarisOS:/' \
		-e 's/There is not enough free space to install this OS./There is not enough free space to install TarisOS./' \
		-e 's/How much space should be allocated to the new OS?/How much space should be allocated to TarisOS?/' \
		-e 's/"New OS size"/"TarisOS size"/' \
		-e 's/The new OS will be allocated/TarisOS will be allocated/' \
		-e 's/Enter a name for your OS/Enter a name for TarisOS (shown in the startup options)/' \
		-e 's/OS name (/Name (/' \
		-e 's/Preparing the new OS for booting/Preparing TarisOS for booting/' \
		-e 's/Setting the new OS as the default boot volume/Setting TarisOS as the default boot volume/' \
		-e 's/To be able to boot your new OS,/To be able to boot TarisOS,/' \
		-e 's/70% to the new OS/70% to TarisOS/' \
		-e 's/the rest to your new OS/the rest to TarisOS/' \
		-e 's/enough free space for an OS install./enough free space for TarisOS./' \
		-e 's/^\( *\)p_question("Choose an OS to install:")$/\1if len(os_list) != 1: p_question("Choose an OS to install:")/' \
		-e 's/^\( *\)idx = self.choice("OS", \[i\["name"\] for i in os_list\])$/\1idx = 0 if len(os_list) == 1 else self.choice("OS", [i["name"] for i in os_list])/' \
		main.py
	sed -i '' 's/Asahi Linux only supports/TarisOS only supports/' install.sh
	sed -i '' \
		-e 's/the OS which you are/TarisOS, which you are/' \
		-e 's/sets up your new OS as/sets up TarisOS as/' \
		step2/step2.sh
	if ! grep -q 'idx = 0 if' main.py || ! grep -q "TarisOS's page" main.py || ! grep -q 'TarisOS in the free space' main.py || grep -qE 'Asahi Linux (dev|only)|(new|this|your) OS[ ,.?"]|an OS (into|install)' main.py install.sh step2/step2.sh; then
		echo "The installer couldn't be prepared for TarisOS."
		exit 1
	fi

	echo
	if [ "$(id -u)" != 0 ]; then
		echo "The installer runs as the administrator: enter your macOS password if asked."
		exec caffeinate -dis sudo -E ./install.sh "$@"
	else
		exec caffeinate -dis ./install.sh "$@"
	fi
fi
