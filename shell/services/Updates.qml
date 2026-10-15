// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris.Config
import Taris.I18n

// Pending updates for the Updates settings (the page in General and its full list share them):
// packages (checkupdates: Arch Linux ARM, Asahi, the TarisOS repository; yay's AUR ones) and
// Flatpak apps
Singleton {
    id: root

    property list<string> pending: []
    property bool checking
    // While an update runs: the popouts whose terminal overlay runs it (none when it runs in a
    // terminal window), whether the shell watched its files before, and the shell's packages'
    // versions before
    property bool updating
    property var updatingIn: null
    property bool watchedFiles
    property string versionsBefore

    function check(): void {
        checking = true;
        proc.running = true;
    }

    // Everything, in the shell's terminal overlay on the focused screen (a terminal window when
    // Settings is a window, with no overlay to show it in): TarisOS's update (/usr/lib/taris/update:
    // packages, with a snapshot first, then Flatpak apps). Replacing the shell's files reloads the
    // shell, which would end the overlay's terminal and the update with it: the shell stops watching
    // its files until the update has ended. A reload can't load a new build of the shell's plugin or
    // of Quickshell, so when the update changed the shell's packages the shell restarts instead.
    function update(): void {
        if (updating)
            return;
        const popouts = ShellState.componentsForActive()?.panels?.popouts;
        // Not while another command (an install) runs in the overlay
        if (popouts && !popouts.showTerminal(Tr.tr("Updating the system"), "/usr/lib/taris/update"))
            return;
        updating = true;
        updatingIn = popouts;
        watchedFiles = Quickshell.watchFiles;
        Quickshell.watchFiles = false;
        versionsBefore = "";
        versionBefore.running = true;
        if (!popouts)
            terminalWindow.running = true;
    }

    function updateFinished(): void {
        updatingIn = null;
        versionAfter.running = true;
    }

    Connections {
        function onTerminalClosed(): void {
            root.updateFinished();
        }

        target: root.updatingIn
    }

    Process {
        id: terminalWindow

        command: [...GlobalConfig.general.apps.terminal, "-e", "bash", "-c", "/usr/lib/taris/update; echo; read -p 'Done. Press Enter to close' _"]
        onExited: root.updateFinished()
    }

    // The packages whose files the shell runs: its own (QML and plugin), Quickshell and the
    // terminal's plugin
    Process {
        id: versionBefore

        command: ["pacman", "-Q", "taris-shell", "quickshell-taris", "qmltermwidget-taris"]
        stdout: StdioCollector {
            onStreamFinished: root.versionsBefore = text.trim()
        }
    }

    Process {
        id: versionAfter

        command: versionBefore.command
        stdout: StdioCollector {
            onStreamFinished: {
                root.updating = false;
                if (text.trim() === root.versionsBefore) {
                    Quickshell.watchFiles = root.watchedFiles;
                    // What's left to update now (nothing, after an update that went through)
                    root.check();
                } else {
                    Quickshell.execDetached(["setsid", "taris", "shell", "-r", "-d"]);
                }
            }
        }
    }

    Process {
        id: proc

        command: ["sh", "-c", "checkupdates 2>/dev/null; command -v yay >/dev/null && yay -Qua 2>/dev/null; command -v flatpak >/dev/null && flatpak remote-ls --system --updates --columns=application,version 2>/dev/null | tr '\\t' ' '; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.pending = text.split("\n").filter(l => l.trim().length > 0);
                root.checking = false;
            }
        }
    }
}
