// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Taris.Config
import qs.components
import qs.components.effects
import qs.services

// Tor's icon at the end of the tray, beside the apps' own (as NordVPN's is): its onion, dimmed
// while Tor is off. A click switches it; hovering shows its menu (popouts/TorMenu.qml).
MouseArea {
    id: root

    implicitWidth: Tokens.font.body.small.pointSize * 2
    implicitHeight: Tokens.font.body.small.pointSize * 2

    onClicked: Tor.toggle()

    ColouredIcon {
        anchors.fill: parent
        source: Quickshell.iconPath("tor")
        colour: Colours.palette.m3secondary
        layer.enabled: Config.bar.tray.recolour
        opacity: Tor.enabled ? 1 : 0.4

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
