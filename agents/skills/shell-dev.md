# Taris Shell Development

Read this before editing the Taris shell under `shell/`.

The shell runs as a single long-running process: Hyprland's autostart starts it with
`taris shell -d`, which runs `taris-qs -c taris` on the installed copy
(`/etc/xdg/quickshell/taris`, from the `taris-shell` package). The same QML also runs as the greeter
(`greeter.qml`) and the first-boot setup screen (`setup.qml`) under greetd. Do not start extra
Quickshell instances for single components.

## Testing a change without installing it

QML changes run straight from the checkout. Stop the installed shell, then run the checkout's in a
terminal (Ctrl+C stops it):

```bash
taris shell -k
taris-qs -p ~/Documents/Projects/tarisOS/shell/shell.qml
```

`taris shell -d` brings the installed shell back. The checkout's `shell.qml` watches its files and
reloads on save. IPC to the test shell goes through `taris-qs -p <path to shell.qml> ipc call ...`
(`taris shell` and `taris-qs -c taris` address the installed one).

The C++ plugin (`shell/plugin/`, the `Taris.*` modules, including every config default) is not
reloaded from the checkout. Build it into the git-ignored `shell/build/` and put it first on the
import path:

```bash
cmake -S shell -B shell/build -G Ninja -DVERSION=1.0.0 -DGIT_REVISION=dev
cmake --build shell/build
QML_IMPORT_PATH=$PWD/shell/build/qml taris-qs -p shell/shell.qml
```

The `-D` options keep CMake from running git. The build needs `cmake ninja qt6-shadertools`.
Anything packaged around the shell (dependencies, the polkit rule, files outside `shell/`) is only
tested by building and installing its package (see [`packaging.md`](packaging.md)), or with
`./install.sh`, which also restarts the shell.

## Checks before handing over

- `/usr/lib/qt6/bin/qmllint -I shell/build/qml -I /opt/quickshell-taris/lib/qt6/qml -I /usr/lib/qt6/qml <files>`
  (without a build, drop the first `-I`). Look for `non-existent`, `Cannot assign`,
  `default property`, `is not a type` and import failures other than `qs.*`; qmllint can't resolve
  the shell's own `qs.*` modules, so check by hand that every type used comes from an imported
  `qs.*` folder. Known noise: `qs.*` imports, members on singletons (`Hypr`, `Colours`…), Repeater
  `required` properties.
- `python3 -I shell/scripts/qml-lint-conventions.py --file <file>` for every QML file you changed:
  leave no violation of your own (the section order is id, properties, signals, functions,
  bindings, children, components).
- `python3 -I shell/scripts/trs-check.py`: no new translation errors in your files. User-facing
  text goes through `Tr.tr()` / `Tr.trCtx()` (`Taris.I18n`).
- Scripts under `shell/assets/`: `bash -n`, Python `python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' <file>`.
- A broken QML file stops the whole shell from loading: after a test run, check `taris shell -l`
  (or the test shell's output) for errors.

## How the shell is put together

- `shell.qml` starts the services (`modules/ServiceLoader.qml`) and the per-screen panel window
  (`modules/drawers/`): one full-screen layer surface per screen holding the bar, the panels and
  the popouts, with an input mask (`Regions.qml`) so clicks pass through everywhere else.
- Panels stay open with `HyprlandFocusGrab`. A grab is only cleared, and its `cleared` signal
  sent, when the compositor clears it (a click on a surface outside it); setting `active` to false
  removes it silently. While a grab is active Hyprland gives keyboard focus to nothing outside it,
  and when the grab ends it refocuses by the pointer. So any new surface that must take clicks or
  keys while a panel is open (the polkit prompt, the area picker) turns the grabs off first:
  `ShellState.grabsReleased`.
- Keyboard focus inside a window: setting `focus = true` on an item after a child has taken focus
  takes it back from the child. Give focus to a container before creating what goes in it.
- Overlays (Settings, the Store, the file picker, the terminal) are the bar popouts' detached
  modes (`modules/bar/popouts/Wrapper.qml`); they log why they close (`taris shell -l`).
- Config: `Config` / `GlobalConfig` (per screen / global) come from the plugin
  (`shell/plugin/src/Taris/Config/`), sizes and fonts from `Tokens`. Colours come from the
  `Colours` singleton; never name anything `Color` (Qt 6.12 adds a `Color` type to `QtQuick`
  that would shadow it).
- When a question depends on Quickshell's or Hyprland's behaviour, read their source at the exact
  installed versions (`hyprctl version` gives Hyprland's commit; Quickshell's is in
  `pacman -Q quickshell-taris`) instead of assuming.

## IPC

`taris shell <target> <function> [args]` is the canonical entry point (`taris shell -s` lists every
target and function); it forwards to the running shell and does not start it. Targets are named
for what they control: `drawers`, `lock`, `notifs`, `wallpaper`, `brightness`, `mpris`, `nexus`,
`store`, `picker`, `filepicker`, `idleInhibitor`, `gameMode`, `toaster`, `hypr`, `audio`.
Hyprland binds the shell's global shortcuts as `hl.dsp.global("taris:<name>")`.

## Editing files with glyphs

Some files carry Nerd Font glyphs as raw unicode characters (the bar's workspace labels in
`plugin/src/Taris/Config/barconfig.hpp`, the README's example config). File-editing tools can strip
multi-byte codepoints in some positions: do not rewrite those files wholesale. For glyph fixes,
make a targeted edit with the surrounding context, or use a Python script that inserts codepoints
with `chr(0xXXXXX)`.
