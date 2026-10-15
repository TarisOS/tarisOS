// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded

pragma ComponentBehavior: Bound

// The greeter (taris-qs -p greeter.qml, run by greetd through /usr/lib/taris/greeter-session): the
// lock screen, logging the chosen account in. Exactly one password prompt before anything of the
// user's starts; it quits once their session is starting.

import "modules"
import "modules/lock"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.utils

ShellRoot {
    id: root

    settings.watchFiles: false

    // The accounts people log in to (/etc/passwd: regular users with a login shell)
    property list<var> users: []
    property string lastUser

    // The account that last logged in, else the first; not once someone has started typing
    function pickUser(): void {
        if (users.length === 0 || pam.buffer || pam.busy)
            return;
        const last = users.find(u => u.name === lastUser);
        if (last)
            pam.user = last.name;
        else if (!users.some(u => u.name === pam.user))
            pam.user = users[0].name;
    }

    GSFLoader {}

    WlSessionLock {
        id: lock

        signal unlock

        locked: true

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
        greeter: true
        user: ""
        users: root.users

        // The session lock goes first, at once: a lock client that quits without unlocking leaves
        // Hyprland showing its error screen until it quits too
        onLoggedIn: {
            lastUserFile.setText(user + "\n");
            lock.locked = false;
        }
    }

    FileView {
        path: "/etc/passwd"
        onLoaded: {
            const users = [];
            for (const line of text().split("\n")) {
                const f = line.split(":");
                if (f.length < 7)
                    continue;
                const uid = parseInt(f[2]);
                if (uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6]))
                    continue;
                users.push({
                    name: f[0],
                    realName: f[4].split(",")[0] || f[0]
                });
            }
            root.users = users;
            root.pickUser();
        }
    }

    FileView {
        id: lastUserFile

        path: GreeterPaths.lastUser
        printErrors: false
        onLoaded: {
            root.lastUser = text().trim();
            root.pickUser();
        }
    }
}
