// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Taris.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.store

// A screenshot large, over the Store (sState.viewer): its full size once downloaded (the app
// page's meanwhile), the arrows or ←/→ for the others; Esc, the close button or a click beside
// it closes it
Item {
    id: root

    required property StoreState sState

    readonly property var viewer: sState.viewer
    readonly property var shot: viewer ? viewer.shots[viewer.index] : null
    property var fullPaths: ({}) // full address -> downloaded file
    property int req: -1

    function go(dir: int): void {
        if (!viewer)
            return;
        const index = viewer.index + dir;
        if (index >= 0 && index < viewer.shots.length)
            sState.viewer = {
                shots: viewer.shots,
                index
            };
    }

    // This screenshot's full size, and its neighbours' in the background, so stepping to them
    // shows theirs straight away
    function loadFull(): void {
        if (!viewer)
            return;
        AppStore.cancel(req);
        req = fetch(shot?.full ?? "");
        fetch(viewer.shots[viewer.index + 1]?.full ?? "");
        fetch(viewer.shots[viewer.index - 1]?.full ?? "");
    }

    function fetch(url: string): int {
        if (!url || fullPaths[url])
            return -1;
        return AppStore.request("image", {
            url
        }, path => {
            if (path) {
                const all = Object.assign({}, fullPaths);
                all[url] = path;
                fullPaths = all;
            }
        });
    }

    opacity: viewer ? 1 : 0
    visible: opacity > 0

    onShotChanged: loadFull()
    onViewerChanged: {
        if (viewer)
            forceActiveFocus();
    }
    Component.onDestruction: AppStore.cancel(req)

    Keys.onEscapePressed: sState.viewer = null
    Keys.onLeftPressed: go(-1)
    Keys.onRightPressed: go(1)

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    // The dim behind it; a click on it closes the preview
    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.extraLarge
        color: Qt.alpha(Colours.palette.m3scrim, 0.75)

        MouseArea {
            anchors.fill: parent
            onClicked: root.sState.viewer = null
            onWheel: wheel => wheel.accepted = true // The page behind doesn't scroll
        }
    }

    StyledClippingRect {
        anchors.centerIn: parent
        width: img.paintedWidth
        height: img.paintedHeight
        radius: Tokens.rounding.large
        color: "transparent"

        Image {
            id: img

            readonly property string full: root.fullPaths[root.shot?.full ?? ""] ?? ""

            anchors.centerIn: parent
            width: root.width - (prev.width + Tokens.padding.large * 2) * 2
            height: root.height - Tokens.padding.extraLarge * 4
            asynchronous: true
            // The picture shown stays until the next one (or its full size) is ready: no blank
            // frame between them
            retainWhileLoading: true
            fillMode: Image.PreserveAspectFit
            source: root.shot ? "file://" + (full || root.shot.thumb) : ""
            sourceSize: {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                return Qt.size(width * dpr, height * dpr);
            }
        }

        // Clicks on the picture itself don't close the preview
        MouseArea {
            anchors.fill: parent
        }
    }

    GalleryArrow {
        id: prev

        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.large
        icon: "chevron_left"
        shown: (root.viewer?.index ?? 0) > 0
        onClicked: root.go(-1)
    }

    GalleryArrow {
        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.large
        icon: "chevron_right"
        shown: root.viewer ? root.viewer.index < root.viewer.shots.length - 1 : false
        onClicked: root.go(1)
    }

    IconButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        icon: "close"
        type: IconButton.Tonal
        isRound: true
        inactiveColour: Colours.palette.m3secondaryContainer
        inactiveOnColour: Colours.palette.m3onSecondaryContainer
        onClicked: root.sState.viewer = null
    }
}
