<p align="center">
<img src="shell/assets/logo.png" alt="TarisOS logo" width="160">
</p>

<h1 align="center">TarisOS</h1>

<p align="center">
A minimal, fast, low-power desktop for Apple Silicon Macs.<br>
Built on <a href="https://asahilinux.org/">Asahi Linux</a> and Arch Linux ARM, with
<a href="https://hypr.land">Hyprland</a> and a custom desktop shell based on
<a href="https://github.com/caelestia-dots/shell">Caelestia</a>.
</p>

<p align="center">
<a href="#installation">Installation</a> ·
<a href="#features">Features</a> ·
<a href="#using-tarisos">Using TarisOS</a> ·
<a href="#building-tarisos">Building</a> ·
<a href="#configuration">Configuration</a> ·
<a href="#license">License</a>
</p>

---

TarisOS installs next to macOS with one command and starts straight into a finished desktop: the
Taris shell (bar, dock, launcher, notifications, lock screen, settings, app store), the apps you
need, and every fix Apple Silicon hardware needs on Linux. Nothing runs unless it's needed, so
the machine stays quiet, cool and long-lasting on battery.

> [!NOTE]
> Back up anything important on your Mac before installing it.

## Contents

- [Features](#features)
- [Supported Macs](#supported-macs)
- [Installation](#installation)
- [Using TarisOS](#using-tarisos)
- [Building TarisOS](#building-tarisos)
- [Working on the shell](#working-on-the-shell)
- [Configuration](#configuration)
- [Repository layout](#repository-layout)
- [Credits](#credits)
- [License](#license)

## Features

**The desktop**

- **The Taris shell**: a bar, a dock with pinned and running apps, an app launcher and app drawer,
  notifications, a dashboard, a window overview, OSDs and a lock screen, all in one
  [Quickshell](https://quickshell.outfoxxed.me) shell.
- **Settings app** (<kbd>SUPER</kbd> + <kbd>,</kbd>): network, Bluetooth, audio, displays, power,
  keyboard and trackpad, wallpaper and colours, window style, security, updates, and a search that
  finds individual options.
- **App Store**: apps from Arch Linux ARM, the TarisOS repository, Flathub and the AUR in one place.
  Browse, search, install, remove and update.
- **Colours and themes**: colour schemes, per-scheme colour changes, saved themes, icon packs
  (Settings > Wallpaper & style), and a window border that follows the theme. TarisOS starts with
  the Taris theme.
- **Coding agent**: a terminal with your coding agent in the dashboard and on a workspace of its
  own (<kbd>SUPER</kbd> + <kbd>A</kbd>), the same session in both, Claude Code by default (installed
  the first time it's opened), with skills that teach agents about this system.
- **Web apps**: Discord is ready to use. `>install` in the launcher adds any site as an app, or
  installs a package; `>uninstall` removes either.

**The system**

- **One password, one prompt**: you log in on a screen that looks like the lock screen, and nothing
  of yours starts before that. With disk encryption, the disk password is the only one you type.
- **First-boot setup**: keyboard, Wi-Fi, time zone and your account, then straight into the
  desktop.
- **Disk encryption**: turn it on from Settings > Security at any time. The Mac restarts once and
  encrypts the disk in place.
- **Backups and factory reset**: Settings > Backup & restore backs up the whole system (apps,
  settings and every account's files) now or on a schedule, restores any backup, and can bring the
  system back to exactly how it was installed. A snapshot of the system is also taken before every
  package change (the last 10 are kept).
- **Updates in one place**: Settings > General > Updates updates the system, the TarisOS packages,
  AUR apps and Flatpak apps together.
- **Account protection**: an account locks for 10 minutes after 10 wrong passwords, and every
  password prompt says so.
- **Firewall**: nothing gets in unless it answers something your Mac started. It's a static
  ruleset, so nothing keeps running.
- **Low power**: no background services that aren't needed, compressed swap in RAM, hardware video
  decoding, power profiles in the bar's battery menu, and an optional 80% charge limit (Settings >
  Power).

**Apple Silicon hardware**

- Speakers and microphones with Asahi's sound processing, including a fix for apps that only heard
  the microphone on one side
- Wi-Fi that recovers after sleep, with the right Wi-Fi channels for your country
- Trackpad and keyboard reliable from the first second
- Hardware video decoding (H.264, HEVC and VP9)
- Fan control in the bar
- Touch Bar with media, brightness and screenshot keys (MacBook Pros that have one)

**Default apps**

| | |
| --- | --- |
| Browser | Chromium (with Google account sign-in and sync) |
| Anonymous browsing | Tor Browser (the Tor Project's alpha: the only build for 64-bit ARM Linux; installed in the background after setup) |
| Terminal | kitty |
| Files | Nautilus, with Space-bar previews |
| Text editor | GNOME Text Editor, Neovim |
| Code editor | VSCodium (installed the first time it's opened) |
| Music | Taris Music, based on Zuno (YouTube Music, without its ads) |
| Images, video, PDFs | imv, mpv, VLC (installed in the background after setup), Evince |
| Disks | GNOME Disks |
| Phone | KDE Connect, in the shell's own window |
| Torrents | qBittorrent |
| Screenshots | The shell's screenshot tool, swappy for editing |
| VPN | Tor for the whole system, from its icon in the taskbar or Settings > Network > Tor (new identity, bridges, a circuit for each site, a random hardware address); NordVPN (installed the first time it's opened) |
| Apps | The App Store: Flathub, the AUR (yay) and the repositories |
| GitHub | GitHub CLI (`gh`) |

Chinese, Japanese and Korean input and fonts are installed when you turn them on in Settings >
Keyboard & trackpad.

## Supported Macs

TarisOS is made for the Apple Silicon Macs Asahi Linux supports: the **M1** and **M2** families.
It's developed and tested on an M1 MacBook Pro; M2 Macs haven't been tested yet. TarisOS is for
Apple Silicon only: it carries no drivers or firmware for other hardware.

## Installation

You need:

- an M1 or M2 Mac running **macOS 13.5 or newer**;
- free disk space for TarisOS (the installer asks how much to give it; 30 GB or more is
  comfortable);
- an internet connection while installing;
- a backup of anything important on the Mac.

**1. Run the installer in macOS.** Open Terminal and run:

```sh
curl -fsSL https://github.com/TarisOS/tarisOS/releases/latest/download/install.sh | sh
```

This starts the TarisOS installer (Asahi Linux's installer, set up for TarisOS). It asks for your
macOS password, how much space to give TarisOS (macOS keeps the rest), and the name the Mac's
startup screen shows. It then downloads TarisOS and installs it next to macOS. Nothing in macOS is
changed apart from its partition shrinking.

**2. Allow TarisOS to start.** Apple requires this step for every other operating system. When the
installer says so, shut the Mac down, then press and hold the power button until "Loading startup
options" appears. Choose TarisOS and follow the installer's instructions; it asks for your macOS
password to confirm.

**3. Set up TarisOS.** TarisOS starts with its setup screen: choose your keyboard, join a Wi-Fi
network (you can skip it), pick your time zone and create your account. Then you're on your
desktop.

To switch between macOS and TarisOS, hold the power button while the Mac starts and pick one.

## Using TarisOS

### Shortcuts

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SPACE</kbd> | App launcher |
| <kbd>SUPER</kbd> + <kbd>RETURN</kbd> | Terminal |
| <kbd>SUPER</kbd> + <kbd>B</kbd> | Browser |
| <kbd>SUPER</kbd> + <kbd>E</kbd> | Files |
| <kbd>SUPER</kbd> + <kbd>,</kbd> | Settings |
| <kbd>SUPER</kbd> + <kbd>TAB</kbd> or <kbd>SUPER</kbd> + <kbd>`</kbd> | Window overview |
| <kbd>SUPER</kbd> + <kbd>N</kbd> | Notification sidebar |
| <kbd>SUPER</kbd> + <kbd>A</kbd> | Show or hide the coding agent's workspace |
| <kbd>SUPER</kbd> + <kbd>V</kbd> | Clipboard history |
| <kbd>SUPER</kbd> + <kbd>K</kbd> | Every keyboard shortcut |
| Hold <kbd>FN</kbd> | Emoji picker |
| <kbd>SUPER</kbd> + <kbd>L</kbd> | Lock |
| <kbd>SUPER</kbd> + <kbd>ESC</kbd> | Power panel (log out, shut down, sleep, stash, restart) |
| <kbd>PRINT</kbd> | Screenshot |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>R</kbd> | Record a part of the screen |
| <kbd>CTRL</kbd> + <kbd>Q</kbd> or <kbd>SUPER</kbd> + <kbd>W</kbd> | Close the window |
| <kbd>SUPER</kbd> + <kbd>F</kbd> | Fullscreen |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>M</kbd> | Maximise |
| <kbd>SUPER</kbd> + <kbd>M</kbd> | Minimise to the dock |
| <kbd>SUPER</kbd> + <kbd>T</kbd> | Float or tile the window |
| <kbd>SUPER</kbd> + arrows | Move focus |
| <kbd>SUPER</kbd> + <kbd>1</kbd>–<kbd>9</kbd> | Go to a workspace |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>1</kbd>–<kbd>9</kbd> | Move the window to a workspace |
| <kbd>SUPER</kbd> + <kbd>S</kbd> | Show or hide the special workspace |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>S</kbd> | Move the window to the special workspace |
| <kbd>fn</kbd> twice | Switch input source |
| 3-finger swipe left or right | Switch workspace |
| 3-finger swipe up or down | Open or close the overview |

The left <kbd>CTRL</kbd> and <kbd>SUPER</kbd> keys are swapped, so <kbd>⌘</kbd> works as it does
in macOS (<kbd>⌘</kbd> + <kbd>C</kbd> copies, <kbd>⌘</kbd> + <kbd>Q</kbd> closes) and the
<kbd>SUPER</kbd> shortcuts are on the <kbd>control</kbd> key. Settings > Keyboard & trackpad
changes this.

### Apps and updates

- **Install apps** from the App Store (in the launcher), or type `>install` in the launcher.
- **Update** from Settings > General > Updates. TarisOS takes a snapshot first, then updates the
  system, its own packages, AUR apps and Flatpak apps.
- **Remove an app** with `>uninstall` in the launcher, or Remove… in the app drawer.

From a terminal, TarisOS is Arch Linux ARM: `pacman`, `yay` and `flatpak` work as usual. Install
with `sudo pacman -Syu --needed <package>` (never `-Sy` alone), and update everything with
`/usr/lib/taris/update`.

### Security, encryption, backups and factory reset

- **Disk encryption** (Settings > Security): choose *Encrypt the disk*, enter your password, and the
  Mac restarts. On the way back up it asks for a new disk password twice, encrypts the disk (it
  shows how far it has got), and starts. From then on the disk password is your login.
- **Backups** (Settings > Backup & restore): *Back up now*, or turn on automatic backups (every
  day, week or month). A backup holds the whole system: apps, packages, settings and every
  account's files. Up to 20 are kept; the oldest go first. *Restore* (click twice) restarts into
  it: everything goes back to how it was then, files included.
- **Factory reset** (Settings > Backup & restore): *Erase everything*, confirmed, restarts and
  brings TarisOS back to how it was installed. Every account, file and backup on it is erased, and
  the setup screen starts again.

Snapshots of the system taken before package changes are listed with `snapper list`.

### Wallpapers

Wallpapers are read from `~/Pictures/Wallpapers`, where `TarisOS` holds the ones TarisOS comes with.
Pick one in Settings > Appearance > Wallpaper & style, or run `taris wallpaper -f <path>`.

### Your own Hyprland settings

Hyprland's settings come from `/usr/share/taris/hypr/` and update with the system. Put your own
changes in `~/.config/hypr/user.lua`, which loads last, or use the Window style, Displays and
Keyboard & trackpad pages in Settings.

### The shell from a terminal

```sh
taris shell -d       # start the shell (it starts with Hyprland)
taris shell -l       # its log
taris shell -s       # every IPC command, e.g.:
taris shell mpris getActive trackTitle
```

## Building TarisOS

TarisOS is built on an Apple Silicon Mac running Arch Linux ARM (Asahi Linux): its own package
repository first, then the installer image from it. Everything goes into `distro/out/`.

```sh
git clone https://github.com/TarisOS/tarisOS.git
cd tarisOS

distro/make-signing-key.sh      # once: the key packages are signed with (back it up)
distro/build-repo.sh            # build and sign every package, and the package list
sudo distro/build-image.sh      # the installer image, from that repository
```

- `distro/build-repo.sh` builds this repository's packages (`packaging/pkgbuilds/`) and VSCodium,
  NordVPN and yay from the AUR (a changed AUR PKGBUILD is shown for review first). It installs the
  build tools it needs, and keeps the source of every package built from source in
  `distro/out/sources` (the GPL asks for it next to the binaries).
- `distro/build-image.sh` makes `distro/out/images/tarisos.zip` in the format the Asahi Linux
  installer installs, with `installer_data.json` and `install.sh` (the command that starts the
  installer).

Publishing (`distro/config.sh` sets where):

- **Packages**: upload everything in `distro/out/repo` to the release `packages` of
  [tarisOS-packages](https://github.com/TarisOS/tarisOS-packages), with
  `taris.db`, `taris.files` and their `.sig` files as copies of the `.tar.gz` files of the same name
  (release assets can't be links).
- **Image**: publish a TarisOS release on this repository (e.g. `v1.0.0`, not marked as a
  pre-release) with `tarisos.zip`, `installer_data.json` and `install.sh` from `distro/out/images`
  (GitHub takes files under 2 GB). The install command always runs the latest release's
  `install.sh`.

## Working on the shell

To work on the shell and the desktop on an existing Asahi Linux (Arch Linux ARM) install:

```sh
git clone https://github.com/TarisOS/tarisOS.git
cd tarisOS
./install.sh
```

`install.sh` builds the shell and the packages it needs from this checkout and installs them,
together with TarisOS's desktop settings (`taris-desktop`, `taris-chromium`, `taris-wallpapers`).
It then restarts the shell and checks that it loaded. Run it again after every change. The login
screen, hardware fixes, snapshots and firewall come only with the TarisOS image.

## Configuration

Most options are in the Settings app (<kbd>SUPER</kbd> + <kbd>,</kbd>). All of them, including the ones
Settings doesn't show, live in `~/.config/taris/shell.json`. Options you leave out use their default values.

### Per-monitor configuration

You can configure per-monitor options in `~/.config/taris/monitors/<monitor>/shell.json`. Each
monitor's folder is named after the monitor itself (its make, model and serial number), so its
settings follow it to any port or adapter. List them by running:

```sh
hyprctl monitors -j | jq -r '.[].description'
```

The built-in display has no description: its folder is named after its output (`eDP-1`). So are
those of identical monitors without serial numbers, which nothing else tells apart. A `/` in a
description becomes `-` in the folder's name.

Options set in these files will **override** the respective options in the global config. Any options not present in
per-monitor configs will inherit their values from the global config.


For example, to automatically hide the bar on a monitor described as `Dell Inc. P2422H 7Q1KX`:

**`~/.config/taris/monitors/Dell Inc. P2422H 7Q1KX/shell.json`**

```json
{
    "bar": {
        "persistent": false
    }
}
```

> [!NOTE]
> Not all options respect per-monitor overrides. Most notably, the following options will only read
> from the global config, and ignore the respective option in per-monitor config files.
>
> <details><summary>Ignored options</summary>
>
> - `appearance`: `anim.*`, `transparency.*`
> - `bar.tray`: `hiddenIcons`, `iconSubs`
> - `bar.workspaces`: `agentWorkspace`, `ignoredTags`, `specialWorkspaceIcons`, `windowIcons`, `workspaceIcons`
> - `dashboard`: `mediaUpdateInterval`, `resourceUpdateInterval`
> - `general`: `apps.*`, `battery.*`, `idle.*`, `logo`, `powerButton`
> - `launcher`: `actionPrefix`, `actions`, `appOrder`, `enableDangerousActions`, `favouriteApps`, `hiddenApps`, `specialPrefix`, `useFuzzy.*`, `vimKeybinds`
> - `lock`: `enableHowdy`, `maxHowdyTries`, `triggerHowdyOnWake`
> - `nexus`: `networkRescanInterval`
> - `notifs`: `actionOnClick`, `defaultExpireTimeout`, `expire`, `fullscreen`, `fullscreenExpireTimeout`
> - `paths`: `lyricsDir`, `wallpaperDir`
> - `services`: `audioIncrement`, `brightnessIncrement`, `clockFormat`, `dataUnits`, `defaultPlayer`, `gpuType`, `lyricsBackend`, `maxVolume`, `playerAliases`, `sensorUnits`, `smartScheme`, `visualiserBars`, `weatherLocation`, `weatherUnits`
> - `utilities`: `toasts.*`, `vpn.*`
>
> </details>

### Example configuration

> [!WARNING]
> The example configuration includes **ALL** configuration options in `shell.json`. It is
> **not** recommended to copy and paste this entire configuration into `shell.json`,
> as options or their default values may change across updates, resulting in a stale config.
>
> This is meant to serve as a reference of all the available options, and you should
> <ins>only add the ones you want to change</ins> to `shell.json`.

<details><summary>Example config</summary>

```json
{
    "enabled": true,
    "appearance": {
        "deformScale": 1,
        "rounding": {
            "scale": 1
        },
        "spacing": {
            "scale": 1
        },
        "padding": {
            "scale": 1
        },
        "font": {
            "scale": 1,
            "clock": "Rubik",
            "workspaces": "Rubik",
            "headline": {
                "family": "GoogleSansFlex",
                "large": { "size": 32, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } },
                "medium": { "size": 28, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } },
                "small": { "size": 24, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } }
            },
            "title": {
                "family": "GoogleSansFlex",
                "large": { "size": 22, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } },
                "medium": { "size": 16, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } },
                "small": { "size": 14, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } }
            },
            "body": {
                "family": "GoogleSansFlex",
                "large": { "size": 16, "weight": 400, "italic": false, "vaxes": { "ROND": 25 } },
                "medium": { "size": 14, "weight": 400, "italic": false, "vaxes": { "ROND": 25 } },
                "small": { "size": 12, "weight": 400, "italic": false, "vaxes": { "ROND": 25 } }
            },
            "label": {
                "family": "GoogleSansFlex",
                "large": { "size": 14, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } },
                "medium": { "size": 12, "weight": 500, "italic": false, "vaxes": { "ROND": 25 } },
                "small": { "size": 11, "weight": 400, "italic": false, "vaxes": { "ROND": 25 } }
            },
            "mono": {
                "family": "CaskaydiaCove NF",
                "large": { "size": 16, "weight": 400, "italic": false, "vaxes": {} },
                "medium": { "size": 14, "weight": 400, "italic": false, "vaxes": {} },
                "small": { "size": 12, "weight": 400, "italic": false, "vaxes": {} }
            },
            "icon": {
                "family": "Material Symbols Rounded",
                "extraLarge": { "size": 36, "weight": 400, "italic": false, "vaxes": {} },
                "large": { "size": 24, "weight": 400, "italic": false, "vaxes": {} },
                "medium": { "size": 18, "weight": 400, "italic": false, "vaxes": {} },
                "small": { "size": 15, "weight": 400, "italic": false, "vaxes": {} }
            }
        },
        "anim": {
            "durations": {
                "scale": 1
            }
        },
        "transparency": {
            "enabled": false,
            "base": 0.85,
            "layers": 0.4
        }
    },
    "general": {
        "logo": "",
        "logoAction": "settings",
        "powerButton": "lock",
        "lidAction": "sleep",
        "showOverFullscreen": false,
        "mediaGifSpeedAdjustment": 300,
        "apps": {
            "terminal": ["kitty"],
            "audio": ["pwvucontrol"],
            "playback": ["mpv"],
            "explorer": ["nautilus"],
            "agent": "claude"
        },
        "idle": {
            "lockBeforeSleep": true,
            "inhibitWhenAudio": true,
            "inhibitWhenCharging": false,
            "timeouts": [
                {
                    "timeout": 180,
                    "idleAction": "lock",
                    "inhibitWhenAudio": false,
                    "inhibitWhenCharging": false,
                    "respectInhibitors": true
                },
                {
                    "timeout": 300,
                    "idleAction": "dpms off",
                    "returnAction": "dpms on"
                },
                {
                    "timeout": 600,
                    "idleAction": ["suspendThenHibernate"]
                }
            ]
        },
        "battery": {
            "warnLevels": [
                {
                    "level": 20,
                    "title": "Low battery",
                    "message": "You might want to plug in a charger",
                    "icon": "battery_android_frame_2"
                },
                {
                    "level": 10,
                    "title": "Did you see the previous message?",
                    "message": "You should probably plug in a charger <b>now</b>",
                    "icon": "battery_android_frame_1"
                },
                {
                    "level": 5,
                    "title": "Critical battery level",
                    "message": "PLUG THE CHARGER RIGHT NOW!!",
                    "icon": "battery_android_alert",
                    "critical": true
                }
            ],
            "criticalLevel": 3
        }
    },
    "background": {
        "enabled": true,
        "wallpaperEnabled": true,
        "desktopClock": {
            "enabled": false,
            "scale": 1.0,
            "position": "bottom-right",
            "invertColors": false,
            "background": {
                "enabled": false,
                "opacity": 0.7,
                "blur": true
            },
            "shadow": {
                "enabled": true,
                "opacity": 0.7,
                "blur": 0.4
            }
        },
        "visualiser": {
            "enabled": false,
            "autoHide": true,
            "blur": false,
            "rounding": 1,
            "spacing": 1
        }
    },
    "bar": {
        "persistent": true,
        "showOnHover": true,
        "dragThreshold": 20,
        "scrollActions": {
            "workspaces": true,
            "volume": true,
            "brightness": true
        },
        "popouts": {
            "activeWindow": true,
            "tray": true,
            "statusIcons": true
        },
        "workspaces": {
            "shown": 5,
            "activeIndicator": true,
            "occupiedBg": false,
            "showUnoccupied": true,
            "perMonitor": true,
            "showWindows": false,
            "showWindowsOnSpecialWorkspaces": false,
            "agentWorkspace": true,
            "maxWindowIcons": 5,
            "activeTrail": false,
            "displayType": "shapes",
            "specialDisplayType": "icons",
            "label": "  ",
            "occupiedLabel": "󰮯",
            "activeLabel": "󰮯",
            "capitalisation": "preserve",
            "workspaceIcons": [],
            "specialWorkspaceIcons": [
                {
                    "name": "special",
                    "icon": "star"
                },
                {
                    "name": "communication",
                    "icon": "forum"
                },
                {
                    "name": "music",
                    "icon": "music_cast"
                },
                {
                    "name": "agent",
                    "icon": "smart_toy"
                },
                {
                    "name": "todo",
                    "icon": "checklist"
                },
                {
                    "name": "sysmon",
                    "icon": "monitor_heart"
                }
            ],
            "ignoredTags": [
                "hide_in_bar",
                "xwl_popup"
            ],
            "windowIcons": [
                {
                    "regex": "steam(_app_(default|[0-9]+))?",
                    "icon": "sports_esports"
                }
            ]
        },
        "activeWindow": {
            "compact": false,
            "inverted": false,
            "showOnHover": true
        },
        "tray": {
            "background": false,
            "recolour": false,
            "compact": false,
            "iconSubs": [],
            "hiddenIcons": []
        },
        "clock": {
            "background": false,
            "showDate": true,
            "showSeconds": true
        },
        "statusIcons": [
            {
                "id": "lockStatus",
                "enabled": false
            },
            {
                "id": "audio",
                "enabled": false
            },
            {
                "id": "microphone",
                "enabled": false
            },
            {
                "id": "kbLayout",
                "enabled": false
            },
            {
                "id": "network",
                "enabled": true
            },
            {
                "id": "bluetooth",
                "enabled": true
            },
            {
                "id": "battery",
                "enabled": true
            }
        ],
        "entries": [
            {
                "id": "logo",
                "enabled": true
            },
            {
                "id": "workspaces",
                "enabled": true
            },
            {
                "id": "spacer",
                "enabled": true
            },
            {
                "id": "activeWindow",
                "enabled": true
            },
            {
                "id": "spacer",
                "enabled": true
            },
            {
                "id": "tray",
                "enabled": true
            },
            {
                "id": "clock",
                "enabled": true
            },
            {
                "id": "statusIcons",
                "enabled": true
            },
            {
                "id": "power",
                "enabled": true
            }
        ],
        "excludedScreens": []
    },
    "border": {
        "thickness": 10,
        "rounding": 25,
        "smoothing": 20
    },
    "dashboard": {
        "enabled": true,
        "showOnHover": true,
        "showDashboard": true,
        "showMedia": true,
        "showPerformance": true,
        "showWeather": true,
        "showAgent": true,
        "showClockSeconds": true,
        "status": "",
        "mediaUpdateInterval": 500,
        "resourceUpdateInterval": 1000,
        "dragThreshold": 50,
        "performance": {
            "showBattery": true,
            "showGpu": true,
            "showCpu": true,
            "showMemory": true,
            "showStorage": true,
            "showNetwork": true
        }
    },
    "launcher": {
        "enabled": true,
        "showOnHover": false,
        "maxShown": 7,
        "maxWallpapers": 9,
        "specialPrefix": "@",
        "actionPrefix": ">",
        "enableDangerousActions": false,
        "dragThreshold": 50,
        "vimKeybinds": false,
        "favouriteApps": [],
        "hiddenApps": [
            "avahi-discover",
            "bssh",
            "bvnc",
            "cmake-gui",
            "qv4l2",
            "qvidcap",
            "mpv",
            "vim",
            "lstopo",
            "org.kde.kdeconnect.app",
            "org.kde.kdeconnect.sms",
            "org.kde.kdeconnect.nonplasma",
            "org.gnome.Papers"
        ],
        "appOrder": [
            "taris-settings",
            "taris-store",
            "org.gnome.DiskUtility",
            "taris-kdeconnect",
            "kitty",
            "org.gnome.Nautilus",
            "chromium",
            "webapp-discord",
            "taris-music",
            "org.qbittorrent.qBittorrent",
            "org.gnome.TextEditor",
            "nvim",
            "taris-install-code",
            "codium",
            "com.microsoft.VSCode",
            "code",
            "visual-studio-code",
            "taris-install-steam",
            "steam",
            "taris-install-obs",
            "com.obsproject.Studio",
            "taris-install-writer",
            "libreoffice-writer",
            "taris-install-calc",
            "libreoffice-calc",
            "taris-install-impress",
            "libreoffice-impress",
            "org.gnome.Evince",
            "taris-install-firefox",
            "firefox",
            "taris-install-nordvpn",
            "taris-nordvpn"
        ],
        "useFuzzy": {
            "apps": false,
            "actions": false,
            "schemes": false,
            "variants": false,
            "wallpapers": false
        },
        "actions": [
            {
                "name": "Calculator",
                "icon": "calculate",
                "description": "Do simple math equations (powered by Qalc)",
                "command": ["autocomplete", "calc"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Install",
                "icon": "download",
                "description": "Add a web app or a package",
                "command": ["autocomplete", "install"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Uninstall",
                "icon": "delete",
                "description": "Remove an app",
                "command": ["autocomplete", "uninstall"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Scheme",
                "icon": "palette",
                "description": "Change the current colour scheme",
                "command": ["autocomplete", "scheme"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Wallpaper",
                "icon": "image",
                "description": "Change the current wallpaper",
                "command": ["autocomplete", "wallpaper"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Variant",
                "icon": "colors",
                "description": "Change the current scheme variant",
                "command": ["autocomplete", "variant"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Random",
                "icon": "casino",
                "description": "Switch to a random wallpaper",
                "command": ["taris", "wallpaper", "-r", "-n"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Light",
                "icon": "light_mode",
                "description": "Change the scheme to light mode",
                "command": ["setMode", "light"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Dark",
                "icon": "dark_mode",
                "description": "Change the scheme to dark mode",
                "command": ["setMode", "dark"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Shutdown",
                "icon": "power_settings_new",
                "description": "Shutdown the system",
                "command": ["poweroff"],
                "enabled": true,
                "dangerous": true
            },
            {
                "name": "Reboot",
                "icon": "cached",
                "description": "Reboot the system",
                "command": ["reboot"],
                "enabled": true,
                "dangerous": true
            },
            {
                "name": "Logout",
                "icon": "exit_to_app",
                "description": "Log out of the current session",
                "command": ["logout"],
                "enabled": true,
                "dangerous": true
            },
            {
                "name": "Lock",
                "icon": "lock",
                "description": "Lock the current session",
                "command": ["loginctl", "lock-session"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Sleep",
                "icon": "bedtime",
                "description": "Suspend then hibernate",
                "command": ["suspendThenHibernate"],
                "enabled": true,
                "dangerous": false
            },
            {
                "name": "Settings",
                "icon": "settings",
                "description": "Configure the shell",
                "command": ["taris", "shell", "nexus", "open"],
                "enabled": true,
                "dangerous": false
            }
        ]
    },
    "lock": {
        "enabled": true,
        "useWallpaper": false,
        "recolourLogo": true,
        "enableHowdy": true,
        "maxHowdyTries": 3,
        "triggerHowdyOnWake": true,
        "hideNotifs": false,
        "enableSessionControls": true
    },
    "nexus": {
        "wallpapersPerRow": 4,
        "networkRescanInterval": 15000
    },
    "notifs": {
        "expire": true,
        "fullscreen": "On",
        "defaultExpireTimeout": 5000,
        "fullscreenExpireTimeout": 2000,
        "clearThreshold": 0.3,
        "expandThreshold": 20,
        "actionOnClick": false,
        "groupPreviewNum": 3,
        "openExpanded": false
    },
    "osd": {
        "enabled": true,
        "hideDelay": 2000,
        "enableBrightness": true,
        "enableMicrophone": false
    },
    "services": {
        "weatherLocation": "",
        "weatherUnits": "Auto",
        "sensorUnits": "Celsius",
        "dataUnits": "Binary",
        "clockFormat": "Auto",
        "gpuType": "Auto",
        "visualiserBars": 60,
        "audioIncrement": 0.1,
        "brightnessIncrement": 0.1,
        "maxVolume": 1.0,
        "smartScheme": true,
        "defaultPlayer": "Music",
        "playerAliases": [{ "from": "com.github.th_ch.youtube_music", "to": "YT Music" }, { "from": "Music", "to": "Taris Music" }],
        "lyricsBackend": "Auto"
    },
    "session": {
        "enabled": true,
        "dragThreshold": 30,
        "vimKeybinds": false,
        "stashNotice": true,
        "icons": {
            "logout": "logout",
            "shutdown": "power_settings_new",
            "hibernate": "bedtime",
            "stash": "move_to_inbox",
            "reboot": "cached"
        },
        "commands": {
            "logout": ["logout"],
            "shutdown": ["poweroff"],
            "hibernate": ["suspend"],
            "stash": ["stash"],
            "reboot": ["reboot"]
        }
    },
    "sidebar": {
        "enabled": true,
        "showOnHover": false,
        "minHoverThreshold": 200,
        "dragThreshold": 80
    },
    "utilities": {
        "enabled": true,
        "maxToasts": 4,
        "toasts": {
            "fullscreen": "off",
            "configLoaded": false,
            "chargingChanged": true,
            "gameModeChanged": true,
            "dndChanged": true,
            "audioOutputChanged": true,
            "audioInputChanged": true,
            "capsLockChanged": false,
            "numLockChanged": false,
            "kbLayoutChanged": true,
            "kbLimit": true,
            "vpnChanged": true,
            "nowPlaying": false
        },
        "vpn": {
            "enabled": false,
            "provider": [
                {
                    "name": "wireguard",
                    "interface": "your-connection-name",
                    "displayName": "Wireguard (Your VPN)",
                    "enabled": false
                }
            ]
        },
        "quickToggles": [
            {
                "id": "wifi",
                "enabled": true
            },
            {
                "id": "bluetooth",
                "enabled": true
            },
            {
                "id": "mic",
                "enabled": true
            },
            {
                "id": "camera",
                "enabled": true
            },
            {
                "id": "settings",
                "enabled": true
            },
            {
                "id": "gameMode",
                "enabled": true
            },
            {
                "id": "dnd",
                "enabled": true
            },
            {
                "id": "vpn",
                "enabled": false
            }
        ]
    },
    "paths": {
        "wallpaperDir": "~/Pictures/Wallpapers",
        "lyricsDir": "~/Music/lyrics/",
        "mediaGif": "root:/assets/bongocat.gif",
        "noNotifsPic": "root:/assets/dino.png",
        "lockNoNotifsPic": "root:/assets/dino.png"
    }
}
```

</details>

### Advanced configuration

> [!CAUTION]
> Do NOT change any of these options unless you know what you are doing. These options control the
> tokens used internally within the shell, and can cause visual issues if modified incorrectly.
> The available options may change or be removed without notice across versions.

A separate `~/.config/taris/shell-tokens.json` file allows editing the internal tokens without
touching the source code of the shell. These tokens affect the dimensions and appearance of visual elements,
including individual rounding, spacing, padding, font size, animation durations and curves, and the sizes of
certain components. The appearance scale values in `shell.json` are multiplied against these base
token values to produce the final computed values.

Per-monitor token overrides are also available at
`~/.config/taris/monitors/<monitor>/shell-tokens.json` (the folder named as above).


## Repository layout

| Path | What's there |
| --- | --- |
| `shell/` | The Taris shell: QML (`modules/`, `components/`, `services/`, `utils/`), its C++ plugin (`plugin/`), the greeter (`greeter.qml`) and the setup screen (`setup.qml`) |
| `packaging/pkgbuilds/` | Every TarisOS package: `taris` and its parts (`taris-hardware`, `taris-shell`, `taris-desktop`, `taris-login`, `taris-chromium`, `taris-snapshots`, `taris-firewall`, `taris-wallpapers`, `taris-keyring`) and the packages Arch Linux ARM doesn't have |
| `packaging/hypr/` | The Hyprland config TarisOS ships |
| `packaging/agents/` | Skills for coding agents |
| `packaging/defaults/`, `packaging/wallpapers/` | The Taris theme, the preinstalled web apps, the logo's icon sizes, the wallpapers |
| `packaging/titlebars/` | Builds the title bar plugin for the installed Hyprland |
| `distro/` | Builds the package repository and the installer image |
| `install.sh`, `install-hypr.sh`, `install-agent-skills.sh` | Install the shell and the desktop on an existing Asahi Linux install, for working on them |
| `AGENTS.md`, `CLAUDE.md`, `agents/skills/` | Instructions for coding agents working on TarisOS itself |

## Credits

The Taris shell is a heavily modified version of the
[Caelestia shell](https://github.com/caelestia-dots/shell) by
[@soramanew](https://github.com/soramanew) and its contributors. Much of its code is Caelestia's,
renamed and reworked for TarisOS. The `taris` command-line tool is built from
[Caelestia's CLI](https://github.com/caelestia-dots/cli). Thank you to the Caelestia project;
TarisOS isn't affiliated with it.

TarisOS is built on [Asahi Linux](https://asahilinux.org/) and
[Arch Linux ARM](https://archlinuxarm.org/), with [Quickshell](https://quickshell.outfoxxed.me) by
[@outfoxxed](https://github.com/outfoxxed) and [Hyprland](https://hypr.land).

Thanks to Naeem and the [Omarchy-Mac](https://github.com/omarchy-mac/omarchy-mac) project, whose
installer showed which fixes Apple Silicon Macs need and how to apply them safely.

TarisOS's music player, Taris Music, is [Zuno](https://github.com/noFAYZ/zuno) by
[@noFAYZ](https://github.com/noFAYZ) and its contributors (Apache-2.0), built from its source for
64-bit ARM with TarisOS's changes (the `music` folder; its `NOTICE` says what changed). Thank you
to the Zuno project; TarisOS isn't affiliated with it.

## License

TarisOS is free software under the [GNU General Public License v3.0](LICENSE) (GPL-3.0-only).
See [`shell/NOTICE`](shell/NOTICE) for the shell's notices. A few bundled files keep their own
licences: `shell/utils/scripts/fzf.js` (BSD-3-Clause), `shell/utils/scripts/fuzzysort.js` (MIT),
the Google Sans Flex font (OFL) and SiliconMotion's driver in `packaging/smidriver/driver/`.
