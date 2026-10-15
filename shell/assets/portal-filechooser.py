#!/usr/bin/env python3
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

"""File pickers for every app that asks the desktop for one, shown with Taris's own.

An xdg-desktop-portal FileChooser backend (org.freedesktop.impl.portal.desktop.taris, started
by D-Bus when the portal first needs it; the installer points the portal's FileChooser at it).
Each OpenFile/SaveFile/SaveFiles request goes to the shell (`taris-qs -c taris ipc call
filepicker open <id> <request>`, modules/FilePicker.qml), which shows its picker in the overlay
and answers on this service's org.taris.FilePicker.Done. When the shell can't take it (not
running), the request goes to the GTK portal's picker instead, so picking a file always works.
It exits after a minute with nothing to do (it's ~20 MB of Python), and D-Bus starts it again for
the next request.
"""

import json
import mimetypes
import os
import re
import shutil
import subprocess
import time
import uuid
import warnings

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

# register_object (with Python callbacks) is the one call PyGObject has for this on every GLib this
# runs on; it warns that it's deprecated on newer ones
warnings.filterwarnings("ignore", category=DeprecationWarning)

BUS_NAME = "org.freedesktop.impl.portal.desktop.taris"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
CHOOSER = "org.freedesktop.impl.portal.FileChooser"
CALLBACK_PATH = "/org/taris/FilePicker"
FALLBACK = "org.freedesktop.impl.portal.desktop.gtk"

ARGS = """
  <arg type="o" name="handle" direction="in"/>
  <arg type="s" name="app_id" direction="in"/>
  <arg type="s" name="parent_window" direction="in"/>
  <arg type="s" name="title" direction="in"/>
  <arg type="a{sv}" name="options" direction="in"/>
  <arg type="u" name="response" direction="out"/>
  <arg type="a{sv}" name="results" direction="out"/>"""
CHOOSER_XML = f"""<node><interface name="{CHOOSER}">
  <method name="OpenFile">{ARGS}</method>
  <method name="SaveFile">{ARGS}</method>
  <method name="SaveFiles">{ARGS}</method>
</interface></node>"""
CALLBACK_XML = """<node><interface name="org.taris.FilePicker">
  <method name="Done">
    <arg type="s" name="id" direction="in"/>
    <arg type="s" name="response" direction="in"/>
    <arg type="s" name="path" direction="in"/>
  </method>
</interface></node>"""
REQUEST_XML = """<node><interface name="org.freedesktop.impl.portal.Request">
  <method name="Close"/>
</interface></node>"""

HOME = os.path.expanduser("~")
QS = shutil.which("taris-qs") or "taris-qs"

connection: Gio.DBusConnection | None = None
# Requests the shell is answering: id -> { invocation, method, handle, files, registration }
pending: dict[str, dict] = {}
# Requests the GTK portal is answering
in_flight = 0
IDLE_EXIT_SECONDS = 60
last_activity = time.monotonic()


def touch() -> None:
    global last_activity
    last_activity = time.monotonic()


def path_bytes(value) -> str | None:
    """A portal path (ay, NUL-terminated bytes) as a str."""
    if not value:
        return None
    raw = bytes(value).rstrip(b"\0")
    return os.fsdecode(raw) if raw else None


def cwd_parts(folder: str | None) -> list[str]:
    """A folder as the dialog's cwd: ["Home", ...] under the home folder, else ["/", ...]."""
    if not folder or not os.path.isdir(folder):
        return ["Home"]
    folder = os.path.abspath(folder)
    if folder == HOME or folder.startswith(HOME + os.sep):
        rel = os.path.relpath(folder, HOME)
        return ["Home"] + ([] if rel == "." else rel.split(os.sep))
    return ["/"] + [p for p in folder.split(os.sep) if p]


def extensions(filter_) -> tuple[str, list[str]]:
    """A portal filter (name, [(0 glob | 1 mime, pattern)]) as a label and file extensions."""
    name, rules = filter_
    exts: list[str] = []
    for kind, pattern in rules:
        if kind == 0:
            pattern = pattern.strip()
            if pattern in ("*", "*.*"):
                return name, ["*"]
            if pattern.startswith("*."):
                # Case-insensitive globs like *.[pP][nN][gG]: the first letter of each group
                exts.append(re.sub(r"\[(.)[^\]]*\]", r"\1", pattern[2:]).lower())
        else:
            mime = pattern.strip().lower()
            if mime in ("*", "*/*", "application/octet-stream"):
                return name, ["*"]
            if mime.endswith("/*"):
                prefix = mime[:-1]
                exts += [e[1:] for e, m in mimetypes.types_map.items() if m.startswith(prefix)]
            else:
                exts += [e[1:] for e in mimetypes.guess_all_extensions(mime)]
    exts = sorted(set(e for e in exts if e))
    return name, exts or ["*"]


def request_for(method: str, title: str, options: dict) -> tuple[dict, list[str]]:
    """What the shell is asked to show, and (SaveFiles) the names to save in the folder picked."""
    files: list[str] = []
    mode, name = "open", ""
    folder = path_bytes(options.get("current_folder"))
    if method == "OpenFile":
        mode = "directory" if options.get("directory") else "open"
    elif method == "SaveFile":
        mode = "save"
        name = options.get("current_name") or ""
        current = path_bytes(options.get("current_file"))
        if current:
            folder = folder or os.path.dirname(current)
            name = name or os.path.basename(current)
    else:  # SaveFiles: a folder to save the given files in
        mode = "directory"
        files = [os.path.basename(path_bytes(f) or "") for f in options.get("files") or []]

    filter_label, filters = "", ["*"]
    chosen = options.get("current_filter") or (options.get("filters") or [None])[0]
    if chosen and mode != "directory":
        filter_label, filters = extensions(chosen)

    request = {
        "title": title,
        "mode": mode,
        "name": name,
        "acceptLabel": (options.get("accept_label") or "").replace("_", ""),
        "filterLabel": filter_label,
        "filters": filters,
        "cwd": cwd_parts(folder),
    }
    return request, files


def finish(request_id: str, response: int, path: str) -> None:
    touch()
    entry = pending.pop(request_id, None)
    if not entry:
        return
    if entry["registration"]:
        connection.unregister_object(entry["registration"])
    uris: list[str] = []
    if response == 0 and path:
        if entry["method"] == "SaveFiles":
            uris = [GLib.filename_to_uri(os.path.join(path, f), None) for f in entry["files"] if f]
        else:
            uris = [GLib.filename_to_uri(path, None)]
    results = {"uris": GLib.Variant("as", uris)} if response == 0 else {}
    entry["invocation"].return_value(GLib.Variant("(ua{sv})", (response, results)))


def fall_back(method: str, parameters: GLib.Variant, invocation: Gio.DBusMethodInvocation) -> None:
    """The GTK portal's picker answers instead."""
    global in_flight
    in_flight += 1

    def done(conn, result):
        global in_flight
        in_flight -= 1
        touch()
        try:
            invocation.return_value(conn.call_finish(result))
        except GLib.Error:
            invocation.return_value(GLib.Variant("(ua{sv})", (2, {})))

    connection.call(FALLBACK, PORTAL_PATH, CHOOSER, method, parameters, GLib.VariantType("(ua{sv})"),
                    Gio.DBusCallFlags.NONE, 2147483647, None, done)


def on_chooser_call(conn, sender, path, interface, method, parameters, invocation):
    touch()
    handle, _app_id, _parent, title, options = parameters.unpack()
    request, files = request_for(method, title, options)
    request_id = uuid.uuid4().hex

    try:
        shown = subprocess.run([QS, "-c", "taris", "ipc", "call", "filepicker", "open", request_id,
                                json.dumps(request)], capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        shown = False
    if not shown:
        fall_back(method, parameters, invocation)
        return

    def on_request_call(conn, sender, path, interface, method_name, params, inv):
        # The app gave up on it: close the picker and answer that it was cancelled
        inv.return_value(None)
        subprocess.run([QS, "-c", "taris", "ipc", "call", "filepicker", "cancel", request_id],
                       capture_output=True, timeout=5, check=False)
        finish(request_id, 1, "")

    try:
        registration = conn.register_object(handle, Gio.DBusNodeInfo.new_for_xml(REQUEST_XML).interfaces[0],
                                            on_request_call, None, None)
    except GLib.Error:
        registration = 0
    pending[request_id] = {"invocation": invocation, "method": method, "handle": handle, "files": files,
                           "registration": registration}


def on_callback_call(conn, sender, path, interface, method, parameters, invocation):
    request_id, response, chosen = parameters.unpack()
    invocation.return_value(None)
    try:
        code = int(response)
    except ValueError:
        code = 2
    finish(request_id, code, chosen)


def on_bus_acquired(conn, name):
    global connection
    connection = conn
    conn.register_object(PORTAL_PATH, Gio.DBusNodeInfo.new_for_xml(CHOOSER_XML).interfaces[0], on_chooser_call,
                         None, None)
    conn.register_object(CALLBACK_PATH, Gio.DBusNodeInfo.new_for_xml(CALLBACK_XML).interfaces[0], on_callback_call,
                         None, None)


def main() -> None:
    loop = GLib.MainLoop()
    owner = Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE, on_bus_acquired, None,
                             lambda *_: loop.quit())

    # Nothing open and nothing asked for a minute: let the name go first (a request after that
    # starts a new one), then stop
    def exit_when_idle() -> bool:
        if pending or in_flight or time.monotonic() - last_activity < IDLE_EXIT_SECONDS:
            return True
        Gio.bus_unown_name(owner)
        GLib.timeout_add(200, loop.quit)
        return False

    GLib.timeout_add_seconds(15, exit_when_idle)
    loop.run()


if __name__ == "__main__":
    main()
