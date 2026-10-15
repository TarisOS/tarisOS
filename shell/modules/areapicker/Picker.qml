// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Taris
import Taris.I18n
import qs.components
import qs.components.effects
import qs.services

// The screenshot tool on one screen. The screen freezes when it opens (a still capture of it, shown
// over it), so nothing changes while picking: a drag selects an area, a click without one takes the
// whole screen, Escape cancels.
MouseArea {
    id: root

    required property LazyLoader loader
    required property ShellScreen screen

    // The capture is shown and the picker can take clicks
    readonly property bool frozen: screencopy.item?.hasContent ?? false
    property bool taken

    property real ssx
    property real ssy

    property real sx: 0
    property real sy: 0
    property real ex: 0
    property real ey: 0

    property real rsx: Math.min(sx, ex)
    property real rsy: Math.min(sy, ey)
    property real sw: Math.abs(sx - ex)
    property real sh: Math.abs(sy - ey)

    function save(area: rect): void {
        taken = true;
        const tmpfile = Qt.resolvedUrl(`/tmp/taris-picker-${Quickshell.processId}-${Date.now()}.png`);
        CUtils.saveItem(screencopy, tmpfile, area, path => {
            if (root.loader.clipboardOnly) {
                Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < " + path]);
                Quickshell.execDetached(["notify-send", "-a", "TarisOS", "-i", path, Tr.tr("Screenshot taken"), Tr.tr("Screenshot copied to clipboard")]);
            } else {
                // On the clipboard straight away (as a full-screen one is), then open to edit
                Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"; exec swappy -f "$1"', "_", path]);
            }
            closeAnim.start();
        });
    }

    anchors.fill: parent
    // Shown once the capture is in: the capture can't include the picker itself
    opacity: 0
    hoverEnabled: true
    cursorShape: Qt.CrossCursor

    onPressed: event => {
        ssx = event.x;
        ssy = event.y;
        sx = ex = event.x;
        sy = ey = event.y;
    }

    onReleased: {
        if (!frozen || taken || closeAnim.running)
            return;

        // A click (moved less than a drag) takes the whole screen
        const drag = Qt.styleHints.startDragDistance;
        if (sw < drag && sh < drag)
            save(Qt.rect(0, 0, width, height));
        else
            save(Qt.rect(Math.ceil(rsx), Math.ceil(rsy), Math.floor(sw), Math.floor(sh)));
    }

    onPositionChanged: event => {
        if (!pressed)
            return;
        sx = ssx;
        sy = ssy;
        ex = event.x;
        ey = event.y;
    }

    focus: true
    Keys.onEscapePressed: closeAnim.start()

    SequentialAnimation {
        id: closeAnim

        PropertyAction {
            target: root.loader
            property: "closing"
            value: true
        }
        ParallelAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            Anim {
                target: root
                properties: "rsx,rsy"
                to: 0
            }
            Anim {
                target: root
                property: "sw"
                to: root.screen.width
            }
            Anim {
                target: root
                property: "sh"
                to: root.screen.height
            }
        }
        PropertyAction {
            target: root.loader
            property: "activeAsync"
            value: false
        }
    }

    Loader {
        id: screencopy

        asynchronous: true
        anchors.fill: parent

        sourceComponent: ScreencopyView {
            captureSource: root.screen

            onHasContentChanged: {
                if (hasContent)
                    root.opacity = 1;
            }
        }
    }

    StyledRect {
        id: overlay

        anchors.fill: parent
        color: Colours.palette.m3secondaryContainer
        opacity: 0.3

        layer.enabled: true
        layer.effect: Mask {
            maskSource: selectionWrapper
            maskInverted: true
        }
    }

    Item {
        id: selectionWrapper

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            id: selectionRect

            x: root.rsx
            y: root.rsy
            implicitWidth: root.sw
            implicitHeight: root.sh
        }
    }

    // The selection's outline, from the first drag on
    Rectangle {
        id: outline

        visible: root.sw > 0 || root.sh > 0
        color: "transparent"
        border.width: 2
        border.color: Colours.palette.m3primary

        x: selectionRect.x - outline.border.width
        y: selectionRect.y - outline.border.width
        implicitWidth: selectionRect.implicitWidth + outline.border.width * 2
        implicitHeight: selectionRect.implicitHeight + outline.border.width * 2

        Behavior on border.color {
            CAnim {}
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.StandardLarge
        }
    }

    Behavior on rsx {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on rsy {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on sw {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on sh {
        enabled: !root.pressed

        Anim {}
    }
}
