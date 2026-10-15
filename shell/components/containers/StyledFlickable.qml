// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import qs.components

Flickable {
    id: root

    property bool doneFakeFlick
    // In contentItem, so anything that sets contentItem.children has to list it too
    readonly property alias glide: glide

    maximumFlickVelocity: 3000

    rebound: Transition {
        onRunningChanged: {
            if (!running && !root.doneFakeFlick) {
                root.doneFakeFlick = true;
                root.flick(1, 1);
                root.flick(-1, -1);
                Qt.callLater(() => root.cancelFlick());
            }
        }

        Anim {
            properties: "x,y"
        }
    }

    // Momentum scrolling for wheels and touchpads
    Glide {
        id: glide

        flickable: root
        horizontal: root.flickableDirection === Flickable.HorizontalFlick
    }

    Timer {
        running: root.doneFakeFlick
        interval: 10
        onTriggered: root.doneFakeFlick = false
    }
}
