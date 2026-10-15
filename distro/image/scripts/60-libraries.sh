#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Every program and library from TarisOS's own packages finds the libraries it needs. One built
# against a library the image has another version of installs fine and then doesn't start (the
# shell's services against libcava.so.2, with libcava.so.1 in the image: no setup screen, greeter
# or shell).
set -euo pipefail

mapfile -t ours < <(comm -12 <(pacman -Sql taris | sort -u) <(pacman -Qq | sort -u))
((${#ours[@]})) || { echo "none of TarisOS's packages are installed" >&2; exit 1; }

broken=0
while read -r file; do
	[[ -f $file && ! -L $file ]] || continue
	[[ $(od -An -tx1 -N4 "$file" 2>/dev/null | tr -d ' \n') == 7f454c46 ]] || continue
	missing=$(ldd "$file" 2>/dev/null | awk '/not found/ { print $1 }') || true
	[[ -n $missing ]] || continue
	echo "$file needs $(echo $missing), which isn't in the image" >&2
	broken=1
done < <(pacman -Qlq "${ours[@]}")
((broken == 0)) || exit 1
echo "Libraries: all found (${#ours[@]} TarisOS packages)"
