// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import Quickshell
import Taris.Config

Singleton {
    id: root

    // The display that always has the shell (Settings > Displays): the chosen one while it's
    // connected, else the first, so the shell is never left on no display at all
    readonly property string mainName: Quickshell.screens.some(s => s.name === GlobalConfig.general.mainDisplay) ? GlobalConfig.general.mainDisplay : (Quickshell.screens[0]?.name ?? "")
    // The displays with the shell (bar, dock and panels)
    readonly property list<ShellScreen> screens: Quickshell.screens.filter(s => s.name === mainName || GlobalConfig.forScreen(s.name).enabled)
    // Every display, numbered left to right then top to bottom, as Settings numbers them
    readonly property list<ShellScreen> ordered: Quickshell.screens.slice().sort((a, b) => (a.x - b.x) || (a.y - b.y))

    function isExcluded(screen: ShellScreen): bool {
        return !screens.includes(screen);
    }

    // A display's number (1, 2…) in Settings, 0 for one not connected
    function numberOf(name: string): int {
        return ordered.findIndex(s => s.name === name) + 1;
    }
}
