---
name: mac-and-dual-boot
description: >
  macOS alongside TarisOS on this Mac: choosing which system starts, moving files between them,
  disk space and partitions, removing TarisOS, recoveryOS. Instructions for the user only: the
  agent never touches macOS, its files, the startup disk, partitions or recovery. Triggers: macOS,
  dual boot, boot into macOS, startup disk, default OS, boot picker, startup options, recoveryOS,
  recovery mode, macOS files, APFS, partition, resize, disk space, uninstall TarisOS, remove
  Linux.
---

# macOS and TarisOS

On a TarisOS development machine (`/etc/taris/dev-machine`), the development rules
(`/usr/share/taris/agent-rules-dev.md`) take precedence over this skill wherever they disagree.

## Hard limits

This skill is instructions only. Whatever the user asks, never:

- mount, read or write macOS's partitions or files, even read-only;
- change the startup disk or the default system (including tools like `asahi-bless`), or touch
  recoveryOS;
- create, delete, resize or format partitions (`diskutil`, `fdisk`, `parted`, `gdisk`, `mkfs`...);
- touch the EFI system partition by hand. TarisOS's own updates keep its boot files current.

macOS's data, and the Mac's ability to start at all, are at stake: a wrong step can erase macOS or
leave the Mac unable to start. When asked to do any of this, say it isn't allowed and why, then give
the user the steps below to follow themselves.

## Steps to give the user

**Choose the system at startup:** shut the Mac down, then press and hold the power button until
"Loading startup options" appears. Pick TarisOS or macOS, then Continue.

**Change which system starts by default:** in macOS, System Settings > General > Startup Disk:
choose the system, then Restart.

**Move files between them:** a USB drive formatted as exFAT (both systems read and write it), or a
cloud service both can use. AirDrop isn't available on TarisOS; KDE Connect covers phones.

**recoveryOS:** at the startup options, choose Options. Use it only for what Apple's or Asahi
Linux's instructions say; it can erase the disk.

**Disk space, resizing, or removing TarisOS:** always from macOS, following Asahi Linux's
partitioning guide (https://asahilinux.org/docs/sw/partitioning-cheatsheet/). Back up first, and
check each partition's name and size before deleting anything: a wrong one is macOS.
