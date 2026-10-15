#!/usr/bin/env python3
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

"""Stash: the apps that are open, kept across a shut down (the shell's Stash, instead of sleep).

Apple Silicon can't hibernate and its sleep keeps drawing power, so Stash records every window
(app, workspace, floating or tiled, position, size, pinned, fullscreen), has each app keep its own
work, closes the apps and lets the shell shut down. At the next login the shell restores them: the
apps open again and each window goes back where it was.

How each app keeps its work, without a "Save changes?" prompt holding up the shut down:
- Chromium and its web apps: quit with SIGTERM, which it takes as the session ending (no prompts,
  the session kept); opened again with --restore-last-session. Its web app windows aren't in that
  session, so each opens again from its launcher.
- VSCodium (and VS Code): quit with SIGTERM; it keeps unsaved files on disk as they're typed and opens its
  windows and those files again.
- kitty: each tab's folder, and the editor or viewer running in it, go into a kitty session file;
  kitty quits on SIGTERM without asking.
- imv and mpv: quit with SIGTERM (nothing unsaved; imv ignores being asked to close) and open
  again with the file they had.
- Neovim, in kitty: its unsaved buffers are written to the stash and its windows to a session,
  over its socket, and it quits; it opens again with that session and the unsaved buffers, still
  unsaved.
- GNOME Text Editor: keeps unsaved documents as drafts as they're typed and in its session when
  asked to close; it opens them again by itself.
- qBittorrent: quits with SIGTERM, cleanly (no prompt about active torrents).
- Every other app is asked to close its windows, as clicking their close button does, and opens
  again from its launcher, with the files it had open.
Whatever is still open after the wait (an app at a prompt) is made to quit, SIGTERM then SIGKILL:
Stash always ends in the shut down.

The state is ~/.local/state/taris/stash.json: its being there is what says the last shut down was
a Stash. restore takes it away first, so it's only ever restored once.

  stash.py save      record, close the apps (forcing the ones that don't); the shell shuts down
  stash.py restore   open the apps again and put their windows back (nothing without a Stash)
"""

import json
import os
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "taris"
STASH = STATE / "stash.json"
SESSIONS = STATE / "stash"
LAUNCH_WEBAPP = Path(__file__).resolve().parent / "launch-webapp.sh"

CLOSE_WAIT = 5  # Seconds the apps get to close before they're made to
FORCE_WAIT = 3  # Seconds after SIGTERM before SIGKILL
RESTORE_WAIT = 60  # Seconds windows are waited for after opening the apps again

# Viewers that keep nothing unsaved and don't all close when asked (imv ignores it): quit with
# SIGTERM instead
VIEWERS = {"imv", "mpv"}

# Apps that open their own last session (windows, documents): opened again without files
SESSION_APPS = {"org.gnome.texteditor"}

# Programs in a terminal that come back with it (an editor, a viewer); anything else running then
# (a build, an install, ssh) isn't started again by itself
TERMINAL_PROGRAMS = {"nvim", "vim", "vi", "nano", "micro", "hx", "helix", "less", "man", "htop", "btop", "top"}


def hyprctl_json(what: str):
    return json.loads(subprocess.run(["hyprctl", "-j", what], capture_output=True, text=True, check=True).stdout)


def dispatch(lua: str) -> None:
    subprocess.run(["hyprctl", "dispatch", lua], capture_output=True)


def lua_str(s: str) -> str:
    return json.dumps(s)  # A JSON string is a valid Lua string literal for these (no control characters)


def cmdline(pid: int) -> list[str]:
    try:
        return [a for a in Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace").split("\0") if a]
    except OSError:
        return []


def cwd(pid: int) -> str:
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return str(Path.home())


def children(pid: int) -> list[int]:
    try:
        return [int(c) for t in os.listdir(f"/proc/{pid}/task") for c in Path(f"/proc/{pid}/task/{t}/children").read_text().split()]
    except OSError:
        return []


def foreground_group(pid: int) -> int:
    # The terminal's foreground process group (tpgid): field 8 of stat, after the name in brackets
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        return int(stat[stat.rindex(")") + 2 :].split()[5])
    except (OSError, ValueError, IndexError):
        return -1


# Launchers (.desktop files), for opening an app again by its window's class
def desktop_entries() -> list[dict]:
    dirs = [Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")]
    dirs += [Path(d) for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    entries, seen = [], set()
    for d in dirs:
        apps = d / "applications"
        if not apps.is_dir():
            continue
        for f in sorted(apps.rglob("*.desktop")):
            entry_id = str(f.relative_to(apps)).replace("/", "-")
            if entry_id in seen:
                continue
            seen.add(entry_id)
            keys, section = {}, None
            try:
                for line in f.read_text(errors="replace").splitlines():
                    line = line.strip()
                    if line.startswith("["):
                        section = line
                    elif section == "[Desktop Entry]" and "=" in line:
                        k, v = line.split("=", 1)
                        keys.setdefault(k.strip(), v.strip())
            except OSError:
                continue
            if keys.get("Type") == "Application" and keys.get("Exec") and keys.get("Hidden") != "true":
                keys["id"] = entry_id.removesuffix(".desktop")
                entries.append(keys)
    return entries


def exec_args(entry: dict) -> list[str]:
    try:
        args = shlex.split(entry["Exec"])
    except ValueError:
        return []
    # Field codes (%f, %U...) are for files passed in: none here
    return [a for a in args if not (len(a) == 2 and a[0] == "%")]


def entry_for_class(entries: list[dict], cls: str) -> dict | None:
    low = cls.lower()
    # An app's own launcher before the hidden ones it may also have (VS Code's URL handler)
    entries = sorted(entries, key=lambda e: e.get("NoDisplay") == "true")
    for match in (
        lambda e: e.get("StartupWMClass", "").lower() == low,
        lambda e: e["id"].lower() == low,
        lambda e: e["id"].lower().rsplit(".", 1)[-1] == low,
        lambda e: Path(exec_args(e)[0] if exec_args(e) else "").name.lower() == low,
    ):
        for e in entries:
            if match(e):
                return e
    return None


def webapp_class(url: str) -> str:
    # Chromium names an --app window's class after the address: chrome-<host>_<path, / as _>-Default
    rest = url.split("://", 1)[-1]
    host, _, path = rest.partition("/")
    return f"chrome-{host}_{('/' + path).replace('/', '_')}-Default"


def webapp_command(entries: list[dict], cls: str) -> list[str]:
    for e in entries:
        args = exec_args(e)
        if len(args) == 2 and args[0].endswith("launch-webapp.sh") and webapp_class(args[1]) == cls:
            return args
    # Not one of the account's web apps: its address again from the class
    middle = cls.removeprefix("chrome-").rsplit("-", 1)[0]
    host, _, path = middle.partition("__")
    return [str(LAUNCH_WEBAPP), f"https://{host}/{path.replace('_', '/')}"]


def kind_of(client: dict) -> str:
    cls = client["class"]
    exe = Path(cmdline(client["pid"])[0] if cmdline(client["pid"]) else "").name.lower()
    if cls.startswith("chrome-") and exe in ("chromium", "chrome"):
        return "webapp"
    if exe in ("chromium", "chrome") or cls.lower() == "chromium":
        return "chromium"
    if cls.lower() in ("codium", "vscodium", "code") or exe in ("codium", "code"):
        return "code"
    if cls.lower() == "kitty" or exe == "kitty":
        return "kitty"
    if cls.lower() in VIEWERS or exe in VIEWERS:
        return "viewer"
    if exe == "qbittorrent":
        return "qbittorrent"
    return "app"


# Neovim, over its socket: the unsaved buffers written to the stash folder, the windows and tabs to a
# session, then it quits (without leaving swap files behind, which a SIGHUP from kitty would)
NVIM_SAVE = """
local dir = ...
vim.fn.mkdir(dir, "p")
local unsaved = {}
for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.bo[b].modified and vim.bo[b].buftype == "" then
        local file = dir .. "/" .. b
        vim.fn.writefile(vim.api.nvim_buf_get_lines(b, 0, -1, false), file, "b")
        unsaved[#unsaved + 1] = { name = vim.api.nvim_buf_get_name(b), file = file }
    end
end
vim.cmd("mksession! " .. vim.fn.fnameescape(dir .. "/session.vim"))
vim.fn.writefile({ vim.json.encode(unsaved) }, dir .. "/unsaved.json")
vim.schedule(function() vim.cmd("qa!") end)
return "ok"
"""

# Opened again: after the session, each unsaved buffer gets its text back (still unsaved), an unnamed
# one in an unnamed window of the session; one line, for nvim -c
NVIM_RESTORE = (
    "local dir = DIR "
    'local ok, unsaved = pcall(vim.json.decode, table.concat(vim.fn.readfile(dir .. "/unsaved.json"), "\\n")) '
    'local unnamed = vim.tbl_filter(function(b) return vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) == "" end, vim.api.nvim_list_bufs()) '
    "for _, u in ipairs(ok and unsaved or {}) do "
    'local b = u.name ~= "" and vim.fn.bufadd(u.name) or table.remove(unnamed, 1) or vim.api.nvim_create_buf(true, false) '
    "vim.fn.bufload(b) "
    "vim.bo[b].buflisted = true "
    'vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.fn.readfile(u.file, "b")) '
    "end "
    'vim.fn.delete(dir, "rf")'
)


def nvim_stash(pid: int, name: str) -> list[str] | None:
    # The server is the nvim in the terminal or its child (the UI runs it embedded), listening at
    # $XDG_RUNTIME_DIR/nvim.<pid>.0
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    sock = next((s for p in (pid, *children(pid)) if (s := Path(runtime, f"nvim.{p}.0")).is_socket()), None)
    if not runtime or not sock:
        return None
    folder = SESSIONS / f"nvim-{name}"
    expr = f"luaeval({json.dumps('assert(loadstring(_A[1]))(_A[2])')}, [{json.dumps(NVIM_SAVE)}, {json.dumps(str(folder))}])"
    try:
        done = subprocess.run(["nvim", "--server", str(sock), "--remote-expr", expr], capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        return None
    if done.stdout.strip() != "ok":
        return None
    return ["nvim", "-S", str(folder / "session.vim"), "-c", "lua " + NVIM_RESTORE.replace("DIR", json.dumps(str(folder)), 1)]


def kitty_session(pid: int, index: int) -> Path:
    # Each tab (a shell the kitty process runs) as it is: its folder, and its editor or viewer
    lines = []
    for child in children(pid):
        args = cmdline(child)
        if not args or Path(args[0]).name == "kitten":
            continue
        if lines:
            lines.append("new_tab")
        # What runs in the foreground: a program in the tab's shell, the shell itself, or a program
        # the tab was opened with (kitty nvim file)
        group = foreground_group(child)
        in_shell = group > 0 and group != child
        program = cmdline(group) if in_shell else args
        lines.append(f"cd {shlex.quote(cwd(group if in_shell else child))}")
        if program and Path(program[0]).name == "nvim":
            program = nvim_stash(group if in_shell else child, f"{index}-{sum(line.startswith('launch') for line in lines)}") or program
        if program and Path(program[0]).name in TERMINAL_PROGRAMS:
            if in_shell:
                # The shell again once the program quits, as the tab had
                lines.append("launch " + shlex.join(["sh", "-c", '"$@"; exec "${SHELL:-/bin/bash}"', "sh", *program]))
            else:
                lines.append("launch " + shlex.join(program))
        else:
            lines.append("launch")
    SESSIONS.mkdir(parents=True, exist_ok=True)
    path = SESSIONS / f"kitty-{index}.session"
    path.write_text("\n".join(lines or ["launch"]) + "\n")
    return path


def save() -> int:
    clients = [c for c in hyprctl_json("clients") if c.get("mapped", True) and c["pid"] > 0]
    active = hyprctl_json("activeworkspace").get("name", "")
    entries = desktop_entries()
    shutil.rmtree(SESSIONS, ignore_errors=True)

    windows, launches, by_pid = [], [], {}
    for c in clients:
        kind = kind_of(c)
        windows.append(
            {
                "address": c["address"],
                "class": c["class"],
                "workspace": c["workspace"]["name"],
                "floating": c["floating"],
                "at": c["at"],
                "size": c["size"],
                "pinned": c["pinned"],
                "fullscreen": c["fullscreen"],
            }
        )

        # One launch per app instance: Chromium and VSCodium open all their windows again by
        # themselves, a web app or another app once per process
        key = (kind, c["pid"]) if kind != "webapp" else (kind, c["class"])
        if key in by_pid:
            by_pid[key]["addresses"].append(c["address"])
            continue
        if kind == "chromium":
            command = ["chromium", "--restore-last-session"]
        elif kind == "webapp":
            command = webapp_command(entries, c["class"])
        elif kind == "code":
            # VSCodium, or VS Code where it's still the one installed
            args = cmdline(c["pid"])
            vscodium = c["class"].lower() in ("codium", "vscodium") or (args and Path(args[0]).name == "codium")
            command = ["codium" if vscodium else "code"]
        elif kind == "kitty":
            args = cmdline(c["pid"])
            extra = [a for i, a in enumerate(args) if a.startswith("--class") or (i and args[i - 1] == "--class")]
            command = ["kitty", *extra, "--session", str(kitty_session(c["pid"], len(launches)))]
        else:
            args = cmdline(c["pid"])
            entry = entry_for_class(entries, c["class"])
            if entry and exec_args(entry) and c["class"].lower() in SESSION_APPS:
                command = exec_args(entry)
            elif entry and exec_args(entry):
                # Its launcher, with the files it had open (a PDF, a video, an image): the command
                # it runs as can be an internal one (Steam's runtime, Flatpak's sandbox, a GNOME
                # app's service)
                folder = cwd(c["pid"])
                files = [str(Path(folder, a)) for a in args[1:] if not a.startswith("-") and Path(folder, a).is_file()]
                command = exec_args(entry) + files
            else:
                command = args
        launch = {"kind": kind, "pid": c["pid"], "command": command, "addresses": [c["address"]]}
        by_pid[key] = launch
        launches.append(launch)

    STATE.mkdir(parents=True, exist_ok=True)
    state = {
        "active": active,
        "windows": windows,
        "launches": [{"kind": lch["kind"], "command": lch["command"]} for lch in launches],
    }
    tmp = STASH.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(STASH)

    # Close: SIGTERM where it keeps the work without asking (once per process: a second one makes
    # Chromium quit at once), the close button for the rest
    signalled = set()
    for lch in launches:
        if lch["kind"] in ("chromium", "webapp", "code", "kitty", "qbittorrent", "viewer"):
            if lch["pid"] not in signalled:
                signalled.add(lch["pid"])
                try:
                    os.kill(lch["pid"], signal.SIGTERM)
                except ProcessLookupError:
                    pass
        else:
            for a in lch["addresses"]:
                dispatch(f"hl.dsp.window.close({{ window = {lua_str('address:' + a)} }})")

    addresses = {w["address"] for w in windows}

    def wait(seconds: float) -> list[dict]:
        deadline = time.monotonic() + seconds
        while True:
            remaining = [c for c in hyprctl_json("clients") if c["address"] in addresses]
            if not remaining or time.monotonic() > deadline:
                return remaining
            time.sleep(0.25)

    # Still open after the wait (a prompt, or hung): made to quit. Its work is what it already kept
    # (the drafts, backups and sessions above); everything comes back at the next login all the same
    remaining = wait(CLOSE_WAIT)
    if remaining:
        print("Made to quit:", ", ".join(sorted({c["class"] for c in remaining})), file=sys.stderr)
    for sig, seconds in ((signal.SIGTERM, FORCE_WAIT), (signal.SIGKILL, FORCE_WAIT)):
        for pid in {c["pid"] for c in remaining}:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        remaining = wait(seconds) if remaining else []
    return 0


def place(address: str, w: dict) -> None:
    win = lua_str("address:" + address)
    dispatch(f"hl.dsp.window.move({{ window = {win}, workspace = {lua_str(w['workspace'])}, follow = false }})")
    dispatch(f"hl.dsp.window.float({{ window = {win}, action = {lua_str('enable' if w['floating'] else 'disable')} }})")
    if w["floating"]:
        dispatch(f"hl.dsp.window.resize({{ window = {win}, x = {w['size'][0]}, y = {w['size'][1]} }})")
        dispatch(f"hl.dsp.window.move({{ window = {win}, x = {w['at'][0]}, y = {w['at'][1]} }})")
    if w["pinned"]:
        dispatch(f"hl.dsp.window.pin({{ window = {win}, action = \"enable\" }})")
    if w["fullscreen"]:
        mode = "maximized" if w["fullscreen"] == 1 else "fullscreen"
        dispatch(f"hl.dsp.window.fullscreen({{ window = {win}, mode = {lua_str(mode)}, action = \"set\" }})")


def restore() -> int:
    if not STASH.exists():
        return 0
    try:
        state = json.loads(STASH.read_text())
    except (OSError, ValueError):
        state = {}
    STASH.unlink(missing_ok=True)

    # Each class's windows in the order they were opened, for the windows as they appear
    pending: dict[str, list[dict]] = {}
    for w in state.get("windows", []):
        pending.setdefault(w["class"], []).append(w)
    if not pending:
        return 0

    events = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    events.connect(f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket2.sock")
    events.settimeout(1)

    for lch in state.get("launches", []):
        if not lch.get("command"):
            continue
        try:
            subprocess.Popen(lch["command"], cwd=Path.home(), start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            print(f"Couldn't open {lch['command'][0]}: {e}", file=sys.stderr)

    buffer = b""
    deadline = time.monotonic() + RESTORE_WAIT
    while any(pending.values()) and time.monotonic() < deadline:
        try:
            data = events.recv(65536)
        except TimeoutError:
            continue
        if not data:
            break
        buffer += data
        *lines, buffer = buffer.split(b"\n")
        for line in lines:
            name, _, args = line.decode(errors="replace").partition(">>")
            if name != "openwindow":
                continue
            # openwindow>>address,workspace,class,title
            fields = args.split(",", 3)
            if len(fields) == 4 and pending.get(fields[2]):
                place("0x" + fields[0].removeprefix("0x"), pending[fields[2]].pop(0))

    if state.get("active"):
        dispatch(f"hl.dsp.focus({{ workspace = {lua_str(state['active'])} }})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("save", "restore"):
        print("usage: stash.py save|restore", file=sys.stderr)
        sys.exit(2)
    sys.exit(save() if sys.argv[1] == "save" else restore())
