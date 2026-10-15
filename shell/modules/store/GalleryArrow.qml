// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.Config
import qs.components
import qs.components.controls
import qs.services

// A round arrow over a gallery's edge, shown while there's more that way
IconButton {
    id: root

    property bool shown: true

    anchors.verticalCenter: parent.verticalCenter
    type: IconButton.Tonal
    isRound: true
    font: Tokens.font.icon.large
    padding: Tokens.padding.small
    inactiveColour: Colours.palette.m3secondaryContainer
    inactiveOnColour: Colours.palette.m3onSecondaryContainer

    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
