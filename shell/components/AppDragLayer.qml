// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import qs.services

// A StateLayer whose app can be dragged to the dock (from the dock itself or the app drawer): a
// left press that moves past a few pixels becomes a drag, the dock under it shows where the app
// would land, and letting go drops it there. Clicks that weren't drags come as activated.
StateLayer {
    id: root

    required property DesktopEntry entry
    property bool draggable: true
    // In the dock: dropped anywhere off it, the app is unpinned
    property bool fromDock
    property bool dragging
    readonly property real dragThreshold: 8

    signal activated(event: MouseEvent)

    function windowPos(x: real, y: real): point {
        const win = QsWindow.window as QsWindow;
        return mapToItem(win.contentItem, x, y);
    }

    function stopDrag(drop: bool): void {
        if (!dragging)
            return;
        dragging = false;
        if (drop)
            Dock.endDrag();
        else
            Dock.cancelDrag();
    }

    preventStealing: true

    onPositionChanged: event => {
        if (!pressed || !(event.buttons & Qt.LeftButton))
            return;
        if (!dragging && draggable && entry && Math.hypot(event.x - pressX, event.y - pressY) > dragThreshold) {
            dragging = true;
            Dock.startDrag(entry, QsWindow.window, windowPos(event.x, event.y), fromDock);
        }
        if (dragging)
            Dock.dragPos = windowPos(event.x, event.y);
    }

    onClicked: event => {
        if (!dragging)
            activated(event);
    }

    // After clicked, so the release that ends a drag isn't taken for a click
    onPressedChanged: {
        if (!pressed)
            Qt.callLater(() => stopDrag(true));
    }
    onCanceled: stopDrag(false)
    Component.onDestruction: stopDrag(false)
}
