# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# For the image's setup scripts (sourced): pacman, tried again when downloads fail (a mirror having
# a bad moment shouldn't end the build). Every Arch Linux ARM mirror is on while the image is
# built, so pacman also moves on to the next mirror by itself.
pacman_retry() {
	local try
	for try in 1 2 3 4 5; do
		pacman "$@" && return 0
		((try < 5)) || break
		echo "pacman failed (try $try of 5); trying again in 20 s..." >&2
		sleep 20
	done
	return 1
}
