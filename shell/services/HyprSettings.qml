// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris.Config
import qs.utils

// Every Hyprland option, from `hyprctl descriptions -j`. Changes apply live through
// `hyprctl eval` and, when Hyprland accepts them, are kept in hypr-settings.json and
// written to hypr-settings.lua, which hyprland.lua loads at the end so they persist. TarisOS's own
// settings in its Hyprland config (the taris_* globals, such as taris_fn_switch) go the same way.
Singleton {
    id: root

    readonly property string luaPath: `${Paths.config}/hypr-settings.lua`
    property list<var> options: []
    readonly property list<string> categories: [...new Set(options.map(o => o.name.split(":")[0]))]
    property string lastError
    readonly property var overrides: adapter.overrides
    readonly property var monitors: adapter.monitors
    readonly property var taris: adapter.taris
    // Monitors being tried out (tryMonitors), what they go back to and the seconds left before they
    // do. Kept here rather than on the Displays page, so they still go back when Settings closes.
    property var trialMonitors: null
    property var trialPrevious: null
    property int trialSeconds
    // hypr-settings.json has been read (migrateMonitors waits for it)
    property bool loaded

    // m: { mode, position, scale, transform, mirror, disabled }. Every field is given: hl.monitor
    // starts from the output's existing rule, so one left out keeps its old value (a rotation,
    // mirroring or being disabled would stay)
    // A mode read while the display wasn't lit yet ("0x0@…") is no mode Hyprland can set: its
    // preferred one instead.
    function monitorLua(name: string, m: var): string {
        if (m.disabled)
            return `hl.monitor({ output = ${JSON.stringify(name)}, disabled = true })`;
        const mode = !m.mode || String(m.mode).startsWith("0x0") ? "preferred" : m.mode;
        const fields = [`output = ${JSON.stringify(name)}`, `mode = ${JSON.stringify(mode)}`, `position = ${JSON.stringify(m.position ?? "auto")}`, `scale = ${m.scale ?? "auto"}`, `transform = ${m.transform ?? 0}`, `mirror = ${JSON.stringify(m.mirror ?? "")}`, "disabled = false"];
        return `hl.monitor({ ${fields.join(", ")} })`;
    }

    // A display's live rule, by its monitor's key as it's kept (keep), mirroring by key too: a
    // rule by the output's name would outlive the monitor being on that output, and win over the
    // kept rules as it comes after them
    function liveLua(name: string, m: var): string {
        return monitorLua(Screens.keyOf(name), Object.assign({}, m, {
            mirror: m.mirror ? Screens.keyOf(m.mirror) : ""
        }));
    }

    // Keeps a display's values (all: the kept monitors, changed in place) under its monitor's key
    // (Screens.keyOf), mirroring by key too, marked with the kind of key ("by"). Its entry from
    // before keys (under its output's name, unmarked) goes; so does its description's entry when
    // it's kept by name as one of identical monitors, as that rule, written after, would put them
    // all in the same place.
    function keep(all: var, name: string, values: var): void {
        const key = Screens.keyOf(name);
        const byDesc = key.startsWith("desc:");
        all[key] = Object.assign({}, values, {
            mirror: values.mirror ? Screens.keyOf(values.mirror) : "",
            by: byDesc ? "desc" : "name"
        });
        if (byDesc && key !== name && all[name] && !all[name].by)
            delete all[name];
        const desc = Screens.descriptionOf(name);
        if (!byDesc && desc)
            delete all[`desc:${desc}`];
    }

    // values: { mode, position, scale, transform, mirror, disabled }; applied live and kept in
    // hypr-settings.lua
    function setMonitor(name: string, values: var): void {
        const all = Object.assign({}, adapter.monitors);
        const merged = Object.assign({}, all[Screens.keyOf(name)] ?? {}, values);
        keep(all, name, merged);
        adapter.monitors = all;
        Quickshell.execDetached(["hyprctl", "eval", liveLua(name, merged)]);
        writeLua();
    }

    // Several monitors ({ name: values }) applied live only, so they can be tried out first
    function previewMonitors(monitors: var): void {
        Quickshell.execDetached(["hyprctl", "eval", Object.entries(monitors).map(([name, m]) => liveLua(name, m)).join("; ")]);
    }

    // Several monitors ({ name: values }) applied live and kept
    function saveMonitors(monitors: var): void {
        const all = Object.assign({}, adapter.monitors);
        for (const [name, values] of Object.entries(monitors))
            keep(all, name, values);
        adapter.monitors = all;
        previewMonitors(monitors);
        writeLua();
    }

    // Entries kept before keys (under an output's name, unmarked) move to the key of the monitor
    // now on that output, and the main display too, as monitors are seen; one of identical
    // monitors keeps its output's name
    function migrateMonitors(): void {
        if (!loaded)
            return;
        const all = Object.assign({}, adapter.monitors);
        let changed = false;
        for (const s of Quickshell.screens) {
            const old = all[s.name];
            if (!old || old.by || !Screens.known(s.name))
                continue;
            const key = Screens.keyOf(s.name);
            if (key === s.name) {
                all[s.name] = Object.assign({}, old, {
                    by: "name"
                });
            } else {
                if (!all[key])
                    all[key] = Object.assign({}, old, {
                        mirror: old.mirror ? Screens.keyOf(old.mirror) : "",
                        by: "desc"
                    });
                delete all[s.name];
            }
            changed = true;
        }
        const main = GlobalConfig.general.mainDisplay;
        if (main && !main.startsWith("desc:") && Quickshell.screens.some(s => s.name === main) && Screens.known(main) && Screens.keyOf(main) !== main) {
            GlobalConfig.general.mainDisplay = Screens.keyOf(main);
            changed = true;
        }
        if (changed) {
            adapter.monitors = all;
            writeLua();
        }
    }

    // Several monitors ({ name: values }) applied live, going back to previous ({ name: values })
    // after 15 seconds unless kept with keepTrial()
    function tryMonitors(monitors: var, previous: var): void {
        trialMonitors = monitors;
        trialPrevious = previous;
        trialSeconds = 15;
        previewMonitors(monitors);
        trialTimer.restart();
    }

    function keepTrial(): void {
        if (!trialMonitors)
            return;
        trialTimer.stop();
        trialSeconds = 0;
        saveMonitors(trialMonitors);
        trialMonitors = null;
        trialPrevious = null;
    }

    function revertTrial(): void {
        if (!trialMonitors)
            return;
        trialTimer.stop();
        trialSeconds = 0;
        previewMonitors(trialPrevious);
        trialMonitors = null;
        trialPrevious = null;
    }

    // Workspace 1 on the main display (Settings > Displays), by its key (Screens.keyOf)
    function mainDisplayLua(key: string): string {
        return `hl.workspace_rule({ workspace = "1", monitor = ${JSON.stringify(key)}, default = true })`;
    }

    // The main display: workspace 1 moves there now and opens there from now on; kept by its
    // monitor's key, so it stays the main display on any port or adapter
    function setMainDisplay(name: string): void {
        const key = Screens.keyOf(name);
        GlobalConfig.general.mainDisplay = key;
        Quickshell.execDetached(["hyprctl", "eval", `${mainDisplayLua(key)}; hl.dispatch(hl.dsp.workspace.move({ workspace = "1", monitor = ${JSON.stringify(name)} }))`]);
        writeLua();
    }

    // _G.taris_<name> = value, for a config that has it
    function tarisLua(name: string, value: var): string {
        return `if _G.taris_${name} ~= nil then _G.taris_${name} = ${luaValue(value)} end`;
    }

    // One of TarisOS's own settings (taris_<name>), applied live and kept
    function setTaris(name: string, value: var): void {
        adapter.taris = Object.assign({}, adapter.taris, {
            [name]: value
        });
        Quickshell.execDetached(["hyprctl", "eval", tarisLua(name, value)]);
        writeLua();
    }

    function refresh(): void {
        descProc.running = true;
    }

    function current(name: string): var {
        return name in adapter.overrides ? adapter.overrides[name] : options.find(o => o.name === name)?.current;
    }

    // Lua literal for a value; numeric strings become numbers, "a b c d" becomes a css gap table
    function luaValue(value: var): string {
        if (typeof value === "boolean" || typeof value === "number")
            return String(value);
        if (Array.isArray(value))
            return `{ ${value.map(v => luaValue(v)).join(", ")} }`;
        const s = String(value).trim();
        if (/^-?\d+(\.\d+)?$/.test(s))
            return s;
        const gap = s.match(/^(\d+) (\d+) (\d+) (\d+)$/);
        if (gap)
            return `{ top = ${gap[1]}, right = ${gap[2]}, bottom = ${gap[3]}, left = ${gap[4]} }`;
        return JSON.stringify(s);
    }

    // "a:b.c" with value v -> hl.config({ a = { b = { c = v } } })
    function luaFor(name: string, value: var): string {
        // Lua spells dashed option names (tap-to-click) with underscores
        const keys = name.split(/[:.]/).map(k => k.replace(/-/g, "_"));
        let body = luaValue(value);
        for (let i = keys.length - 1; i >= 0; i--)
            body = `{ ${/^[A-Za-z_][A-Za-z0-9_]*$/.test(keys[i]) ? keys[i] : `["${keys[i]}"]`} = ${body} }`;
        return `hl.config(${body})`;
    }

    function set(name: string, value: var): void {
        setMany({
            [name]: value
        });
    }

    // Several options ({ name: value }) in one go, kept only when Hyprland takes them all (the
    // keyboard layout and its variants have to change together)
    function setMany(values: var): void {
        const proc = applyComp.createObject(root, {
            values
        });
        proc.running = true;
    }

    function reset(name: string): void {
        const o = options.find(opt => opt.name === name);
        const all = Object.assign({}, adapter.overrides);
        delete all[name];
        adapter.overrides = all;
        if (o)
            Quickshell.execDetached(["hyprctl", "eval", luaFor(name, o.default)]);
        writeLua();
    }

    function writeLua(): void {
        const lines = ["-- Written by Settings (Displays and Keyboard pages). Edit there, not here."];
        for (const [name, value] of Object.entries(adapter.overrides))
            lines.push(`pcall(function() ${luaFor(name, value)} end)`);
        // By output name first, by monitor after: Hyprland takes the last rule that matches, so a
        // monitor's own rule wins over one for the output it's on
        const kept = Object.entries(adapter.monitors);
        for (const [key, m] of kept.filter(([k]) => !k.startsWith("desc:")).concat(kept.filter(([k]) => k.startsWith("desc:"))))
            lines.push(`pcall(function() ${monitorLua(key, m)} end)`);
        if (GlobalConfig.general.mainDisplay)
            lines.push(`pcall(function() ${mainDisplayLua(GlobalConfig.general.mainDisplay)} end)`);
        for (const [name, value] of Object.entries(adapter.taris))
            lines.push(tarisLua(name, value));
        luaFile.setText(lines.join("\n") + "\n");
    }

    Component.onCompleted: refresh()

    Component {
        id: applyComp

        Process {
            id: proc

            required property var values

            command: ["hyprctl", "eval", Object.entries(values).map(([name, value]) => root.luaFor(name, value)).join("; ")]
            stdout: StdioCollector {
                onStreamFinished: {
                    if (text.trim() === "ok") {
                        adapter.overrides = Object.assign({}, adapter.overrides, proc.values);
                        root.lastError = "";
                        root.writeLua();
                    } else {
                        root.lastError = text.trim().replace(/^error: return .*?;:1: /, "");
                    }
                    proc.destroy();
                }
            }
        }
    }

    Timer {
        id: trialTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.trialSeconds--;
            if (root.trialSeconds <= 0)
                root.revertTrial();
        }
    }

    Process {
        id: descProc

        command: ["hyprctl", "descriptions", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.options = JSON.parse(text);
                } catch (e) {
                    root.options = [];
                }
            }
        }
    }

    FileView {
        id: luaFile

        path: root.luaPath
    }

    // The monitors seen change (one plugged in, or Hyprland describing them)
    Connections {
        function onKeysChanged(): void {
            root.migrateMonitors();
        }

        target: Screens
    }

    FileView {
        path: `${Paths.config}/hypr-settings.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            root.loaded = true;
            root.migrateMonitors();
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
            root.loaded = true;
        }

        JsonAdapter {
            id: adapter

            property var overrides: ({})
            property var monitors: ({})
            property var taris: ({})
        }
    }
}
