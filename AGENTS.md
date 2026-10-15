# Task Guides

Deeper instructions for specific kinds of work live in `agents/skills/`. Read the matching guide before starting:

- [`agents/skills/shell-dev.md`](agents/skills/shell-dev.md) - editing the Taris shell under `shell/` (QML, the C++ plugin, its helper scripts)
- [`agents/skills/packaging.md`](agents/skills/packaging.md) - working under `packaging/` (PKGBUILDs, the helpers in `/usr/lib/taris`, pacman hooks, install scripts, the Hyprland config TarisOS ships)
- [`agents/skills/upgrades.md`](agents/skills/upgrades.md) - changing something on machines that are already installed
- [`agents/skills/distro-image.md`](agents/skills/distro-image.md) - working under `distro/` (the package repository, the installer image, the macOS install command) and testing whole installs
- [`agents/skills/visual-verification.md`](agents/skills/visual-verification.md) - verifying any change with a visual effect in the running UI
- [`agents/skills/icons.md`](agents/skills/icons.md) - adding or changing icons, logos and brand marks

# Working Rules

These rules come before everything else in this file. You run on a user's own TarisOS install: the machine is their desktop, and the person you work with is that user.

- Do exactly what is asked: nothing less, nothing more. Never add behaviour, restrictions or "while I'm here" changes nobody asked for. When something is unclear, ask, but first re-read the conversation: never ask what the user already answered.
- No git commands at all (not even `git status`, `git log` or `git diff`) unless the user explicitly says so for that step. When asked to commit: atomic commits (one coherent change each), with succinct messages that describe the change.
- Find causes from evidence before changing anything: logs (`taris shell -l`, `journalctl`), live state (`hyprctl -j clients`, `hyprctl getoption`), the source of Hyprland and Quickshell at the exact versions installed, and the user's screenshots and recordings. Do not ship guesses; say plainly when something is still unexplained.
- No explanation text in the UI: labels and controls only.
- Shell features are core distro components: trace focus grabs, layers, keyboard focus, timing and edge cases, and reread the whole file before handing a change over.
- Prefer the simplest fix that solves the problem without breaking anything else. When something can be fixed directly and quickly, do that instead of building an elaborate mechanism around it or investigating causes that don't change the fix.
- Before making any change, consider whether it could break anything or introduce new bugs: trace what it touches (the code that depends on it, and how the shell, Quickshell and Hyprland at the installed versions react to it) and say what it could affect. Don't make a change you haven't checked this way.
- This machine is the user's own desktop. Do not kill or restart the shell or Hyprland, remove packages or delete large things without saying so first; hand over the command when a step needs the user's password, or run it with `pkexec` so the prompt appears on their screen.
- Code for TarisOS on plain Asahi Linux only. Nothing for other hardware.
- Every new source file starts with the copyright and licence header the existing files carry (`Copyright (C) 2026 George Dobreff ("Witcher") and contributors`, `SPDX-License-Identifier: GPL-3.0-only`).
- `/tmp` is RAM: no big builds there. Use the git-ignored `shell/build/` or a package's own folder.

# Documentation Layout

Documentation is split by genre and audience:

- `agents/skills/` - task procedure ("do this when doing X"), for anyone working on the codebase
- `README.md` - the user manual and the build instructions, published; never codebase internals beyond the repository layout
- `packaging/agents/skills/` - skills for the coding agents of TarisOS users (installed by `taris-desktop`): end-user customization of an installed system, never TarisOS development

# Style

- In markdown documents, wrap lines at 100 columns as the existing documents do; break earlier only at structural boundaries like headings and list items.
- Indentation follows the file: tabs in the scripts under `packaging/pkgbuilds/` and `distro/`, four spaces in TarisOS's own PKGBUILDs (`taris*`) and in QML, C++ and Python, two spaces in the scripts at the repository root and under `shell/assets/`. PKGBUILDs based on other people's keep their own. Never mix them in one file.
- Use bash conditionals: `[[ ]]` for string and file tests and `(( ))` for numeric tests.
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g. `[[ $mode == "auto" ]]`).
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g. `(( count < 50 ))`, not `[[ $count -lt 50 ]]`).
- Prefer a full `if`/`else` for simple two-path control flow; don't rely on `exec` or `exit` in one branch to make the following statements unreachable.
- Quote strings and paths with spaces instead of escaping the spaces.
- Shebangs: `#!/bin/bash` for bash (never `#!/usr/bin/env bash`); `#!/bin/sh` only for scripts that must stay POSIX (the greeter's, run before anything of the user's), `#!/usr/bin/ash` for initramfs hooks, `#!/usr/bin/python3 -I` for root helpers in Python.
- Python runs isolated (`python3 -I`), from the shell and from scripts.
- Comments say why, in plain sentences; every script and helper starts with the header and a comment saying what it does, who runs it and its usage lines.
- British spelling in the shell's names and text (`Colours`, `colour`), as the code already has.

# Naming

Everything is `taris`: packages are `taris-*`, helpers are `/usr/lib/taris/<name>`, shared data is `/usr/share/taris/`, the shell is installed to `/etc/xdg/quickshell/taris` and runs on `quickshell-taris` as `taris-qs`, its QML modules are `Taris.*` and its global shortcuts `taris:<name>`. Per-user files are `~/.config/taris/`, `~/.local/state/taris/` and `~/.cache/taris/`.

Links to the old repositories (`caelestia-dots/*`, `xxwitcher/caelestia-silicon`), the upstream CLI tarball, `shell/NOTICE` and the README's credits keep their names on purpose.

# Runtime Environment

- The shell finds its own files through `Quickshell.shellDir` / `Quickshell.shellPath()` and the `Paths` singleton (`shell/utils/Paths.qml`); never hard-code `/etc/xdg/quickshell/taris` in QML.
- Helpers and packaged scripts use their absolute installed paths (`/usr/lib/taris/...`, `/usr/share/taris/...`).
- Hyprland's config is Lua: TarisOS's is `/usr/share/taris/hypr/hyprland.lua` and `taris.lua` (from `packaging/hypr/`), loaded by each account's `~/.config/hypr/hyprland.lua` stub, with the account's own `user.lua` last.

# Privileged Commands

Follow the "Privilege Escalation" section of `packaging/agents/skills/asahi-desktop/SKILL.md`, and the repo's own code follows it too: `sudo` when the caller has a terminal to enter a password in, `pkexec` when it does not. The shell is the session's polkit agent (`shell/modules/polkit/`). An account locks for 10 minutes after 10 failed passwords: never retry a failing one.

# Helper Commands

Use these instead of reimplementing what they do:

- `/usr/lib/taris/update` - update everything (repositories, AUR, Flatpak)
- `/usr/lib/taris/install-on-demand <app>` - install an app that is installed on first use, then open it
- `/usr/lib/taris/input-method add|remove zh|ja|ko` - CJK typing
- `/usr/lib/taris/tor on|off|status` - everything through Tor (the taskbar's Tor icon)
- `/usr/lib/taris/user-defaults [--if-new]` - a new account's defaults
- `/usr/lib/taris/chromium-flags` - Chromium's settings for the account
- `/usr/lib/taris/build-hyprbars [--check|--force]` - the title bar plugin for the installed Hyprland
- `taris` (the CLI: `scheme`, `wallpaper`, `screenshot`, `record`, `shell`) and `taris-qs -c taris ipc call <target> <function>`
- `notify-send -a TarisOS` for notifications from scripts

Commands installed by TarisOS's own packages and the default apps (`distro/image/scripts/40-taris.sh`) are runtime invariants. Invoke them directly; do not add defensive `command -v` checks around them. Check only for genuinely optional programs (`fprintd`, `wtype`, an agent the user hasn't installed) or code that can run before the packages are installed (`install.sh`, the image build).

# Settings App

- The pages are listed in `shell/modules/nexus/PageRegistry.qml` and built in `shell/modules/nexus/PageCompRegistry.qml`, in the same order; keep both in step.
- `shell/modules/nexus/SettingsIndex.qml` is generated by `shell/scripts/settings-index.py` (`install.sh` and `distro/build-repo.sh` run it). Never edit it by hand; run the script after changing a page's options.

# Config Structure

- `packaging/hypr/` - the Hyprland config every account loads (installed by `taris-desktop`)
- `packaging/defaults/` - the Taris theme, the preinstalled web apps and the logo's icon sizes
- `shell/plugin/src/Taris/Config/*.hpp` - the shell's config options and their defaults (`~/.config/taris/shell.json` overrides them); a changed default needs the plugin rebuilt
- `packaging/pkgbuilds/taris-desktop/user-defaults` - what a new account starts with

# Tests

There is no automated test suite yet. Until there is one, run the checks for the area you changed, and report their output; [`agents/skills/shell-dev.md`](agents/skills/shell-dev.md) and [`agents/skills/packaging.md`](agents/skills/packaging.md) list them. The shell's own checkers (`shell/scripts/qml-lint-conventions.py`, `shell/scripts/trs-check.py`) already report problems in files nobody touched: run them on the files you changed (`--file`), and leave none of your own.

Run anything that touches an account's files against a throwaway home, never the user's (see [`agents/skills/upgrades.md`](agents/skills/upgrades.md)).

Visual changes must be verified in the running UI in addition to these checks; follow [`agents/skills/visual-verification.md`](agents/skills/visual-verification.md). Whole-install changes (login, setup screen, encryption, factory reset, the image) need a fresh image; see [`agents/skills/distro-image.md`](agents/skills/distro-image.md).

# Refresh Pattern

- An account's Hyprland stub: `./install-hypr.sh` (keeps a backup of an existing `~/.config/hypr/hyprland.lua`).
- An account's agent skills: `./install-agent-skills.sh`.
- The shell and the desktop packages from this checkout on this machine: `./install.sh` (it restarts the shell: say so before running it).
