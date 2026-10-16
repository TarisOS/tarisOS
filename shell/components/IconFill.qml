// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell.Widgets

// An icon in full colour over the same icon greyed out, filled from the bottom as far as progress
// (0 to 1) says: an app installed on first use, while it installs (services/OnDemandInstaller.qml)
Item {
    id: root

    required property url source
    property real progress

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * root.progress
        clip: true

        Behavior on height {
            Anim {}
        }

        IconImage {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            implicitSize: root.width
            source: root.source
        }
    }
}
