// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import Quickshell

// A KDE Connect device type's Material Symbol
Singleton {
    function iconFor(type: string): string {
        if (type === "phone")
            return "smartphone";
        if (type === "tablet")
            return "tablet";
        if (type === "laptop")
            return "laptop";
        if (type === "desktop")
            return "desktop_windows";
        if (type === "tv")
            return "tv";
        return "devices";
    }
}
