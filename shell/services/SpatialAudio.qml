// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Spatial audio's switch: WirePlumber's taris.spatial-audio setting (taris-hardware's
// spatial-audio.lua), saved across restarts. Unavailable without that package's setting.
Singleton {
    id: root

    property bool available: false
    property bool enabled: true
    readonly property bool busy: setProc.running

    function refresh(): void {
        getProc.running = true;
    }

    function toggle(): void {
        if (busy || !available)
            return;
        setProc.command = ["wpctl", "settings", "--save", "taris.spatial-audio", enabled ? "false" : "true"];
        setProc.running = true;
    }

    // "Value: true (Saved: true)", or "Setting '...' not found" without taris-hardware's setting
    Process {
        id: getProc

        running: true
        command: ["wpctl", "settings", "taris.spatial-audio"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.match(/^Value: (true|false)/);
                root.available = !!value;
                if (value)
                    root.enabled = value[1] === "true";
            }
        }
    }

    Process {
        id: setProc

        onExited: root.refresh()
    }
}
