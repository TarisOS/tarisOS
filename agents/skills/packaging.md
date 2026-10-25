# Packaging

Read this before working under `packaging/`: the PKGBUILDs, the helpers they install to
`/usr/lib/taris`, pacman hooks, install scripts, the Hyprland config, the defaults and the agent
skills TarisOS ships.

TarisOS is configuration as packages: every fix or default is a file owned by a pacman package, so
updates reach installed machines and removing the package undoes it. The image installs the
`taris` meta package and the default apps; nothing else configures the system.

## Where things go

- `packaging/pkgbuilds/<package>/` - one folder per package: its PKGBUILD and the files it
  installs. `taris-shell`, `taris-desktop` and `taris-wallpapers` also read files from the
  repository itself (`$startdir/../..`: `shell/`, `packaging/hypr/`, `packaging/defaults/`,
  `packaging/agents/skills/`, `packaging/wallpapers/`).
- Which package owns what: hardware fixes in `taris-hardware`, the login, greeter, setup screen and
  disk encryption in `taris-login`, Hyprland's config, a new account's defaults and the system's
  name in `taris-desktop`, snapshots and factory reset in `taris-snapshots`, Chromium's settings in
  `taris-chromium`, the firewall in `taris-firewall`, everything through Tor (its own Tor, the
  rules that send everything to it, the time through it) in `taris-tor`, thumbnails that never
  outlive their files' contents in `taris-thumbnails`. Packages built only because Arch Linux ARM
  lacks them sit next to them, and so do TarisOS's patches to other packages: `quickshell-taris`
  beside Quickshell (in `/opt`); `tiny-dfr-taris` and `speakersafetyd-taris`, which build Asahi's
  installed version with TarisOS's patches (see "Patches that follow every version" below).
  `distro/config.sh` lists every package in build order.
- System-wide defaults go where programs read them for every account (`/etc/xdg/...`,
  `/usr/share/taris/...`), not into home folders. Only what can't work that way goes into
  `user-defaults` (see [`upgrades.md`](upgrades.md)).
- Root-scoped hardware setup belongs to `taris-hardware`; per-account setup to `taris-desktop`'s
  `user-defaults`. Keep it clear what runs as root and what runs for each account.

## Rules

- Bump `pkgrel` whenever a package's content changes (the version is `1.0.0`; `pkgver` changes
  with a release). Installed machines only update when the version goes up. One bump per release
  of the package is enough: don't bump again for further changes before it is published.
- After changing any file in a package's `source=()`: `updpkgsums` in its folder.
- Files an administrator may edit go in `backup=()`.
- Services that are always on are enabled by the package itself (a `*.wants/` link in the
  package), so there is no enabling step to forget and nothing left behind on removal.
- Hooks: name them for what they do, order them with a numeric prefix where order matters
  (`00-` before, `zz-` after other hooks), and make their command a no-op on a machine where its
  precondition is missing.
- Install scripts (`*.install`): idempotent, safe to run on every upgrade; `post_upgrade` usually
  calls `post_install`.
- Dependencies: everything a package's files run is in `depends=()`; programs that are optional
  for it go in `optdepends=()`. A missing dependency only shows on a fresh install, never on this
  machine (which has everything), so check new commands against the package.
- Every helper in `/usr/lib/taris` starts with the copyright header and a comment saying what it
  does, who runs it (a service, a hook, Settings through `pkexec`…) and its usage lines, as the
  existing helpers do. Root helpers run through `pkexec` validate every argument and refuse what
  they don't expect.
- Raw `pacman`, `command -v` and `pacman-key` are fine in package and build tooling, where direct
  package-manager behaviour is the point.

## Patches that follow every version

No TarisOS fix may rely on a specific version of what it fixes (the maintainer, 2026-10-23): each
applies itself to whatever version is installed, idempotently, and leaves a version it doesn't fit
as it is.

- Kernel drivers: the DKMS packages and `asahi-source.sh` (next section).
- Programs from Asahi's repository (`tiny-dfr-taris`, `speakersafetyd-taris`): Asahi's package
  stays installed. Ours carries only the patches, `asahi-package.sh` (the same script in both; what
  each builds is in its `asahi-package.conf`), a pacman hook and a systemd drop-in. The hook runs
  the script after Asahi's package or ours is installed or upgraded: it fetches Asahi's packaging
  for the installed version (asahi-alarm/PKGBUILDs; their sources, checksums and patches), runs
  their `prepare()`, applies TarisOS's patches (skipped when the source has them, the build stops
  when one doesn't apply), runs their build as `nobody` and keeps the binary in
  `/var/lib/taris/asahi-package/<package>/`. The drop-in bind-mounts it over the stock binary
  (`BindReadOnlyPaths=-...`) only while one exists for the installed version, so the stock binary
  runs otherwise. When Asahi's packaging has moved past the installed version, the build waits for
  the next upgrade. To change a patch: edit it, rebuild the package; the hook builds again.
- TarisOS's own builds of other projects (`quickshell-taris` from Quickshell's git, `taris-music`'s
  cpal): each patch is skipped when the source has it and applied while it fits; the build stops
  when it doesn't, and the patch has to be brought up to date.
- Device trees (`usb-c-display`) follow the tree's structure, not a kernel version.

## Drivers patched for every kernel

`taris-tipd-dkms`, `taris-appledrm-dkms`, `taris-brcmfmac-dkms` and `taris-bcm4377-dkms` patch
drivers of Asahi's kernel without carrying its source: each holds only TarisOS's patches,
`asahi-source.sh` (the same script in all four) and `asahi-source.conf` (which source folders, which
patches). DKMS builds them for every kernel installed (its pacman hook), and before each build
`asahi-source.sh` takes Asahi's tag from the kernel release (`7.2.12-1-1-ARCH`: `asahi-7.2.12-1`),
fetches just those folders (a shallow, sparse clone, cached in `/var/cache/taris-dkms`), and applies
the patches. A patch the source already has is skipped. One that no longer applies stops that build,
and the kernel's own driver loads instead: the M1's USB-C display stays dark, a USB-C display
unplugged while on breaks modesetting until a restart, the Wi-Fi link stays in L1 (about 0.2 W
more), or Bluetooth can die on waking from sleep until a restart. Nothing needs doing per Asahi
release, except when a patch stops applying:

- bring the patch up to date against the new source (DKMS's `make.log` for that kernel says which
  one stopped), and test it as the build does: `asahi-source.sh <kernel release>` in a copy of the
  package's folder, then `make -C /usr/lib/modules/<release>/build M=$PWD modules`;
- without a network at the kernel update the build stops too: `sudo dkms autoinstall` builds it
  later.

`usb-c-display` (taris-hardware) patches the device trees of each kernel the same way, by their
structure: it leaves a tree it doesn't recognise as it is and says so in pacman's output (Asahi
moved the display DARTs from one cell to five in 7.2: it follows the cells the tree has).

## Checks before handing over

- Shell scripts `bash -n` (initramfs hooks `sh -n`), Lua `luac -p`, Python `ast.parse`,
  nftables in a throwaway namespace (`unshare -rn nft -f <file>`).
- Build the package: `makepkg -f -c` in its folder (`-d` to skip installed-dependency checks).
  Look inside the result (`bsdtar -tf` for the file list, `bsdtar -xOf <pkg> <path>` for a file)
  to confirm it carries the change. The package file is git-ignored; delete it when done unless
  the user is testing it.
- Test on this machine by installing the build: `pkexec pacman -U <package file>`
  (the password prompt appears on the user's screen). Then check the effect where it applies:
  `hyprctl configerrors` and `hyprctl getoption` for Hyprland's config, the service's status for a
  unit, the running program for its config.
- For a script that writes into a home folder, run it against a throwaway home first
  ([`upgrades.md`](upgrades.md) shows how).
