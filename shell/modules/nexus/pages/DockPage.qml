// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Dock: show/hide it (at the bottom of the screen) and its apps button, Settings and Trash, and
// manage pinned apps (unpin, reorder; the dock itself also rearranges them by dragging)
PageBase {
    id: root

    title: Tr.tr("Dock")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: Tr.tr("Show the dock")
            checked: Dock.enabled
            onToggled: Dock.setEnabled(checked)
        }

        // How long the pointer has to push into the bottom edge (modules/drawers/Interactions.qml)
        SliderRow {
            visible: Dock.enabled
            icon: "vertical_align_bottom"
            label: Tr.tr("Push Force")
            valueLabel: Dock.pushTime
            value: Dock.pushTime / 200
            onMoved: v => Dock.setPushTime(Math.round(v * 40) * 5)
        }

        ToggleRow {
            text: Tr.tr("Show the apps button in the dock")
            subtext: Tr.tr("Opens the app launcher")
            checked: Dock.showAppsButton
            onToggled: Dock.setShowAppsButton(checked)
        }

        ToggleRow {
            text: Tr.tr("Show Settings in the dock")
            checked: Dock.showSettings
            onToggled: Dock.setShowSettings(checked)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Show the Trash in the dock")
            checked: Dock.showTrash
            onToggled: Dock.setShowTrash(checked)
        }

        SectionHeader {
            text: Tr.tr("Pinned apps")
        }

        Repeater {
            model: Dock.pinned

            ConnectedRect {
                id: pin

                required property string modelData
                required property int index
                readonly property DesktopEntry entry: DesktopEntries.byId(modelData) ?? DesktopEntries.heuristicLookup(modelData)

                Layout.fillWidth: true
                first: index === 0
                last: index === Dock.pinned.length - 1
                implicitHeight: pinRow.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: pinRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: pin.entry?.name ?? pin.modelData
                    }

                    IconButton {
                        icon: "arrow_upward"
                        type: IconButton.Text
                        disabled: pin.index === 0
                        onClicked: Dock.move(pin.modelData, -1)
                    }

                    IconButton {
                        icon: "arrow_downward"
                        type: IconButton.Text
                        disabled: pin.index === Dock.pinned.length - 1
                        onClicked: Dock.move(pin.modelData, 1)
                    }

                    IconButton {
                        icon: "keep_off"
                        type: IconButton.Tonal
                        onClicked: Dock.togglePin(pin.modelData)
                    }
                }
            }
        }

        StyledText {
            visible: Dock.pinned.length === 0
            text: Tr.tr("No pinned apps yet")
            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
