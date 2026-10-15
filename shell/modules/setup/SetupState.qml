// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Taris.I18n
import qs.modules.lock

// The setup screen's choices and its last step: /usr/lib/taris/setup-apply (as root, through
// pkexec: the greeter's user may run it while the system isn't set up) makes the account and sets
// the time zone and keyboard, then the account is logged in through greetd with its new password.
Scope {
    id: root

    enum Step {
        Welcome,
        Keyboard,
        Wifi,
        TimeZone,
        Account,
        Finishing
    }

    required property Pam pam

    property int step: SetupState.Welcome

    // Keyboard layouts (and their variants) from xkb: { layout, variant, name }
    property list<var> layouts: []
    property string layout: "us"
    property string variant: ""

    property list<string> zones: []
    property string timezone: "UTC"

    property string fullName
    property string userName
    // Typed by hand: no longer made from the name
    property bool userNameEdited
    property string password
    property string error

    readonly property bool working: applyProc.running || pam.busy

    function setLayout(layout: string, variant: string): void {
        root.layout = layout;
        root.variant = variant;
        kbProc.command = ["hyprctl", "eval", `hl.config({ input = { kb_layout = "${layout}", kb_variant = "${variant}" } })`];
        kbProc.running = true;
    }

    // A username from the name: its first word, lower case, letters and digits only
    function suggestUserName(name: string): string {
        const first = name.trim().split(/\s+/)[0] ?? "";
        return first.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9_-]/g, "").replace(/^[^a-z_]+/, "").slice(0, 32);
    }

    function userNameError(name: string): string {
        if (!name)
            return "";
        if (!/^[a-z_][a-z0-9_-]{0,31}$/.test(name))
            return Tr.tr("Lower-case letters, digits, - and _ only, starting with a letter");
        if (["root", "greeter", "nobody", "bin", "daemon", "mail", "ftp", "http", "nordvpn", "tor"].includes(name))
            return Tr.tr("That username can't be used");
        return "";
    }

    function finish(): void {
        if (working)
            return;
        error = "";
        step = SetupState.Finishing;
        applyProc.stdinEnabled = true;
        applyProc.running = true;
    }

    Process {
        id: kbProc
    }

    Process {
        id: applyProc

        command: ["pkexec", "/usr/lib/taris/setup-apply"]
        stdinEnabled: true
        stderr: StdioCollector {
            id: applyErr
        }

        // The choices on stdin (the password never on a command line)
        onStarted: {
            write(JSON.stringify({
                name: root.fullName.trim(),
                user: root.userName,
                password: root.password,
                timezone: root.timezone,
                layout: root.layout,
                variant: root.variant
            }) + "\n");
            stdinEnabled = false;
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0) {
                root.pam.user = root.userName;
                root.pam.buffer = root.password;
                root.password = "";
                root.pam.submit();
            } else {
                root.error = applyErr.text.trim().split("\n").pop() || Tr.tr("Setting up failed");
                root.step = SetupState.Account;
            }
        }
    }

    // A login that fails after the account was made: the greeter takes over (quitting ends this
    // Hyprland; greetd starts the greeter, as the system is set up now)
    Connections {
        function onStateChanged(): void {
            if (root.pam.state === Pam.Failed || root.pam.state === Pam.Error)
                Qt.quit();
        }

        target: root.pam
    }

    FileView {
        path: "/usr/share/X11/xkb/rules/evdev.lst"
        printErrors: false
        onLoaded: {
            const names = {};
            const out = [];
            let section = "";
            for (const line of text().split("\n")) {
                if (line.startsWith("! ")) {
                    section = line.slice(2).trim();
                    continue;
                }
                const m = line.match(/^\s+(\S+)\s+(.*)$/);
                if (!m)
                    continue;
                if (section === "layout") {
                    names[m[1]] = m[2];
                    out.push({
                        layout: m[1],
                        variant: "",
                        name: m[2]
                    });
                } else if (section === "variant") {
                    const v = m[2].match(/^(\S+):\s*(.*)$/);
                    if (v)
                        out.push({
                            layout: v[1],
                            variant: m[1],
                            name: v[2]
                        });
                }
            }
            // English (US), (UK) and (Australia) first, then the rest by name: the list opens at its
            // top, on the default (us)
            const first = ["us:", "gb:", "au:"];
            const rank = l => {
                const i = first.indexOf(`${l.layout}:${l.variant}`);
                return i < 0 ? first.length : i;
            };
            out.sort((a, b) => (rank(a) - rank(b)) || a.name.localeCompare(b.name));
            root.layouts = out;
        }
    }

    Process {
        running: true
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: root.zones = text.split("\n").filter(z => z)
        }
    }

    Process {
        running: true
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector {
            onStreamFinished: root.timezone = text.trim() || "UTC"
        }
    }
}
