# Changing Installed Machines

Read this before making a change that has to reach machines that are already installed.

TarisOS has no migration runner. Installed machines change only through package updates
(`/usr/lib/taris/update`, Settings > Updates), so every change has to arrive as one of these, in
this order of preference:

1. **A file the package owns, read at runtime.** The new version replaces the old on update and
   takes effect for every account at once: Hyprland's config in `/usr/share/taris/hypr/`, kitty's
   in `/etc/xdg/kitty/`, bash's extras in `/usr/share/taris/bashrc`, helpers in `/usr/lib/taris/`.
   Prefer this whenever the program can read a system-wide file.
2. **A pacman hook or the package's install script** (`*.install`, `post_upgrade`) for state
   pacman can't own by itself on the system side: it runs as root, during the update, once.
3. **`user-defaults`** for an account's own files. It runs once per account (`--if-new`, at the
   first login, or from the setup screen), so a change to it reaches new accounts only, never
   existing ones.

There is no way yet to change files in existing accounts' home folders on update. When a change
needs that, say so to the user instead of inventing a mechanism.

## Rules for install scripts and hooks

- Idempotent: check the state before changing it; running twice changes nothing more.
- Never restart the shell or Hyprland from them; the update runs while the user works.
- Machine-wide repairs run as root, in the update's transaction: no prompts, no network unless
  the hook is about the network (the title bar plugin's build).
- Say what they do: hooks have a `Description =` that reads as an action ("Rebuilding the
  initramfs for TarisOS's settings...").
- A repair that deletes a file the old version left behind matches exactly what the old version
  produced, and leaves anything an administrator wrote alone.

## Rules for user-defaults

- It runs as the account, with that account's `HOME` and XDG folders, and without a running shell
  or session (from the setup screen, and in the image build with a throwaway home for the greeter's
  look). It must produce a complete result by itself: nothing it leaves may depend on the shell
  running later (the setup screen's brown colours came from that).
- It never replaces what the account already has: check first, and only fill in what is missing.

## Testing against a throwaway home

Never run a script that writes into a home folder against the user's. Run it in a throwaway
home, in its own user and PID namespaces with an empty `/dev/pts`, so nothing reaches the running
session (the `taris` CLI writes colours to every terminal and signals running apps):

```bash
look=$(mktemp -d)
unshare -r -m --pid --fork --mount-proc sh -c 'mount -t tmpfs none /dev/pts; exec env -i PATH=/usr/bin HOME="$1" XDG_CONFIG_HOME="$1/.config" XDG_STATE_HOME="$1/.local/state" XDG_DATA_HOME="$1/.local/share" XDG_CACHE_HOME="$1/.cache" LANG=en_US.UTF-8 "$2"' sh "$look" packaging/pkgbuilds/taris-desktop/user-defaults
```

Then inspect what it left in `$look`, compare against the installed version run the same way, and
run it twice to show it is idempotent. `sudo -n` inside it logs a harmless "unable to open
/etc/sudoers" (it runs as a fake root).
