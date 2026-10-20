---
name: updates-and-recovery
description: >
  Updating this TarisOS Mac and getting it back when something goes wrong: system updates,
  .pacnew files, snapshots before package changes, whole-system backups, a broken or interrupted
  update, the desktop not starting, the kernel, the initramfs, GRUB and m1n1's boot image.
  Triggers: update, upgrade, pacman, pacnew, snapshot, snapper, backup, restore, rollback,
  downgrade, broken after update, won't boot, black screen, login loop, kernel, initramfs,
  mkinitcpio, GRUB, kernel parameters, m1n1, DKMS.
---

# Updates and Recovery

On a TarisOS development machine (`/etc/taris/dev-machine`), the development rules
(`/usr/share/taris/agent-rules-dev.md`) take precedence over this skill wherever they disagree.

## Updating

- **Everything at once:** Settings > Updates, or `/usr/lib/taris/update` in a terminal: Arch
  Linux ARM, Asahi's repository, TarisOS's, the AUR, then Flatpak apps. It picks fresh mirrors
  first.
- Never update one package alone with fresh package lists (`pacman -Sy <pkg>`): that's a partial
  upgrade, and can leave the system unable to start.
- A snapshot of the system is taken before every package change (the last 10 are kept).
- After an update to the kernel, drivers or boot files, restart the Mac. After an update to the
  shell (`taris-shell`), log out and back in: the running shell keeps its old files until then.

## Configuration files after an update (.pacnew)

When an update brings a new version of a file in `/etc` that was edited here, pacman keeps the
edited one and puts the new one next to it as `<file>.pacnew`:

```bash
sudo find /etc -name '*.pacnew'
diff /etc/<file> /etc/<file>.pacnew
```

Merge what the user wants from the new file into theirs (with their yes), then remove the
`.pacnew`. TarisOS's own editable files work the same way, e.g. `/etc/default/update-m1n1` and
`/etc/taris/factory-reset.keep`. (The Touch Bar's settings are the owner account's own file instead:
the taris skill.)

## Something broke after an update

1. What changed: `grep -E 'upgraded|installed|removed' /var/log/pacman.log | tail -40`.
2. Evidence: `journalctl -b -p warning`, `journalctl --user -b`, `taris shell -l` for the shell.
3. The simplest way back, with the user's yes:
   - **One package:** install its previous version from pacman's cache, if it's still there:
     `ls /var/cache/pacman/pkg/<name>-*`, then `sudo pacman -U /var/cache/pacman/pkg/<file>`.
   - **One transaction's file changes:** `sudo snapper list` shows a pre and post snapshot for each
     package change; `sudo snapper status <pre>..<post>` lists what it changed, and
     `sudo snapper undochange <pre>..<post>` puts those files back. Not for kernel or boot updates:
     m1n1's boot image on the EFI partition isn't in the snapshots and would no longer match.
   - **The whole system:** a backup (below).
4. Report a TarisOS bug if the cause is in TarisOS (the asahi-desktop skill, Reporting Bugs).

## Backups and factory reset

Settings > Backup & restore makes whole-system backups (the system and every account's files, at
most 20, on demand or on a schedule) and restores one at the next start. It also has the factory
reset, which brings back the system exactly as installed and erases every account and file.

Never restore a backup or run a factory reset for the user: both replace the whole system. Tell
them where it is and what it will do; they choose. From a text console (below), a backup can also be
restored with `sudo /usr/lib/taris/backup restore <id>`, which restarts the Mac at once
(`/var/lib/taris/backups.json` lists them with their ids); give that to the user to run themselves.

## An interrupted update

If an update stopped half way (power, a crash), finish it before anything else:

```bash
pgrep -x pacman || sudo rm -f /var/lib/pacman/db.lck   # only when no pacman is running
sudo pacman -Syu
```

## The desktop doesn't start

The login screen is the shell itself, so a broken shell or Hyprland can leave a black screen.

1. Switch to a text console, then log in: Ctrl+Alt+F3. On the desktop Ctrl is the ⌘ Command key
   (TarisOS swaps them unless Settings > Keyboard & trackpad says otherwise); on the login screen
   and on a text console it's the key labelled control. On a MacBook with a Touch Bar, hold fn too
   so it shows F1–F12.
2. Look: `journalctl -b -p warning`, `/var/log/pacman.log` for a recent or unfinished update.
3. Finish or repair the update (above), then `sudo systemctl restart greetd` or restart the Mac.

## Kernel and boot

The Mac starts m1n1 (Asahi's boot loader), then U-Boot, GRUB and the kernel (`linux-asahi`).

- **Kernel parameters:** in a file of the user's own, `/etc/default/grub.d/<name>.cfg` (never the
  `taris*.cfg` ones, which belong to TarisOS), e.g.
  `GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT <option>"`, then
  `sudo grub-mkconfig -o /boot/grub/grub.cfg`.
- **Initramfs:** modules and hooks in `/etc/mkinitcpio.conf.d/<name>.conf` of the user's own (not
  `taris-*.conf`), then `sudo mkinitcpio -P`.
- **m1n1:** its options (`display=`, `chosen.*`) in `/etc/m1n1.conf`, then `sudo update-m1n1`.
  `/etc/default/update-m1n1` is TarisOS's (it gives m1n1 the device trees with the M1's USB-C
  display): keep its lines when editing it.
- **TarisOS's own drivers** (`taris-tipd-dkms`, `taris-appledrm-dkms` for USB-C displays,
  `taris-brcmfmac-dkms` for the Wi-Fi's power saving) are built by DKMS for one kernel only. After
  a kernel update they may be skipped until TarisOS updates them: the Mac works as usual, only the
  M1's USB-C display stays dark and Wi-Fi uses a little more power. `dkms status` shows it.
