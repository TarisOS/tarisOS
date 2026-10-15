// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import qs.components

Item {
    id: root

    required property ScreenState screenState
    required property Item sidebarPanel
    // Both hang from the top edge, so where the dashboard reaches under the popups each would draw
    // over the other's background: the popups make way while it's there and come back after
    required property Item dashboardPanel
    readonly property bool covered: dashboardPanel.visible && dashboardPanel.x + dashboardPanel.width > x
    property alias osdPanel: content.osdPanel
    property alias sessionPanel: content.sessionPanel
    property alias utilitiesPanel: content.utilitiesPanel

    visible: height > 0
    anchors.topMargin: -5
    implicitWidth: Math.max(sidebarPanel.width, content.implicitWidth)
    implicitHeight: covered ? 0 : content.implicitHeight

    Content {
        id: content

        anchors.topMargin: -root.anchors.topMargin
        visible: !root.covered
        screenState: root.screenState
    }
}
