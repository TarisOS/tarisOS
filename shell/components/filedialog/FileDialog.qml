// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Taris.I18n
import qs.components
import qs.services

// A file picker. It opens like the settings: in the overlay over everything on the focused screen,
// closed by clicking away (the popouts Wrapper shows it); in a window of its own only when there's
// no overlay to show it in.
LazyLoader {
    id: loader

    property list<string> cwd: ["Home"]
    property string filterLabel: Tr.tr("All files")
    property list<string> filters: ["*"]
    property string title: Tr.tr("Select a file")
    // "open" (a file), "directory" (a folder) or "save" (a file name in a folder)
    property string mode: "open"
    property string currentName // The file name to start with when saving
    property string acceptLabel // The accept button's text (Select, or Save when saving, by default)
    property var overlay: null // The popouts Wrapper showing it

    signal accepted(path: string)
    signal rejected

    function open(): void {
        const popouts = ShellState.componentsForActive()?.panels?.popouts;
        if (popouts?.showFileDialog(loader)) {
            overlay = popouts;
        } else {
            activeAsync = true;
        }
    }

    function close(): void {
        rejected();
    }

    function finish(): void {
        const shownIn = overlay;
        overlay = null;
        shownIn?.closeFileDialog(loader);
        activeAsync = false;
    }

    onAccepted: finish()
    onRejected: finish()

    FloatingWindow {
        implicitWidth: 1000
        implicitHeight: 600
        minimumSize.width: 400
        minimumSize.height: 300
        color: Colours.tPalette.m3surface
        surfaceFormat.opaque: false
        title: loader.title

        onVisibleChanged: {
            if (!visible)
                loader.rejected();
        }

        DialogContent {
            anchors.fill: parent
            loader: loader
        }

        Behavior on color {
            CAnim {}
        }
    }
}
