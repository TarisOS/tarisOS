// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import Quickshell
import Quickshell.Wayland
import Taris.Config
import qs.services

// qmllint disable uncreatable-type
PanelWindow {
    // qmllint enable uncreatable-type
    required property string name

    WlrLayershell.namespace: `taris-${name}`
    color: "transparent"

    contentItem.Config.screen: Screens.configOf(screen.name)
    contentItem.Tokens.screen: Screens.configOf(screen.name)
}
