#!/usr/bin/env sh
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

cat ~/.local/state/taris/sequences.txt 2>/dev/null

exec "$@"
