#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Unloads the draft read-only SMC key reader loaded by test-install.sh. The saved results/ stay.
# Run by the maintainer, as root:
#   sudo dev/power/smc-keys/test-revert.sh

set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
if [[ -d /sys/module/taris_smc_keys ]]; then
  rmmod taris_smc_keys
  echo "Unloaded taris_smc_keys."
else
  echo "taris_smc_keys isn't loaded; nothing to do."
fi
