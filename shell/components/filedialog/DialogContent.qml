// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.I18n

// The file dialog itself (sidebar, path, files, buttons), for a FileDialog: shown in the
// settings-style overlay, or in a window of its own when there's no overlay to show it in.
Item {
    id: root

    required property var loader // The FileDialog (null while the overlay fades out after it)
    property list<string> cwd: loader?.cwd ?? ["Home"]
    readonly property string filterLabel: loader?.filterLabel ?? ""
    readonly property list<string> filters: loader?.filters ?? ["*"]
    readonly property string mode: loader?.mode ?? "open"
    property string fileName: loader?.currentName ?? "" // Saving: the name typed (or picked)
    readonly property string folderPath: folderContents.folderPath
    // Saving over a file that's already there (the button says Replace)
    readonly property bool nameExists: mode === "save" && fileName.length > 0 && folderContents.hasName(fileName)
    readonly property string acceptLabel: loader?.acceptLabel || (mode === "save" ? Tr.trCtx("Save", "button") : Tr.trCtx("Select", "button"))

    readonly property bool selectionValid: {
        const file = folderContents.currentItem?.modelData;
        if (mode === "save")
            return fileName.trim().length > 0 && !fileName.includes("/");
        if (mode === "directory")
            return !file || file.isDir;
        return (file && !file.isDir && (filters.includes("*") || filters.some(filter => filter.toLowerCase() === file.suffix.toLowerCase()))) ?? false;
    }

    // The accept button (or Enter, or a double click): what the mode picks
    function acceptSelection(): void {
        if (!selectionValid)
            return;
        const file = folderContents.currentItem?.modelData;
        if (mode === "save")
            accepted(`${folderPath}/${fileName.trim()}`);
        else if (mode === "directory")
            accepted(file?.isDir ? file.path : folderPath);
        else
            accepted(file.path);
    }

    function accepted(path: string): void {
        loader?.accepted(path);
    }

    function rejected(): void {
        loader?.rejected();
    }

    RowLayout {
        anchors.fill: parent

        spacing: 0

        Sidebar {
            Layout.fillHeight: true
            dialog: root
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            spacing: 0

            HeaderBar {
                Layout.fillWidth: true
                dialog: root
            }

            FolderContents {
                id: folderContents

                Layout.fillWidth: true
                Layout.fillHeight: true
                dialog: root
            }

            DialogButtons {
                Layout.fillWidth: true
                dialog: root
                folder: folderContents
            }
        }
    }
}
