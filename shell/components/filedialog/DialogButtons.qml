// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property var dialog
    required property FolderContents folder

    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium

        spacing: Tokens.spacing.small

        StyledText {
            text: root.dialog.mode === "save" ? Tr.trCtx("Name:", "file name to save as") : root.dialog.mode === "directory" ? Tr.trCtx("Folder:", "folder to pick") : Tr.trCtx("Filter:", "file filter")
        }

        // Saving: the file name
        StyledTextField {
            Layout.fillWidth: true
            Layout.rightMargin: Tokens.spacing.medium
            visible: root.dialog.mode === "save"
            verticalPadding: Tokens.padding.small
            text: root.dialog.fileName
            focus: visible
            onTextEdited: root.dialog.fileName = text
            onAccepted: root.dialog.acceptSelection()
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.rightMargin: Tokens.spacing.medium
            visible: root.dialog.mode !== "save"

            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            StyledText {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium

                elide: Text.ElideMiddle
                text: {
                    if (root.dialog.mode === "directory")
                        return root.dialog.folderPath;
                    const filters = root.dialog.filters.map(f => `*.${f}`).join(Tr.trCtx(", ", "file filter separator"));
                    // TRANSLATORS: %1 = filter label, %2 = file patterns
                    return Tr.trCtx("%1 (%2)", "file filter label and patterns").arg(root.dialog.filterLabel).arg(filters);
                }
            }
        }

        StyledRect {
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            implicitWidth: selectText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: selectText.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                disabled: !root.dialog.selectionValid
                onClicked: root.dialog.acceptSelection()
            }

            StyledText {
                id: selectText

                anchors.centerIn: parent
                anchors.margins: Tokens.padding.medium

                text: root.dialog.nameExists ? Tr.trCtx("Replace", "button: save over an existing file") : root.dialog.acceptLabel
                color: root.dialog.selectionValid ? Colours.palette.m3onSurface : Colours.palette.m3outline
            }
        }

        StyledRect {
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.medium

            implicitWidth: cancelText.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: cancelText.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                onClicked: {
                    root.dialog.rejected();
                }
            }

            StyledText {
                id: cancelText

                anchors.centerIn: parent
                anchors.margins: Tokens.padding.medium

                text: Tr.trCtx("Cancel", "button")
            }
        }
    }
}
