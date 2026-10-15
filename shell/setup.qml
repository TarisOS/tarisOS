// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded

// The first-boot setup screen (taris-qs -p setup.qml, run by greetd instead of the greeter until the
// first account exists): keyboard, Wi-Fi, time zone and the account, then straight into the
// desktop, logged in with the password just chosen.

import "modules"
import "modules/lock"
import "modules/setup"
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    settings.watchFiles: false

    GSFLoader {}

    // What's been chosen, shared by every screen's surface (only the first screen shows the steps)
    SetupState {
        id: setupState

        pam: pam
    }

    WlSessionLock {
        id: lock

        signal unlock

        locked: true

        WlSessionLockSurface {
            id: surface

            color: "black"

            SetupScreen {
                anchors.fill: parent
                screen: surface.screen
                setup: setupState
                visible: surface.screen === Quickshell.screens[0]
            }
        }
    }

    // The login at the end, the greeter's way (greetd)
    Pam {
        id: pam

        lock: lock
        greeter: true
        user: ""

        onLoggedIn: lock.locked = false
    }
}
