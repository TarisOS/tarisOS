// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar
    property bool dock // Hovered at the bottom edge (it also shows while the app drawer is open)

    // Dashboard state
    property int dashboardTab
    property bool agentTabActive // The Agent tab is the dashboard's current one
    property bool statusEditing // The status is being typed in: it needs the keyboard
    property date dashboardDate: new Date()
}
