// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell

// TarisOS's logo in its own colours, fitted inside the item
Item {
    id: root

    implicitWidth: 128
    implicitHeight: 117

    Image {
        anchors.fill: parent
        source: Quickshell.shellPath("assets/logo.png")
        fillMode: Image.PreserveAspectFit
        mipmap: true
    }
}
