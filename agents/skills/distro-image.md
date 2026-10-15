# The Repository, the Image and Whole-Install Tests

Read this before working under `distro/`, or on anything that only shows on a fresh install: the
first-boot setup screen, the greeter and login, disk encryption, factory reset, snapshots, the
image's own setup scripts and what the image ships.

## How it's built

- `distro/config.sh` - where the repository and the image are published, and every package in
  build order.
- `distro/make-signing-key.sh` - once, on the build machine: the key packages are signed with.
- `distro/build-repo.sh [package...]` - builds and signs the packages into `distro/out/repo`
  (installing what a later build needs), fetches and builds the AUR packages it carries (a changed
  AUR PKGBUILD is shown for review first), keeps sources in `distro/out/sources`.
- `sudo distro/build-image.sh` - Arch Linux ARM's root, set up in a chroot by
  `distro/image/scripts/*.sh` from `distro/out/repo`, into a btrfs `root.img` with the EFI
  partition's files, zipped with `installer_data.json` and the macOS command (`install.sh`).
- Publishing is by hand (the user's call): the packages to the `packages` release of
  `TarisOS/tarisOS-packages`, the image as a versioned release of `TarisOS/tarisOS`. Never
  publish anything yourself.

Everything goes into `distro/out/` (git-ignored, big: not `/tmp`).

## Image setup scripts

- They run in order inside the chroot, as root, with `set -euo pipefail`; a failure stops the
  build. Use `pacman_retry` (from `distro/image/files/lib.sh`) for anything that downloads.
- Each one checks what it produced when a mistake would only show at boot (the initramfs has the
  asahi hook, m1n1's boot image has the device trees, every program finds its libraries:
  `60-libraries.sh`). Add a check like that for anything new that would otherwise fail silently.
- Nothing in them may reach the build machine's session: run account-level tools in their own
  namespaces with a throwaway home, as `50-system.sh` does for the greeter's look.

## Testing

There is no disposable machine or VM for TarisOS yet, and this machine is the user's own TarisOS
install. So:

- Package-level changes are tested by building the package and installing it on this machine
  (see [`packaging.md`](packaging.md)).
- Changes to the image, to what it installs, to the setup screen, greeter, encryption or factory
  reset need a fresh image built from the local checkout and installed next to macOS. Say so to the
  user, with the exact build commands, instead of claiming such a change is tested.
- Never run the encryption, factory reset or setup helpers on this machine to "test"
  them: they change the disk or the accounts for real.
- What can be checked without an install, check: `bash -n` on every script, `luac -p` on the
  greeter's Hyprland config, a `makepkg` of the packages involved, and the parts of a helper that
  only read (`/usr/lib/taris/encrypt status`; `pkexec /usr/lib/taris/factory-reset --check`, which
  needs root to look at the volume and changes nothing).
