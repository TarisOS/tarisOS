---
name: taris
description: >
  REQUIRED for anything about the desktop shell on this machine: Taris, TarisOS's shell.
  Use for the taskbar/bar, dock, app launcher and app drawer, notifications and toasts, OSD
  sliders, sidebar, dashboard, overview, lock screen, idle/sleep, wallpaper, colour schemes and
  themes, the window border gradient, gaps, corners and other window style, the Taris
  settings app, the shell's keybindings and gestures, screenshots and screen recording, and
  the Touch Bar layout. Triggers: taris, shell, bar, dock, launcher, notifications, wallpaper,
  scheme, colours, theme, border, gaps, lock, idle, settings app, ~/.config/taris/.
---

# Taris Skill

This machine runs TarisOS (Arch Linux ARM on Apple Silicon, Asahi Linux) with Hyprland and
**Taris** as its desktop shell. For Hyprland, terminals, packages and the rest of the system, see
the asahi-desktop skill.

Taris is a Quickshell shell (package `taris-shell`, from the TarisOS repository). The same shell
is the login screen (the greeter, before anyone has logged in) and the first-boot setup screen.

## Critical Safety Rules

- **Never edit the installed shell** in `/etc/xdg/quickshell/taris/` (package
  `taris-shell`), or the `taris` CLI in `/usr/lib/python3*/site-packages/taris/`.
  Reading them is fine. Package updates overwrite them.
- **Never run `taris install` or `taris update`.** They deploy upstream Taris's dotfiles,
  which replace this setup.
- Changing the shell's own code is development, not customization: it happens in TarisOS's
  source (https://github.com/TarisOS/tarisOS), never in the installed files. Only when
  the user asks for it.
- Files under `~/.config/taris/` that say "Written by Taris settings" are generated: change
  them through the settings app (or the JSON they're written from), not by hand.
- Restarting the shell (`taris shell -r`) closes every panel and briefly removes the bar. Config
  changes reload on their own, so only restart when a change really needs it, and say so first.
- Back up a config file before editing it: `cp file file.bak.$(date +%s)`.
- For privileged work, use `sudo` when a terminal is available for the password prompt, `pkexec`
  when it is not.

## Files

```
~/.config/taris/
├── shell.json              # Shell config: bar, dock entry, launcher, notifications, idle, appearance...
│                           #   Reloads on save.
├── window-style.conf       # Window style page: key=value (gradient, bordertheme, colors, inactive,
│                           #   bordersize, gapsin, gapsout, roundingon, rounding, fade, swipe,
│                           #   titlebars, borderresize, columns, floatnew, opacity (windows', percent),
│                           #   blur, blursize, blurpasses, shellblur (the panels')); run
│                           #   `hyprctl reload` after. Chromium, web apps, mpv, imv, Evince, VSCodium and
│                           #   kitty stay solid; kitty's background follows `opacity` instead
├── theme-border.conf       # Generated: the scheme's border colours (used while bordertheme=1)
├── colour-overrides.json   # Colours page: per-scheme colour overrides {"name flavour mode": {colour: hex}}
├── hypr-settings.json      # Displays and Keyboard pages (monitors, input options) ...
└── hypr-settings.lua       #   ... and the Lua generated from it (don't edit)

~/.local/state/taris/
├── scheme.json             # Current colour scheme, written by the `taris` CLI (don't edit)
├── dock.json               # Pinned dock apps and the dock's Settings/apps/Trash buttons
└── notifs.json             # Saved notifications
```

Wallpapers are read from `~/Pictures/Wallpapers` (one folder per category; `TarisOS` links to the
wallpapers TarisOS comes with, `/usr/share/backgrounds/taris`).

## Settings App

`SUPER + COMMA` (or `taris-qs -c taris ipc call nexus open`) opens Taris's settings as an
overlay. Prefer pointing the user there for things it covers: wallpaper and colours, window style,
network, Bluetooth, audio, displays, power and idle, lock screen, keyboard and trackpad, panels,
dock, default apps, notifications.

## Commands

```bash
taris shell -d                    # Start the shell (detached)
taris shell -r                    # Kill and restart it (see the safety rules)
taris shell -l                    # Print the shell log: check it after config changes
taris shell -s                    # List every IPC target and function
taris-qs -c taris ipc call <target> <function> [args]
```

Useful IPC targets: `drawers` (toggle launcher, dashboard, sidebar...), `lock` (lock, unlock),
`notifs` (clear, toggleDnd), `wallpaper` (get, set, list), `brightness` (get, set "10%+"...),
`mpris` (playPause, next, previous), `idleInhibitor`, `gameMode`, `overview`, `picker`
(screenshot region picker), `nexus` (open settings), `store` and `kdeconnect` (open).

Hyprland binds the shell's global shortcuts as `hl.dsp.global("taris:<name>")`, with these names:
launcher, dashboard, sidebar, session, utilities, showall, overview, overviewOpen, overviewClose,
nexus, agent, lock, unlock, clearNotifs, screenshot, screenshotClip, screenshotFreeze,
screenshotFreezeClip, brightnessUp, brightnessDown, mediaToggle, mediaNext, mediaPrev, mediaStop,
mediaSwitch, refreshDevices, powerButton.

## Colours, Themes and Wallpaper

The shell's colour scheme (and the colours the `taris` CLI writes for terminals, Hyprland,
GTK, Qt, btop, fuzzel and others) comes from the `taris` CLI:

```bash
taris scheme list                         # Schemes and flavours (JSON)
taris scheme get                          # Current scheme
taris scheme set -n gruvbox -f soft       # Pick a scheme and flavour
taris scheme set -m light                 # Light or dark
taris scheme set -n dynamic               # Colours from the wallpaper
taris wallpaper -f <image>                # Set the wallpaper
```

Single colours of a scheme are changed on the Colours page (Settings > Wallpaper & style >
Colours), which keeps them per scheme in `colour-overrides.json`.

The window border gradient follows the scheme while `bordertheme=1` in `window-style.conf`; picking
border colours on the Window style page turns that off, picking a scheme turns it back on.

## Hyprland Integration

`/usr/share/taris/hypr/taris.lua` (package-owned) adds the shell's layer rules, keybindings,
gestures, window style and settings to Hyprland. It is loaded near the end of TarisOS's Hyprland
config (`/usr/share/taris/hypr/hyprland.lua`, which `~/.config/hypr/hyprland.lua` loads), just
before `~/.config/hypr/user.lua`. Personal Hyprland changes go in `user.lua`, which loads last and
so wins over Taris's (see the asahi-desktop skill).

After any Hyprland change: `hyprctl reload`, then `hyprctl configerrors` until it is clean.

### Keybindings Taris adds

| Keys | Action |
|------|--------|
| `SUPER + SPACE` | App launcher |
| `SUPER + GRAVE` | Window overview (also 3-finger swipe up; swipe down closes it) |
| `SUPER + N` | Notification sidebar |
| `SUPER + COMMA` | Settings |
| `SUPER + A` | Show or hide the coding agent's workspace |
| `SUPER + M` | Minimize the window to the dock |
| `CTRL + Q` | Close the window |
| 3-finger horizontal swipe | Switch workspace (window style `swipe=1`) |

TarisOS's Hyprland config adds the rest (terminal, browser, files, workspaces, window keys, media
keys); see the asahi-desktop skill. Left Ctrl and left Super are swapped unless the Keyboard page
says otherwise.

## Idle and Lock

Idle actions are `general.idle.timeouts` in `shell.json` (a list of `{ "timeout": seconds,
"idleAction": "lock" | "dpms off" | [command...], "returnAction": ... }`), also on Settings > Power.
Lock now: `taris-qs -c taris ipc call lock lock`.

## Screenshots and Recording

```bash
taris screenshot                  # Full screen
taris screenshot -r               # Pick a region (-f freezes the screen while picking)
taris record                      # Start/stop recording the screen (-r region, -s with sound)
taris record -p                   # Pause/resume (not on Apple Silicon: wf-recorder can't pause)
```

Recordings and their list are also in the quick actions panel (bottom right).

## Dock

Pinned apps are in `~/.local/state/taris/dock.json` and on Settings > Dock. In the dock, drag
apps to rearrange them, drag from the app drawer to pin, drop on the Trash to unpin; right click
for an app's menu.

## Touch Bar

On MacBooks with a Touch Bar, `tiny-dfr` draws it from `/etc/tiny-dfr/config.toml` (from the
`taris-hardware` package: a pacman update keeps your edits and leaves its own next to them as
`.pacnew`). Edit with sudo, then `sudo systemctl restart tiny-dfr`.

## Troubleshooting

- Shell misbehaving after a config edit: `taris shell -l` shows the QML warnings and errors.
- A setting not applying to Hyprland: `hyprctl configerrors`, and check `window-style.conf` and
  `hypr-settings.json`.
- Colours stuck: `taris scheme get`, then set the scheme again.
