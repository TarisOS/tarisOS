// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import Quickshell

// Where the greeter finds what it can't read from anyone's home folder: the last session's colours
// and wallpaper, and the accounts' pictures (written by taris-greeter-sync as the user), and the
// account that last logged in (written by the greeter itself)
Singleton {
    readonly property string root: "/var/lib/taris/greeter"
    readonly property string faces: `${root}/faces`
    readonly property string lastUser: "/var/lib/taris/greeter-user/last-user"
}
