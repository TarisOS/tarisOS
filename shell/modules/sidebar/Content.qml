// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import qs.components
import qs.services

Item {
    id: root

    required property Props props
    required property ScreenState screenState
    readonly property real naturalHeight: dock.naturalHeight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerLow

            NotifDock {
                id: dock

                objectName: "sidebarNotifications"

                props: root.props
                screenState: root.screenState
            }
        }

    }
}
