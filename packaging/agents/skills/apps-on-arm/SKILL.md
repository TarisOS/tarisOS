---
name: apps-on-arm
description: >
  Installing, removing and running apps on this TarisOS Mac (Arch Linux ARM on Apple Silicon:
  aarch64, 16 KB memory pages). Use when asked to install or remove an app, when an app has no
  ARM build, when a downloaded program won't start, for x86 programs, games and Steam, and for
  streaming video that needs DRM. Triggers: install, uninstall, app, package, AUR, yay, Flatpak,
  Flathub, App Store, x86, amd64, emulation, FEX, muvm, Steam, games, Widevine, Netflix, Spotify.
---

# Apps on an ARM Mac

On a TarisOS development machine (`/etc/taris/dev-machine`), the development rules
(`/usr/share/taris/agent-rules-dev.md`) take precedence over this skill wherever they disagree.

This Mac is 64-bit ARM (aarch64) with 16 KB memory pages, on Asahi Linux's kernel. An app has to be
built for that: check before promising one, and never suggest an x86 build as if it would just run.

## Where apps come from

Prefer them in this order:

1. **The App Store** (in the launcher): installs from the repositories and Flathub below.
2. **The repositories:** Arch Linux ARM, Asahi's (`asahi-alarm`) and TarisOS's own (`taris`).
   `pacman -Ss <term>` to search, `sudo pacman -Syu --needed <pkg>` to install, always with the
   pending updates: never `pacman -Sy <pkg>` alone, which is a partial upgrade and can break the
   system.
3. **Flathub:** `flatpak search <term>`, `flatpak install --system flathub <id>`. Only apps with an
   aarch64 build install here (`flatpak remote-info flathub <id>` shows its architecture).
4. **The AUR:** `yay -S <pkg>`, built on this machine. Read its PKGBUILD first (`yay -Gp <pkg>`):
   its `arch=` has to include `aarch64` (or `any`). Many `-bin` packages are x86_64 only and fail
   to build or install here.

Removing: `sudo pacman -Rns <pkg>`, `flatpak uninstall <id>`, or the App Store.

## Apps installed on first use

Some apps are in the launcher and dock greyed out until first opened, then installed (with the
pending updates) in a terminal: `/usr/lib/taris/install-on-demand <app>` with `code` (VSCodium),
`steam`, `obs`, `writer`, `calc`, `impress` (LibreOffice), `firefox` or `nordvpn`. Opening the
greyed-out icon does the same.

## A program that won't start

- **x86 only:** `file <program>` says `x86-64`. See below.
- **16 KB pages:** some prebuilt ARM64 programs assume 4 KB memory pages and fail at start, with
  errors about page size, memory mapping or the allocator (often apps that bundle their own copy of
  jemalloc or Chromium). A build from the repositories, Flathub or source usually works; otherwise
  running it inside muvm (below), whose virtual machine has 4 KB pages, can.
- Otherwise work from its error output and `journalctl --user -b`, and the diagnose-crash skill if
  it crashed.

## x86 programs and games

- **Steam:** `/usr/lib/taris/install-on-demand steam`. Asahi's `steam` package runs Steam and its
  games in muvm (a small virtual machine) through FEX-Emu (x86 emulation). Games that need more
  than the GPU driver offers, or anti-cheat, may not run.
- **Other x86 programs:** FEX-Emu and muvm are in Asahi's repository
  (`pacman -Ss 'fex|muvm'`). Read Asahi Linux's documentation for running a program through them
  before setting it up, and say plainly that emulated programs are slower and not all of them
  work.

## Streaming video (DRM)

Chromium plays DRM video (Netflix, Spotify, and others) through Widevine, installed with the system
(`pacman -Q widevine`). If a site still refuses, check it's Chromium and not another browser, then
the site's own requirements: some services limit Linux to lower quality.
