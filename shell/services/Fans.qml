// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Apple Silicon fan control through macsmc_hwmon (assets/fans.py). Each fan runs on
// auto (the SMC decides), full, constant (a fixed speed) or range (minimum speed at
// `from` °C, maximum at `to` °C, linear between, following the hottest sensor).
Singleton {
    id: root

    readonly property string script: `${Quickshell.shellDir}/assets/fans.py`
    property bool present
    property bool control
    property list<var> fans: [] // Only replaced when the fans themselves change, so the panel isn't rebuilt every read
    property var rpms: ({}) // Live speeds by fan number
    property string fansShape
    property list<var> temps: []
    property var applied: ({})
    readonly property var hottest: temps.reduce((a, t) => !a || t.celsius > a.celsius ? t : a, null)
    // Popouts showing the fans (FansPopout): readings every 2 s while one is, or while a fan
    // follows the temperature (range); every 10 s otherwise, which is enough for the bar's icon
    property int watchers
    readonly property bool live: watchers > 0 || fans.some(f => config(f.n).mode === "range")
    readonly property int interval: live ? 2 : 10
    onIntervalChanged: {
        // A new interval needs a new fans.py: stop this one (onExited starts the next). Only a
        // running one: running = false before it has started (during the shell's start) cancels
        // the start, and nothing would start it again
        if (!readProc.running)
            return;
        restarting = true;
        readProc.running = false;
    }
    property bool restarting

    function config(n: int): var {
        const c = adapter.fans[String(n)] ?? {};
        // Out-of-range values (e.g. saved by an older build) fall back to defaults
        return {
            mode: c.mode ?? "auto",
            rpm: c.rpm ?? 0,
            from: c.from >= 30 && c.from <= 95 ? c.from : 50,
            to: c.to >= 35 && c.to <= 100 ? c.to : 85
        };
    }

    function setConfig(n: int, values: var): void {
        const all = Object.assign({}, adapter.fans);
        all[String(n)] = Object.assign(config(n), values);
        adapter.fans = all;
        apply();
    }

    function clampRpm(fan: var, rpm: real): int {
        return Math.round(Math.max(fan.min, Math.min(fan.max, rpm)));
    }

    function wanted(fan: var): var {
        const c = config(fan.n);
        if (c.mode === "full")
            return fan.max;
        if (c.mode === "constant")
            return clampRpm(fan, c.rpm > 0 ? c.rpm : fan.min);
        if (c.mode === "range" && hottest) {
            const f = Math.max(0, Math.min(1, (hottest.celsius - c.from) / Math.max(1, c.to - c.from)));
            return clampRpm(fan, fan.min + f * (fan.max - fan.min));
        }
        return "auto";
    }

    function apply(): void {
        if (!control)
            return;
        for (const fan of fans) {
            if (!fan.writable)
                continue;
            const want = wanted(fan);
            const last = applied[String(fan.n)];
            // Range speeds settle within 50 RPM so the fan doesn't hunt
            if (last === want || (want !== "auto" && typeof last === "number" && Math.abs(last - want) < 50))
                continue;
            applied[String(fan.n)] = want;
            Quickshell.execDetached(["python3", "-I", script, "set", String(fan.n), String(want)]);
        }
    }

    // One fans.py for the shell's lifetime, printing a reading every 2 s: starting Python for
    // every reading cost more CPU than everything else the shell does while idle
    Process {
        id: readProc

        running: true
        command: ["python3", "-I", root.script, "watch", String(root.interval)]
        stdout: SplitParser {
            onRead: text => {
                try {
                    const data = JSON.parse(text);
                    root.present = data.present;
                    root.control = data.control;
                    const f = data.fans ?? [];
                    const shape = JSON.stringify(f.map(x => [x.n, x.label, x.min, x.max, x.writable]));
                    if (shape !== root.fansShape) {
                        root.fansShape = shape;
                        root.fans = f;
                    }
                    const rpms = {};
                    for (const x of f)
                        rpms[x.n] = x.rpm ?? 0;
                    root.rpms = rpms;
                    root.temps = data.temps ?? [];
                    root.apply();
                } catch (e) {
                    console.warn("Fans: failed to read fans.py output:", e);
                }
            }
        }
        // It only stops if something kills it: start it again
        onExited: {
            if (root.restarting) {
                root.restarting = false;
                running = true;
            } else {
                restartTimer.restart();
            }
        }
    }

    Timer {
        id: restartTimer

        interval: 5000
        onTriggered: readProc.running = true
    }

    FileView {
        path: `${Paths.state}/fans.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter

            property var fans: ({})
        }
    }
}
