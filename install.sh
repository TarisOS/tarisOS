#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Build and install TarisOS's shell and desktop on this Mac (Asahi Linux, Arch Linux ARM), to work on
# them: the shell's packages from this checkout, and the desktop's settings packages
# (taris-desktop, taris-chromium, taris-wallpapers). The rest of TarisOS (login, hardware, snapshots,
# firewall) is only installed by its image (distro/). The shell runs on quickshell-taris (/opt) via
# `taris-qs`, beside any other quickshell.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
packaging="$here/packaging"
pkgbuilds="$packaging/pkgbuilds"

sudo pacman -S --needed vulkan-headers cli11 ninja cmake qt6-shadertools git aubio libqalculate \
  ttf-material-symbols-variable ttf-cascadia-code-nerd papirus-icon-theme swappy dart-sass cliphist fuzzel \
  python-build python-installer python-hatch python-hatch-vcs pybind11 meson autoconf-archive wf-recorder \
  hyprsunset adw-gtk-theme python-gobject jq pacman-contrib xdg-utils flatpak archlinux-appstream-data libjxl

# Packages ours replace: they own the same files, and --noconfirm won't swap them out
declare -A replaces=(
  [qmltermwidget-taris]=qmltermwidget # The Agent tab's terminal, patched (see its PKGBUILD)
  [taris-shell]=taris-silicon         # The shell's package before the rename
)

# Installed already, at this PKGBUILD's version where it fixes one (where pkgver() makes it at build
# time, any installed version will do). pacman -Q answers for packages that only provide the name
# too, so the name it gives has to be this one.
installed_current() {
  local pkg="$1" have want
  have=$(pacman -Q "$pkg" 2>/dev/null) || return 1
  [[ ${have%% *} == "$pkg" ]] || return 1
  grep -q '^pkgver()' PKGBUILD && return 0
  want=$(set +eu; source ./PKGBUILD >/dev/null 2>&1; echo "${epoch:+$epoch:}$pkgver-$pkgrel")
  [[ ${have#* } == "$want" ]]
}

build_install() {
  local pkg="$1"
  cd "$pkgbuilds/$pkg"

  # Skip rebuilding dependencies that are already installed (the shell and the desktop's settings,
  # built from this checkout, are always rebuilt)
  if [[ $pkg != taris-shell && $pkg != taris-desktop && $pkg != taris-chromium ]] && installed_current "$pkg"; then
    echo "==> $pkg is already installed, skipping."
    return 0
  fi

  # Clean out any old or corrupted package files before building
  rm -f ./*.pkg.tar.*

  makepkg -f --noconfirm

  local pkg_file
  pkg_file=$(ls -t ./*.pkg.tar.* 2>/dev/null | head -n1)
  if [[ -z "$pkg_file" ]]; then
    echo "error: No package file generated for $pkg" >&2
    return 1
  fi

  # -Qq names the package installed: ours answer to the names they replace too (provides)
  local old=${replaces[$pkg]:-}
  if [[ -n $old && $(pacman -Qq "$old" 2>/dev/null) == "$old" ]]; then
    sudo pacman -Rdd --noconfirm "$old"
  fi

  sudo pacman -U --noconfirm "$pkg_file"
  rm -f ./*.pkg.tar.*
}

# Dependencies first: each later package needs the earlier ones installed to build
# mise-bin installs the coding agent picked in Settings > Apps > Agent
for pkg in libcava qt6-m3shapes-git ttf-rubik-vf python-materialyoucolor quickshell-taris taris-cli qmltermwidget-taris mise-bin; do
  # Any mise will do (another package, or mise's own installer); a second one would conflict
  [[ $pkg == mise-bin ]] && command -v mise &>/dev/null && { echo "==> mise is already installed, skipping."; continue; }
  build_install "$pkg"
done

# The settings search's index of every option on the settings pages, up to date with them
python3 -I "$here/shell/scripts/settings-index.py" || echo "warning: the settings search index could not be updated" >&2

# The shell itself, from this checkout's shell folder
build_install taris-shell

# The shell's terminal colours come from each account's own folder now (qmltermwidget-taris looks
# there): the link older versions of this script put in QMLTermWidget's folder would come first
for qml in /usr/lib/qt6/qml /usr/lib64/qt6/qml; do
  link="$qml/QMLTermWidget/color-schemes/Taris.colorscheme"
  [[ -L $link ]] && sudo rm -f "$link"
done

# SiliconMotion SM77x USB display adapters (vendored in packaging/smidriver/ from the Witcher's
# Tweaks): the driver runs on the evdi kernel module (dkms), and a preloaded shim keeps it from
# crashing against upstream libevdi (packaging/smidriver/evdi-nullfix.c). Any step failing leaves
# the rest of the install be.
install_smi_driver() {
  local kernel_pkg build
  kernel_pkg=$(pacman -Qqo "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -1)
  [[ -n $kernel_pkg ]] || { echo "SMI driver: can't tell which package owns the running kernel" >&2; return 1; }

  sudo pacman -S --needed dkms "$kernel_pkg-headers" libdrm python-setuptools gcc || return 1
  build_install evdi-dkms || return 1

  if [[ -x /opt/siliconmotion/SMIUSBDisplayManager ]]; then
    echo "==> SiliconMotion driver is already installed, skipping."
  else
    # Its installer copies its files by relative path, so it runs from its own folder
    sudo bash -c 'cd "$1" && ./install.sh install' _ "$packaging/smidriver/driver" || return 1
  fi

  build=$(mktemp -d)
  gcc -shared -fPIC -O2 -o "$build/libevdi-nullfix.so" "$packaging/smidriver/evdi-nullfix.c" -levdi || { rm -rf "$build"; return 1; }
  sudo install -D -m 755 "$build/libevdi-nullfix.so" /usr/local/lib/libevdi-nullfix.so
  sudo install -D -m 644 "$packaging/smidriver/nullfix.conf" /etc/systemd/system/smiusbdisplay.service.d/nullfix.conf
  sudo systemctl daemon-reload
  rm -rf "$build"

  # The driver's udev rule starts it when an adapter is plugged in; one already plugged in starts now
  if grep -qsx 090c /sys/bus/usb/devices/*/idVendor; then
    sudo systemctl reset-failed smiusbdisplay 2>/dev/null || true
    sudo systemctl restart smiusbdisplay
  else
    echo "==> SMI driver installed; plug the adapter in to start it (reboot if its monitors don't come up)."
  fi
}
install_smi_driver || echo "warning: the SMI USB display driver could not be set up (see above); the rest of TarisOS is fine" >&2

# On TarisOS, taris-hardware already has the Touch Bar layout and fan control (below)
has_hardware=0
pacman -Q taris-hardware &>/dev/null && has_hardware=1

# Touch Bar layout with media keys and a screenshot key (MacBooks running tiny-dfr; skipped
# without it). On TarisOS it comes with taris-hardware.
if ((!has_hardware)); then
  "$packaging/extras/install-touchbar.sh" || echo "warning: the Touch Bar layout could not be installed (see above)" >&2
fi

# Fan control (the bar's fan popout): the fan driver, macsmc_hwmon, is built into the Asahi kernel
# and only takes speeds with macsmc_hwmon.fan_control=1 on the kernel command line (in GRUB's
# options here); the udev rule lets the wheel group write them. Apple Silicon only. A changed
# command line takes effect at the next boot. On TarisOS it comes with taris-hardware.
install_fan_control() {
  [[ -d /sys/module/macsmc_hwmon ]] || return 0
  sudo install -Dm644 "$pkgbuilds/taris-hardware/90-taris-fans.rules" /etc/udev/rules.d/90-taris-fans.rules
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=hwmon --action=change || true

  local grub=/etc/default/grub option=macsmc_hwmon.fan_control=1
  [[ $(cat /sys/module/macsmc_hwmon/parameters/fan_control 2>/dev/null) == Y ]] && grep -qs "$option" "$grub" && return 0
  if [[ ! -f $grub ]]; then
    echo "Fan control: no $grub here; add $option to the kernel options and reboot to set fan speeds" >&2
    return 0
  fi
  if ! grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=.*$option" "$grub"; then
    sudo cp "$grub" "$grub.bak.$(date +%s)"
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT="' "$grub"; then
      sudo sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 $option\"/" "$grub"
    else
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$option\"" | sudo tee -a "$grub" >/dev/null
    fi
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
  [[ $(cat /sys/module/macsmc_hwmon/parameters/fan_control 2>/dev/null) == Y ]] ||
    echo "==> Fan control is set up: reboot to set fan speeds (they're read-only until then)."
}
if ((!has_hardware)); then
  install_fan_control || echo "warning: fan control could not be set up (see above)" >&2
fi

# Hyprland and the desktop's packages; then TarisOS's desktop settings (taris-desktop: the
# Hyprland config in /usr/share/taris, the portal's file picker, the title bar plugin built by its
# pacman hook), Chromium's (taris-chromium) and the wallpapers (taris-wallpapers)
sudo pacman -S --needed hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk gnome-keyring \
  kitty nautilus gvfs pipewire wireplumber networkmanager bluez bluez-utils chromium noto-fonts noto-fonts-emoji
# This account was set up before: the desktop's defaults for a new account (colours, wallpaper,
# web apps, the dock) mustn't replace yours at the next login
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/taris"
touch "${XDG_STATE_HOME:-$HOME/.local/state}/taris/defaults-applied"
for pkg in taris-wallpapers taris-desktop taris-chromium; do
  build_install "$pkg"
done
"$here/install-hypr.sh"
/usr/lib/taris/chromium-flags || echo "warning: Chromium's settings could not be added (see above)" >&2

# The wallpapers, one collection in the wallpaper folder (a link to taris-wallpapers'; a TarisOS
# folder made by an older install.sh stays as it is)
walls="${TARIS_WALLPAPERS_DIR:-$HOME/Pictures/Wallpapers}"
mkdir -p "$walls"
[[ -e $walls/TarisOS || -L $walls/TarisOS ]] || ln -s /usr/share/backgrounds/taris "$walls/TarisOS"

# Instructions and rules for coding agents (the Agent tab, SUPER + A), written for this system
"$here/install-agent-skills.sh" || echo "warning: the agent skills could not be installed (see above)" >&2

# The desktop portal reads its config at startup; the GTK one (still the fallback, and its other
# dialogs) its theme (adw-gtk3-dark, installed above)
for unit in xdg-desktop-portal-gtk.service xdg-desktop-portal.service; do
  systemctl --user is-active --quiet "$unit" && systemctl --user restart "$unit" || true
done

# Start the shell just installed, only inside the Hyprland session it's for (not over SSH or from a
# TTY)
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  echo "Done. Start the shell from your Hyprland session with: taris shell -d"
else
  # Taris is the polkit agent now: polkit-gnome (started by older versions of this setup) holds
  # the agent's place while it runs
  pkill -f polkit-gnome-authentication-agent-1 2>/dev/null || true
  taris shell -k &>/dev/null || true
  taris shell -d
  # A config that fails to load leaves the process running with nothing on screen, and says so
  # only in its log: wait for the log to say which (up to 15 s)
  status=""
  for _ in $(seq 30); do
    log=$(timeout 3 taris shell -l 2>/dev/null || true)
    if grep -q 'Failed to load configuration' <<<"$log"; then
      status=failed
      break
    elif grep -q 'Configuration Loaded' <<<"$log"; then
      status=loaded
      break
    fi
    sleep 0.5
  done
  case $status in
  loaded) echo "Done. TarisOS is running." ;;
  failed)
    echo "error: the shell was installed but its config failed to load:" >&2
    grep -E 'ERROR' <<<"$log" | sed 's/\x1b\[[0-9;]*m//g' >&2
    exit 1
    ;;
  *) echo "warning: the shell was started, but its log doesn't say yet whether it loaded (taris shell -l)" >&2 ;;
  esac
fi
