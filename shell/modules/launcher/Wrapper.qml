// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Taris.Config
import qs.components
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property var panels

    readonly property bool shouldBeActive: screenState.launcher && Config.launcher.enabled

    readonly property real maxHeight: {
        let max = screen.height - Config.border.thickness * 2 + Tokens.padding.extraLarge;
        if (screenState.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }

    property real offsetScale: shouldBeActive ? 0 : 1
    // Built at the first opening and kept: building it (its apps) on every opening took about 200 ms
    // of the main thread as it opened. While closed it's hidden, its search empty
    property bool built

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            built = true;
            implicitHeight = Qt.binding(() => content.implicitHeight);
        } else {
            implicitHeight = implicitHeight; // Break binding during close anim
        }
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    // Closed, the width it had when its content went with it (the frame's shapes follow it)
    implicitWidth: (shouldBeActive || visible ? content.implicitWidth : 0) || 630 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Component.onCompleted: Qt.callLater(() => Apps) // Load apps on init

    Behavior on offsetScale {
        Anim {}
    }

    // Cut off at the dock's top edge: the drawer comes out from behind the whole dock (its
    // background included) as it slides up, instead of its apps passing over it
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.panels.dock.visible ? Math.max(0, root.panels.dock.y - root.y) : parent.height
        clip: true

        Loader {
            id: content

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            active: root.built

            sourceComponent: Content {
                screenState: root.screenState
                panels: root.panels
                maxHeight: root.maxHeight
            }
        }
    }
}
