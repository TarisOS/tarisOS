// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris
import Taris.Config
import Taris.I18n

// Everything through Tor (/usr/lib/taris/tor, from taris-tor): on needs no password, off asks for
// one (its polkit rule), and it stays on after a reboot. Connected once a request comes back from
// the Tor network (check.torproject.org, itself through Tor), which also gives the exit's address;
// until then it's connecting, as Tor takes a while to reach its network. Switching it on or off is
// announced whatever does it (followed through its service's signals on the system bus); how it
// is found at login isn't. Its settings (Settings > Network > Tor: the bridges, a circuit for each
// site, a random hardware address) go through the same helper, with the password; a new identity
// needs none.
Singleton {
    id: root

    property bool enabled
    property bool failed
    property bool connected
    property string exitAddress
    // The first status has been read: changes from then on are announced
    property bool known
    // Switched on and not yet announced (connected, or couldn't start)
    property bool announce
    readonly property bool switching: setProc.running
    readonly property bool connecting: enabled && !failed && !connected
    // none, obfs4, snowflake, meek or custom (customBridges: its lines)
    property string bridges: "none"
    property list<string> customBridges: []
    property bool isolate
    property bool randomMac
    readonly property bool changing: optionProc.running || identityProc.running

    function refresh(): void {
        getProc.running = true;
    }

    function readSettings(): void {
        settingsProc.running = true;
    }

    // A setting through the helper (/usr/lib/taris/tor bridges|isolate|mac ...), with the password
    function setOption(args: list<string>): void {
        if (changing)
            return;
        optionProc.command = ["pkexec", "/usr/lib/taris/tor", ...args];
        optionProc.running = true;
    }

    // New circuits for everything from now on: connecting again until a request comes back through
    // them, with the new exit's address
    function newIdentity(): void {
        if (!connected || changing)
            return;
        identityProc.running = true;
    }

    function toggle(): void {
        if (switching)
            return;
        setProc.command = ["pkexec", "/usr/lib/taris/tor", enabled ? "off" : "on"];
        setProc.running = true;
    }

    function toast(title: string, message: string, icon: string, type: int): void {
        if (GlobalConfig.utilities.toasts.vpnChanged)
            Toaster.toast(title, message, icon, type);
    }

    onConnectingChanged: {
        if (connecting && !checkProc.running)
            checkProc.running = true;
    }

    onFailedChanged: {
        if (failed && announce) {
            announce = false;
            toast(Tr.tr("Tor couldn't start"), "", "error", Toast.Error);
        }
    }

    Process {
        id: getProc

        running: true
        command: ["/usr/lib/taris/tor", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim();
                const was = root.enabled;
                // Only what the switch says: no answer (no switch) is off
                root.enabled = state === "on" || state === "failed";
                root.enabledChanged(); // Switches flipped by a change that didn't happen flip back
                if (root.known && !was && root.enabled)
                    root.announce = true;
                root.failed = state === "failed";
                if (!root.enabled) {
                    if (root.known && was)
                        root.toast(Tr.tr("Tor off"), "", "domino_mask", Toast.Info);
                    root.announce = false;
                    root.connected = false;
                    root.exitAddress = "";
                }
                root.known = true;
            }
        }
    }

    // Read back afterwards: a failed switch leaves it as it was
    Process {
        id: setProc

        onExited: root.refresh()
    }

    Process {
        id: settingsProc

        running: true
        command: ["/usr/lib/taris/tor", "settings"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const value = key => lines.find(l => l.startsWith(`${key}=`))?.slice(key.length + 1) ?? "";
                root.bridges = value("bridges") || "none";
                root.isolate = value("isolate") === "1";
                root.randomMac = value("mac") === "1";
                root.customBridges = lines.slice(3).filter(l => l.trim());
                // Switches flipped by a change that didn't happen flip back
                root.bridgesChanged();
                root.isolateChanged();
                root.randomMacChanged();
            }
        }
    }

    // Tor starts again with new bridges or isolation: connecting until it's through again
    Process {
        id: optionProc

        onExited: code => {
            root.readSettings();
            if (code === 0 && root.enabled) {
                root.connected = false;
                root.exitAddress = "";
            }
            root.refresh();
        }
    }

    Process {
        id: identityProc

        command: ["pkexec", "/usr/lib/taris/tor", "newnym"]
        onExited: code => {
            if (code !== 0 || !root.enabled)
                return;
            root.toast(Tr.tr("New Tor identity"), "", "domino_mask", Toast.Info);
            root.connected = false;
            root.exitAddress = "";
        }
    }

    // Tor's service starting or stopping, whatever switched it
    Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.systemd1", "--object-path", "/org/freedesktop/systemd1/unit/taris_2dtor_2eservice"]
        stdout: SplitParser {
            onRead: refreshTimer.restart()
        }
    }

    Process {
        id: checkProc

        command: ["curl", "-s", "--max-time", "15", "https://check.torproject.org/api/ip"]
        stdout: StdioCollector {
            onStreamFinished: {
                let reply = null;
                try {
                    reply = JSON.parse(text);
                } catch (e) {}
                if (!root.connecting)
                    return;
                if (reply?.IsTor) {
                    root.exitAddress = reply.IP ?? "";
                    root.connected = true;
                    if (root.announce)
                        root.toast(Tr.tr("Tor connected"), root.exitAddress, "domino_mask", Toast.Info);
                    root.announce = false;
                } else {
                    retryTimer.start();
                }
            }
        }
    }

    // A switch sends several signals: read once they've settled
    Timer {
        id: refreshTimer

        interval: 500
        onTriggered: root.refresh()
    }

    Timer {
        id: retryTimer

        interval: 3000
        onTriggered: {
            if (root.connecting)
                checkProc.running = true;
        }
    }
}
