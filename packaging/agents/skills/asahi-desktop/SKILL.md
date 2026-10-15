---
name: asahi-desktop
description: >
  REQUIRED for end-user customization of this TarisOS desktop (Arch Linux ARM on Apple Silicon /
  Asahi Linux, Hyprland, the Taris shell). Use when editing ~/.config/hypr/, ~/.config/kitty/,
  ~/.config/foot/, ~/.config/alacritty/, ~/.config/ghostty/ or other files in ~/.config/.
  Triggers: Hyprland, window rules, animations, keybindings, monitors, gaps, borders, blur,
  opacity, layer rules, workspace settings, display config, terminal config, packages, default
  apps, system updates, snapshots, bug reports. For the shell itself (bar, dock, launcher,
  notifications, wallpaper, colours, lock, idle) use the taris skill.
---

# Asahi Desktop Skill

Manage this machine: TarisOS, a desktop for Apple Silicon Macs built on Arch Linux ARM and
Asahi Linux, with Hyprland as the window manager and Taris as the desktop shell (see the taris
skill).

This skill is for end-user customization. It is not for developing TarisOS.

## When This Skill MUST Be Used

- Editing ANY file in `~/.config/hypr/` (keybindings, monitors, window rules, animations...)
- Editing terminal configs (kitty, foot, alacritty, ghostty)
- Window behavior, animations, opacity, blur, gaps, borders, layer rules, workspaces
- Display/monitor configuration
- Installing or removing packages, system updates, snapshots
- Reporting a bug in this setup

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

## Topic Guides

- [`hyprland.md`](hyprland.md) - keybindings, monitors, window rules, and other Hyprland config

## Critical Safety Rules

For privileged commands, follow the Privilege Escalation rules below: `sudo` when a terminal is
available for the password prompt, `pkexec` when it is not. Do not wrap commands that already
manage privilege elevation themselves.

**Never modify files owned by packages**: `/usr/` (TarisOS's own settings are in
`/usr/share/taris/`, its helpers in `/usr/lib/taris/`), `/etc/xdg/quickshell/taris/`, and the
`/etc` files TarisOS's packages own (`pacman -Qo <file>` tells). Updates replace them. Reading
them is safe and useful.

**Always use these safe locations instead:**
- `~/.config/hypr/user.lua` - personal Hyprland changes (loaded last)
- `~/.config/` - other user configuration

Back up a file before changing it: `cp file file.bak.$(date +%s)`.

## Privilege Escalation

For an interactive script or command run in a visible terminal, use `sudo` for privileged work;
the terminal is the appropriate place to request a password.

Use `pkexec` only when the caller cannot interact with a terminal or cannot enter a password there,
such as a command launched by an agent or a graphical background process. Do not replace `sudo`
with `pkexec` merely because a command changes system state.

An account locks for 10 minutes after 10 failed password attempts (on every password prompt,
sudo included), and says so. Don't retry a failing password: tell the user.

## System Architecture

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **TarisOS** (Arch Linux ARM, Asahi) | Base OS, kernel and Apple Silicon support | `/etc/`, `~/.config/` |
| **Hyprland** | Wayland compositor/WM (Lua config) | `/usr/share/taris/hypr/` (system), `~/.config/hypr/user.lua` |
| **Taris** | Shell: bar, dock, launcher, notifications, OSD, lock, idle (Quickshell) | `~/.config/taris/` |
| **greetd** | Login: the shell's greeter (the lock screen) | `/etc/greetd/taris.toml` |
| **kitty** | Default terminal (`$TERMINAL` overrides it) | `~/.config/kitty/kitty.conf` |
| **Nautilus** | File manager | |
| **Chromium** | Browser, and the web apps | `~/.config/chromium-flags.conf` (TarisOS adds its lines at login) |
| **PipeWire / WirePlumber** | Audio (Asahi's speaker and microphone processing) | `~/.config/wireplumber/` |
| **NetworkManager, BlueZ** | Network, Bluetooth (also in Taris's settings) | |
| **snapper** | A snapshot of the system before every package change | `/etc/snapper/configs/root` |
| **nftables** | Firewall: nothing gets in unless it answers this machine | `/usr/share/taris/firewall.nft` |
| **tiny-dfr** | Touch Bar (MacBooks that have one) | `/etc/tiny-dfr/config.toml` |

Default apps: kitty, Nautilus, Chromium, GNOME Text Editor, Neovim, imv (images), mpv and VLC
(video), Taris Music (music, the `taris-music` package), Evince (PDFs), swappy (screenshots),
GitHub CLI (`gh`). VSCodium and Claude Code are installed the first time they're opened (`codium`
and `claude` in a terminal offer it too).

## Packages and Updates

```bash
pacman -Q <name>                      # Is it installed?
pacman -Ss <term>                     # Search the repositories
sudo pacman -Syu --needed <pkgs...>   # Install (with the pending updates: never a partial upgrade)
sudo pacman -Rns <pkgs...>            # Remove
/usr/lib/taris/update                 # Update everything (what Settings > Updates runs)
yay -S <aur-package>                  # From the AUR
flatpak install --system flathub <id> # From Flathub
```

Packages come from Arch Linux ARM (aarch64), Asahi's repository (`asahi-alarm`) and TarisOS's
own (`taris`: the shell, its settings packages, and builds of AUR apps such as VSCodium and
NordVPN). The App Store (in the launcher) installs from all of them and from Flathub. Never install
an app from outdated package lists alone (`pacman -Sy <pkg>`): that's a partial upgrade.

Snapshots: `sudo snapper list` shows them; a snapshot is taken before every package change, and the
last 10 are kept. Factory reset (Settings > Security) brings back the system as installed.

## Terminals

```
~/.config/kitty/kitty.conf
~/.config/foot/foot.ini
~/.config/alacritty/alacritty.toml
~/.config/ghostty/config
```

Changes apply to new terminal windows. Terminal colours come from Taris's colour scheme (see
the taris skill), so don't hardcode colours there unless the user wants them fixed.

kitty, the default terminal, reads TarisOS's settings from `/etc/xdg/kitty/kitty.conf` only while
the account has no `~/.config/kitty/kitty.conf`. When creating one, start it with
`include /etc/xdg/kitty/kitty.conf` so TarisOS's settings stay (without it, kitty reopens maximized
over everything). Hyprland opens kitty floating and centred (`/usr/share/taris/hypr/hyprland.lua`);
change that with a window rule in `user.lua`.

## Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fuzzel | `~/.config/fuzzel/fuzzel.ini` |
| git | `~/.config/git/config` |
| Apps started at login | `~/.config/autostart/*.desktop` (the dock's Open at Login sets them) |
| Default apps | `~/.config/mimeapps.list` (TarisOS's are in `/etc/xdg/mimeapps.list`) |

## Safe Customization Patterns

```bash
# 1. Read the current config
cat ~/.config/hypr/user.lua
# 2. Back it up before changing it
cp ~/.config/hypr/user.lua ~/.config/hypr/user.lua.bak.$(date +%s)
# 3. Make the change with the Edit tool
# 4. Apply and validate:
#    Hyprland: reloads on save; validate with `hyprctl reload` and `hyprctl configerrors`
#    Taris: ~/.config/taris/shell.json reloads on save; check `taris shell -l`
#    Terminals: changes apply to new windows
```

## Resetting to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong, put the TarisOS defaults back only after the user says yes, and back
up what is there first:

```bash
# Hyprland: the account's stub, which loads TarisOS's config (personal changes are in user.lua)
cp ~/.config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua.bak.$(date +%s)
cp /etc/skel/.config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua
# Taris: move a broken shell.json aside and the defaults apply
mv ~/.config/taris/shell.json ~/.config/taris/shell.json.bak.$(date +%s)
```

Never run Settings > Security's factory reset for a user: it erases every account and file on the
machine.

## System Information

```bash
cat /etc/os-release                   # TarisOS
uname -r                              # Kernel
hyprctl version                       # Hyprland version
pacman -Q taris taris-shell quickshell-taris taris-cli hyprland
journalctl --user -b                  # This session's user log
journalctl -b -p warning              # This boot's system warnings and errors
taris shell -l                        # The shell's log
```

## Decision Framework

1. **Is it about the shell** (bar, dock, launcher, notifications, wallpaper, colours, lock, idle)?
   Use the taris skill.
2. **Is it a Hyprland change?** Follow [`hyprland.md`](hyprland.md); put it in `~/.config/hypr/user.lua`.
3. **Is it another config edit?** Edit in `~/.config/`, never in `/usr/`.
4. **Is it a package install?** `sudo pacman -Syu --needed <pkgs...>` in a terminal, or the App Store.
5. **Is it automation on an event?** Use a systemd user unit (`~/.config/systemd/user/`) or a
   Hyprland event handler (`hl.on(...)`) in `user.lua`.
6. **Unsure a command exists?** Check with `command -v <name>` before suggesting it.

## Reporting Bugs

Route a problem to where it belongs, and only once it is a verified bug:

- **TarisOS (the shell, its packages, the Hyprland config it ships):**
  https://github.com/TarisOS/tarisOS
- **Apple Silicon hardware support, the Asahi kernel or drivers:** Asahi Linux
  (https://asahilinux.org/, issues at https://github.com/AsahiLinux)
- **A package built by Arch Linux ARM:** https://archlinuxarm.org/
- **A bug inside an application:** that application's own project

Before filing anything: show the user the exact title and body and wait for a yes, search existing
issues (open and closed) first, and only use `gh` when `gh auth status` succeeds. Never install or
authenticate `gh` yourself; hand the user the text instead. Include what happened, what was
expected, steps to reproduce, and the System Information above. `gh` cannot attach media: save a
screenshot (`taris screenshot`) and give the user its path. End the report with a line naming
the model and agent harness that wrote it ("Filed by <model> via <harness>.").

## Example Requests

- "Add a keybinding for SUPER+E to open yazi" -> Check `hyprctl binds`, then `hl.unbind` and
  `hl.bind` in `~/.config/hypr/user.lua`, and say what SUPER+E did before
- "Make the window gaps smaller" -> Settings > Appearance > Window style (or `gapsin`/`gapsout` in
  `~/.config/taris/window-style.conf`, then `hyprctl reload`)
- "Configure my external monitor" -> Settings > Displays, or `hl.monitor(...)` in `user.lua`
- "Change my colours" -> `taris scheme set -n <scheme> -f <flavour>` (see the taris skill)
- "Turn on night light" -> Settings > Displays > Night light
- "Install <app>" -> the App Store, or `sudo pacman -Syu --needed <app>` in a terminal
- "Update everything" -> `/usr/lib/taris/update` in a terminal (Settings > General > Updates)
- "Record my screen" -> `taris record` (again to stop; `-r` for a region)
- "Report this bug to TarisOS" -> Gather the System Information and a capture of the problem, then
  follow Reporting Bugs

## Out of Scope

- Changing TarisOS's code or packages (development: only when asked)
- Editing package-owned files in `/usr/` or `/etc/xdg/quickshell/taris/`
