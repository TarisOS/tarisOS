// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Taris
import Taris.Config
import qs.components
import qs.services

// The dock, at the bottom of the screen: hidden until the pointer touches the bottom edge under it
// (modules/drawers/Interactions sets screenState.dock), then sliding up like the other drawers.
// It stays up while the app drawer is open (which opens around it), while one of its menus is open
// and while an app is dragged on this screen.
Item {
    id: root

    required property ScreenState screenState

    readonly property int padding: Tokens.padding.medium
    // As wide as its icons, up to exactly the open app drawer's width (modules/launcher/Content:
    // its apps' width and its padding); past that the icons get smaller instead
    readonly property real fixedWidth: Tokens.sizes.launcher.itemWidth + Tokens.padding.large * 2
    readonly property int clampedPadding: CUtils.clamp(padding - Config.border.thickness, 0, padding)
    readonly property bool dragging: Dock.dragApp !== null && Dock.dragWindow === QsWindow.window
    readonly property bool shouldBeActive: Dock.enabled && (screenState.dock || screenState.launcher || content.held || dragging)
    // One of its menus is open: they open above it, outside its panel
    readonly property bool held: content.held
    // The height it takes when shown (the app drawer leaves this much room for it)
    readonly property real nonAnimHeight: content.implicitHeight + padding + clampedPadding
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitWidth: content.capped ? fixedWidth : content.implicitWidth + padding * 2
    implicitHeight: nonAnimHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Behavior on implicitWidth {
        Anim {}
    }

    DockContent {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.padding
        screenState: root.screenState
        maxWidth: root.fixedWidth - root.padding * 2
    }
}
