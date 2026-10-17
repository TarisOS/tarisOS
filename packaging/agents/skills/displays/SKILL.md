---
name: displays
description: >
  The built-in display and external monitors on this TarisOS Mac: which ports and adapters work,
  arranging displays, resolution, scale, rotation, mirroring, the main display, the shell on each
  display, brightness, night light, and a display that stays dark. Triggers: monitor, display,
  screen, external, HDMI, USB-C, DisplayPort, adapter, dock, Silicon Motion, DisplayLink,
  resolution, refresh rate, scale, rotate, mirror, arrange, brightness, DDC, night light.
---

# Displays

On a TarisOS development machine (`/etc/taris/dev-machine`), the development rules
(`/usr/share/taris/agent-rules-dev.md`) take precedence over this skill wherever they disagree.

## Settings first

Settings > Displays does nearly everything, and keeps the Settings app accurate: arrangement (drag
the boxes), resolution and refresh rate, scale, rotation, mirroring, turning a display off, the
main display, the taskbar on each display, Identify (each display's number on it) and night light.
A change is tried out first and goes back by itself unless kept.

## What works

- **The built-in display**, and **HDMI** on Macs that have an HDMI port.
- **USB-C on M1 Macs, on one port:** the front left one of the MacBook Air and MacBook Pro, the
  back right one (next to HDMI) of the Mac mini, the back left one of the iMac with two ports and
  the back right middle one of the iMac with four. Other ports, and USB-C or Thunderbolt display
  output on other Macs, don't drive displays under Linux yet.
- **USB display adapters with a Silicon Motion chip** (USB vendor `090c`): their service
  (`smiusbdisplay`) starts by itself when one is plugged in. DisplayLink adapters aren't supported
  (there's no driver for them here).
- **Brightness:** the built-in display's, and an external monitor's when the monitor and its
  connection answer DDC/CI (`ddcutil detect` tells). Not through USB display adapters or the M1's
  USB-C port: those monitors are dimmed with their own buttons.

Before promising anything about a port, dock or adapter, check against this list.

## Where the settings are kept

- `~/.config/taris/hypr-settings.json` (and `hypr-settings.lua`, generated from it: don't edit):
  each monitor's mode, position, scale, rotation and mirroring, kept for the monitor itself
  (`desc:<make model serial>`) so they follow it to any port or adapter. The built-in display, and
  identical monitors without serial numbers, are kept by output name (`eDP-1`, `HDMI-A-1`...).
- `~/.config/taris/display-numbers.json`: the numbers Settings and Identify show.
- `~/.config/taris/shell.json`, `general.mainDisplay`: the main display. It always has the shell
  (bar, dock, panels) and workspace 1.
- `~/.config/taris/monitors/<monitor>/shell.json`: a display's own shell settings, in a folder named
  after the monitor's description (`hyprctl monitors -j | jq -r '.[].description'`; a `/` in it
  becomes `-`), or after its output for the built-in display. `"enabled": true` there puts the shell
  on that display too; displays other than the main one have it off until it's turned on.

## By hand

Only when Settings can't do it: a monitor rule in `~/.config/hypr/user.lua`, matched by the
monitor's description so it follows the monitor:

```lua
hl.monitor({ output = "desc:<make model serial>", mode = "2560x1440@144", position = "auto",
  scale = 1 })
```

`user.lua` loads last, so its rule wins over Settings for that monitor: say so, since Settings'
changes to it stop applying. List monitors and modes: `hyprctl monitors all`.

## A display that stays dark

1. Is it seen? `hyprctl monitors all` (a disabled display is listed with `disabled: true`; turn it
   on in Settings > Displays).
2. Is the port or adapter one that works (above)?
3. Kernel messages: `journalctl -k -b | grep -i -E 'dcp|drm|evdi|typec'`.
4. A Silicon Motion adapter: `systemctl status smiusbdisplay`, and unplug and plug it back in.
5. The M1's USB-C port after a kernel update: TarisOS's display drivers may not be built for the
   new kernel yet (`dkms status`; the updates-and-recovery skill).
