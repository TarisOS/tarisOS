---
name: apple-silicon-hardware
description: >
  What this TarisOS Mac's hardware can do under Asahi Linux, and its settings: battery and charge
  limit, sleep and the lid, fans, the Touch Bar, the camera, keyboard and trackpad, and which Mac
  this is. Use before promising or setting up anything hardware-related. Triggers: battery,
  charge limit, sleep, suspend, lid, fan, temperature, Touch Bar, camera, webcam, Touch ID,
  fingerprint, keyboard, fn key, trackpad, gestures, which Mac, model, hardware support.
---

# Apple Silicon Hardware

On a TarisOS development machine (`/etc/taris/dev-machine`), the development rules
(`/usr/share/taris/agent-rules-dev.md`) take precedence over this skill wherever they disagree.

## What the hardware supports

This Mac runs Asahi Linux's kernel and drivers. Not everything macOS can do works under Linux yet,
and some hardware never will without Apple's help. Before promising or setting up anything:

- **Which Mac:** `cat /proc/device-tree/model`.
- **Check Asahi Linux's feature support pages** (https://asahilinux.org/) for that Mac, and say
  plainly when something isn't supported rather than trying workarounds that can't work.
- **Not available:** the Touch ID sensor (no fingerprint login on the built-in sensor). External
  displays: see the displays skill.
- Never write to the SMC, firmware or other hardware registers by hand, and never flash firmware.

## Battery

- **Charge limit:** Settings > Power (where charging stops, for a battery that stays plugged in).
  It's `/sys/class/power_supply/macsmc-battery/charge_control_end_threshold`, which the wheel group
  may write and Asahi keeps across restarts.
- **Level and state:** `cat /sys/class/power_supply/macsmc-battery/{capacity,status}`.

## Sleep and the lid

Closing the lid sleeps the Mac. Settings > Power has the idle timeouts and "Lock before sleeping".
After waking, Wi-Fi on Macs whose Wi-Fi can come back wedged is reloaded by itself
(`taris-wifi-resume.service`). A Mac that doesn't sleep: `journalctl -b -u systemd-suspend` and the
messages just before it.

## Fans

On Macs with fans, the bar's fan popout shows them and can set their speed; Auto hands them back to
the Mac's own control (the SMC), which is what they should normally be on. TarisOS turns on the
kernel option that allows setting them; nothing else is needed.

## Touch Bar

On MacBooks that have one, `tiny-dfr` draws it from settings the owner account changes without
sudo, from `~/.config/taris/touchbar.toml` (a link to `/var/lib/taris/touchbar/config.toml`),
including whether the media keys or F1–F12 show without fn (`MediaLayerDefault`). The taris skill
has the details. `tiny-dfr` here runs with TarisOS's patches (`tiny-dfr-taris` builds Asahi's
installed version with them): the modifiers held on the keyboard go with the Touch Bar's keys, so
Ctrl+Alt+F1–F12 on it switch text consoles.

## Camera

The Camera quick toggle switches the FaceTime camera off for every app at once, across restarts
(`/usr/lib/taris/camera off|on|status`). Turning it back on asks for the password, so nothing can
turn it on unseen.

## Keyboard and trackpad

- Settings > Keyboard & trackpad: layout, input sources, keyboard and trackpad behaviour.
- Left Ctrl and left Super (Command) are swapped unless that page says otherwise.
- `fn` twice switches the input source; `fn` held for a second opens the emoji picker.
- Chinese, Japanese and Korean typing: `/usr/lib/taris/input-method add|remove zh|ja|ko` (the
  Keyboard & trackpad page runs it in a terminal).
- Gestures: three-finger swipes for workspaces and the overview (the taris skill).

## Memory

Compressed swap in RAM (zram, up to 8 GB) is set up; nothing else is needed for swap.
