# Visual Verification

Read this before finishing any change with a visual effect: the shell's styling and layout, its
panels, overlays, menus, notifications and lock screen, the greeter and setup screen, window
behaviour (tiling, floating, sizes, focus), animations and transitions, and the screenshot and
screen recording flows.

Visual changes must be verified in the running UI in addition to the checks in `AGENTS.md`.
Creating an artifact is not sufficient: inspect it for clipping, overlap, incorrect spacing,
wrong colours, stale state, focus problems and visual regressions before finishing. Do not hand the
verification to the user when you can do it yourself.

This machine is the user's own desktop: keep checks short, close everything you
open, and restore anything you change.

On a TarisOS development machine (`/etc/taris/dev-machine`) the agent takes no screenshots or
recordings and never moves the pointer: read the state as below, and hand what shows on screen to
the maintainer to check ([`dev-machine.md`](dev-machine.md)).

## State first

Most behaviour can be read directly, which beats looking at pixels:

```bash
hyprctl clients -j | jq '.[] | {class, floating, fullscreen, fullscreenClient, size, at}'
hyprctl monitors -j
hyprctl layers -j                 # the shell's surfaces and their layers
hyprctl getoption <option> -j     # a config value as Hyprland has it
hyprctl configerrors
taris shell -l                    # the shell's log: QML errors, why an overlay closed
```

Example: to check how a new window opens, start it in the background, wait for it to map, read its
entry, then stop it:

```bash
kitty >/dev/null 2>&1 & pid=$!; sleep 2.5
hyprctl clients -j | jq -c --argjson p $pid '.[] | select(.pid == $p) | {floating, fullscreen, size, at}'
kill $pid
```

## Screenshots

Take a full-screen screenshot without opening the editor:

```bash
grim /tmp/shot-$(date +%s).png
```

`taris screenshot` runs the interactive flow (region picker, then swappy). Capture reference and
candidate states as separate images when changing a layer-shell surface or layout, then compare
both. Look at every image you take.

## Recordings

Record a short full-screen video for animation, transition, timing, window-movement, capture or
screen-recording changes:

```bash
wf-recorder -f /tmp/check.mp4 & rec=$!
# Exercise the changed behaviour.
kill -INT $rec
```

`taris record` (`-r` for a region) is the user-facing flow. To look at a recording (yours or the
user's, in `~/Videos/Recordings`), extract contact sheets of frames and read those:

```bash
mkdir -p /tmp/frames
ffmpeg -v error -i <video> -vf "fps=2,scale=1000:-1,tile=4x3" /tmp/frames/sheet_%02d.png
```

Keep recordings short and focused on the changed behaviour, and delete the scratch files after.

## Input

Global shortcuts can be fired without a keyboard: `hyprctl dispatch 'hl.dsp.global("taris:<name>")'`
(for example `taris:launcher`, `taris:screenshot`). For typing into a focused control, use `wtype`
when it is installed (`wtype -k Escape`, `wtype 'text'`); it is not part of the image
(`sudo pacman -S --needed wtype`). `wtype` does not prove that a Hyprland keybinding works: fire
the global shortcut instead, or ask the user to press the key.

If a launched UI would otherwise remain open, keep track of its PID and stop it after the
screenshot or recording; avoid broad process kills unless you check with `ps` first.

## What can't be seen from here

The greeter, the setup screen, the lock screen's session lock and the disk-password screen only
run on a fresh install or at login. Verify them on a fresh image (see
[`distro-image.md`](distro-image.md)); never lock the user's session or log them out to check.
