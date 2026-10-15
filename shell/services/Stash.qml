// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris.Config
import Taris.Services

// Stash: instead of sleep, which keeps drawing power on Apple Silicon, the open apps are recorded
// and closed, keeping their work, and the Mac shuts down; at the next login they open again where
// they were (assets/stash.py). An app that doesn't close (at a prompt) is made to quit: Stash
// always ends in the shut down.
Singleton {
    id: root

    readonly property bool busy: save.running
    // The notice the Stash button shows first is up (modules/session/StashNotice.qml)
    property bool confirming

    function stash(): void {
        if (save.running)
            return;
        // Nothing sleeps in the middle (the lid, whatever its setting), kept until the shut down,
        // and the screen goes off at once: the rest happens in the dark
        SessionManager.blockSleep = true;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.dpms({ action = "disable" })` : "dpms off"); // qmllint disable missing-property
        save.running = true;
    }

    // The Stash button: its notice first, unless the user turned it off
    function request(): void {
        if (save.running)
            return;
        if (GlobalConfig.session.stashNotice)
            confirming = true;
        else
            stash();
    }

    // At login (ServiceLoader): nothing unless the last shut down was a Stash
    function restore(): void {
        if (!restoreProc.running)
            restoreProc.running = true;
    }

    Process {
        id: save

        command: ["python3", "-I", `${Quickshell.shellDir}/assets/stash.py`, "save"]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("Stash:", text.trim());
            }
        }
        onExited: SessionManager.poweroff()
    }

    Process {
        id: restoreProc

        command: ["python3", "-I", `${Quickshell.shellDir}/assets/stash.py`, "restore"]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("Stash:", text.trim());
            }
        }
    }
}
