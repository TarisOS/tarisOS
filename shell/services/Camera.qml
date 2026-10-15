// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The camera's switch (/usr/lib/taris/camera, from taris-hardware): off takes the camera from its
// driver and keeps the driver from loading until it's switched on again. Off needs no password,
// on asks for one (its polkit rule).
Singleton {
    id: root

    property bool enabled: true
    readonly property bool busy: setProc.running

    function refresh(): void {
        getProc.running = true;
    }

    function toggle(): void {
        if (busy)
            return;
        setProc.command = ["pkexec", "/usr/lib/taris/camera", enabled ? "off" : "on"];
        setProc.running = true;
    }

    Process {
        id: getProc

        running: true
        command: ["/usr/lib/taris/camera", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.enabled = text.trim() !== "off"
        }
    }

    // Read back afterwards: a cancelled password prompt leaves it as it was
    Process {
        id: setProc

        onExited: root.refresh()
    }
}
