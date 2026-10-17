# TarisOS: Rules for Coding Agents

This machine runs TarisOS: Arch Linux ARM on an Apple Silicon Mac (Asahi Linux), with Hyprland and
the Taris shell. These rules apply to every session, before any skill.

## Which machine this is

- **`/etc/taris/dev-machine` exists:** a TarisOS development machine. Read
  `/usr/share/taris/agent-rules-dev.md` before doing anything else and follow it. It takes
  precedence over this file and over the TarisOS skills wherever they disagree.
- **Otherwise:** the person you work with is a TarisOS user. Everything you change is their own
  configuration, laid on top of TarisOS: in their home folder, or in the places TarisOS leaves for
  the administrator (named in the skills). Never change TarisOS's own files: anything a package
  owns (`pacman -Qo <file>` tells), `/usr/`, and the installed shell in
  `/etc/xdg/quickshell/taris/`. Updates replace them. Changing TarisOS itself is development: only
  when the user asks for it, in its source (https://github.com/TarisOS/tarisOS).

## Working rules

- Do exactly what is asked: nothing less, nothing more. When something is unclear, ask, but first
  re-read the conversation: never ask what the user already answered.
- Find causes from evidence before changing anything: logs (`taris shell -l`, `journalctl`), live
  state (`hyprctl`, `pactl`, `nmcli`) and the files involved. Don't present guesses as facts; say
  plainly when something is still unexplained.
- Prefer the simplest change that solves the problem without breaking anything else.
- Before a change, check what it could affect and say so. Back up a file before editing it:
  `cp file file.bak.$(date +%s)`.
- Privileges: `sudo` when a terminal is there for the password, `pkexec` when it isn't. An account
  locks for 10 minutes after 10 failed passwords: never retry a failing one, tell the user.
- Say so before restarting the shell (`taris shell -r`) or Hyprland, removing packages or deleting
  anything large.
- This is Apple Silicon (aarch64, 16 KB memory pages, Asahi's kernel and drivers). Advice written
  for x86 PCs or other Linux hardware often doesn't apply: check it against this machine first.
- `/tmp` is in RAM: no big downloads or builds there.
- Never touch macOS: its partitions and files, the startup disk, recoveryOS or the EFI system
  partition. Give the user instructions instead (the mac-and-dual-boot skill).
- Never restore a backup or run a factory reset for the user: they replace the whole system. Point
  them to Settings > Backup & restore.

## Skills

Read the matching skill before working on its topic. They are in
`/usr/share/taris/agent-skills/<name>/SKILL.md` if your agent hasn't loaded them.

| Skill | Topics |
|-------|--------|
| taris | The shell: bar, dock, launcher, notifications, lock, idle, wallpaper, colours and themes, window style, the Settings app, screenshots and recording |
| asahi-desktop | Hyprland (keys, windows, workspaces), terminals, configs in `~/.config/`, the user's own scripts and autostart, packages basics, bug reports |
| apps-on-arm | Installing apps: which source, x86-only apps, Steam, streaming video |
| updates-and-recovery | Updates, `.pacnew` files, snapshots and backups, a broken update, the desktop not starting, the kernel and boot |
| displays | Built-in and external displays, adapters, arrangement, brightness, night light |
| audio | Speakers, headphones, microphone, spatial audio, Bluetooth audio |
| apple-silicon-hardware | Battery, sleep, fans, Touch Bar, camera, keyboard and trackpad, what the hardware supports |
| network-and-privacy | Wi-Fi, VPN, Tor, KDE Connect, the firewall |
| mac-and-dual-boot | macOS alongside TarisOS: instructions only |
| diagnose-crash | A program that crashed, and reporting a confirmed bug |
