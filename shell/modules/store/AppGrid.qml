// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import qs.components
import qs.services
import qs.modules.store

// A titled grid of apps (only shown when there are some)
ColumnLayout {
    id: root

    required property StoreState sState
    property string title
    property var apps: []
    property int limit: -1

    Layout.fillWidth: true
    visible: apps.length > 0
    spacing: Tokens.spacing.medium

    StyledText {
        visible: root.title !== ""
        text: root.title
        font: Tokens.font.title.small
        color: Colours.palette.m3onSurface
    }

    GridLayout {
        Layout.fillWidth: true
        columns: Math.max(1, Math.floor(width / 300))
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.medium
        uniformCellWidths: true

        Repeater {
            model: root.limit > 0 ? root.apps.slice(0, root.limit) : root.apps

            AppTile {
                sState: root.sState
            }
        }
    }
}
