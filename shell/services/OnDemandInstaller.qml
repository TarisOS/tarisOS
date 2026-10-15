// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris
import Taris.I18n
import qs.utils

// Apps installed on first use (utils/OnDemand.qml), installed in the background when their
// greyed-out stand-in is opened from the launcher or the dock: the password prompt is all that
// shows, while the stand-in's icon fills with colour as the install goes, then the app opens. As
// the App Store installs (assets/store.py): the freshest mirrors first (no password), then pacman,
// with the system's pending updates. One at a time (pacman's lock); others wait their turn.
Singleton {
    id: root

    // The stand-in installing now (its entry id), and how far along it is (0 to 1)
    readonly property string current: proc.running ? proc.appId : ""
    readonly property real progress: proc.running ? proc.progress : 0
    property list<string> queue: []

    // Stand-ins installed, waiting for the app's own entry to appear to open it
    property list<string> toOpen: []

    function isInstalling(id: string): bool {
        return current === id || queue.includes(id);
    }

    function install(entry: DesktopEntry): void {
        if (!OnDemand.isPlaceholder(entry) || isInstalling(entry.id))
            return;
        queue = [...queue, entry.id];
        next();
    }

    function next(): void {
        if (proc.running || queue.length === 0)
            return;
        const id = queue[0];
        queue = queue.slice(1);
        proc.appId = id;
        proc.appName = DesktopEntries.byId(id)?.name ?? id;
        proc.progress = 0;
        proc.phase = "";
        proc.downloads = 0;
        proc.downloaded = 0;
        proc.errors = [];
        proc.command = ["sh", "-c", 'pkexec /usr/lib/taris/mirrors && exec pkexec pacman -Syu --needed --noconfirm "$1"', "sh", OnDemand.packages[id]];
        proc.running = true;
    }

    // How far a pacman line puts the install: the databases, the downloads (counted against the
    // packages it lists), installing, then the hooks; it only ever goes forward
    function read(line: string): void {
        const text = line.trim();
        if (!text)
            return;
        if (text.toLowerCase().startsWith("error:") && proc.errors.length < 3)
            proc.errors = [...proc.errors, text.slice(6).trim()];

        let value = 0.02;
        const count = text.match(/^Packages \((\d+)\)/);
        if (count)
            proc.downloads = Number(count[1]);
        if (text.startsWith(":: Retrieving packages"))
            proc.phase = "download";
        else if (text.startsWith(":: Processing package changes"))
            proc.phase = "install";
        else if (text.startsWith(":: Running post-transaction hooks"))
            proc.phase = "hooks";

        const step = text.match(/^\((\d+)\/(\d+)\)/);
        if (proc.phase === "download") {
            if (/downloading/.test(text))
                proc.downloaded++;
            value = 0.05 + 0.5 * Math.min(1, proc.downloaded / Math.max(1, proc.downloads));
        } else if (proc.phase === "install" && step) {
            value = 0.6 + 0.35 * Number(step[1]) / Math.max(1, Number(step[2]));
        } else if (proc.phase === "hooks" && step) {
            value = 0.95 + 0.05 * Number(step[1]) / Math.max(1, Number(step[2]));
        }
        proc.progress = Math.max(proc.progress, value);
    }

    Process {
        id: proc

        property string appId
        property string appName
        property real progress
        property string phase
        property int downloads
        property int downloaded
        property list<string> errors

        stdout: SplitParser {
            onRead: line => root.read(line)
        }
        stderr: SplitParser {
            onRead: line => root.read(line)
        }
        onExited: code => {
            if (code === 0) {
                root.toOpen = [...root.toOpen, appId];
                openTimer.tries = 0;
                openTimer.restart();
            } else if (code !== 126 && code !== 127) {
                // 126 and 127: the password prompt was cancelled or refused
                Toaster.toast(Tr.tr("%1 couldn't be installed").arg(appName), errors.join("\n"), "error", Toast.Error);
            }
            Qt.callLater(root.next);
        }
    }

    // The app's own entry appears once the desktop entries are read again: it opens then (given up
    // after a minute)
    Timer {
        id: openTimer

        property int tries

        interval: 500
        repeat: true
        onTriggered: {
            const waiting = [];
            for (const id of root.toOpen) {
                const entry = OnDemand.installedFor(id);
                if (entry)
                    entry.execute();
                else
                    waiting.push(id);
            }
            root.toOpen = waiting;
            if (waiting.length === 0 || ++tries > 120) {
                root.toOpen = [];
                tries = 0;
                stop();
            }
        }
    }
}
