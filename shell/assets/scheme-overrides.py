#!/usr/bin/env python3
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

"""Colours picked one by one in Settings > Wallpaper & style > Colours, on top of the scheme.

The overrides are kept per scheme (name, flavour and mode) in ~/.config/taris/colour-overrides.json:

    {"overrides": {"gruvbox soft dark": {"primary": "a46a32", "surface": "282828"}}}

This takes the current scheme's own colours again (the taris CLI's, so a colour no longer
overridden goes back to the scheme's), puts the overrides for it on top, saves the scheme and
themes everything the CLI themes with it (terminals, Hyprland, GTK, Qt...). The shell runs it when
a colour is picked or reset, and after the CLI switches scheme.
"""

import fcntl
import json
import os
import shutil
import subprocess
from pathlib import Path

from taris.utils import theme
from taris.utils.paths import c_state_dir
from taris.utils.scheme import get_scheme
from taris.utils.theme import apply_colours


def apply_chromium(colours: dict[str, str]) -> None:
    """The CLI's browser theming without its `<browser> --refresh-platform-policy`, which hands the
    running browser a command line and can take focus (closing the settings it was picked in);
    the browsers reload their policy folder by themselves when the file changes."""
    browsers = [
        ("chromium", "/etc/chromium/policies/managed"),
        ("brave", "/etc/brave/policies/managed"),
        ("google-chrome-stable", "/etc/opt/chrome/policies/managed"),
    ]
    policy = json.dumps({"BrowserThemeColor": f"#{colours['surface']}", "BrowserColorScheme": "device"})
    for cmd, policy_dir in browsers:
        if shutil.which(cmd) is None or not Path(policy_dir).is_dir():
            continue
        subprocess.run(
            ["sudo", "-n", "tee", f"{policy_dir}/taris.json"],
            input=policy,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


theme.apply_chromium = apply_chromium

config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "taris"
overrides_path = config / "colour-overrides.json"

try:
    overrides = json.loads(overrides_path.read_text()).get("overrides", {})
except (OSError, json.JSONDecodeError, AttributeError):
    overrides = {}

scheme = get_scheme()
scheme._update_colours()  # The scheme's own colours
picked = overrides.get(f"{scheme.name} {scheme.flavour} {scheme.mode}", {})
# Names that aren't scheme colours (shell:...) only change the shell, which applies them itself
for name, colour in picked.items():
    if name in scheme.colours:
        scheme.colours[name] = colour.lstrip("#").lower()
scheme.save()

# The CLI themes apps under a lock and skips when it's held: right after a scheme switch it still
# is, so wait for it to finish first
lock_file = c_state_dir / "theme.lock"
c_state_dir.mkdir(parents=True, exist_ok=True)
with open(lock_file, "w") as lock_fd:
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)

apply_colours(scheme.colours, scheme.mode)
