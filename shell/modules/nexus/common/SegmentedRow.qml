// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// One of a few choices side by side (rotation, position...), the way the Witcher's Tweaks
// settings change them. options: [{ value, label }]; emits chosen(value).
ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    property var options: []
    property var current

    signal chosen(value: var)

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: !!root.subtext
                text: root.subtext
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        Row {
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root.options

                TextButton {
                    required property var modelData

                    type: TextButton.Tonal
                    isToggle: true
                    checked: modelData.value === root.current
                    text: modelData.label
                    onClicked: {
                        if (modelData.value !== root.current)
                            root.chosen(modelData.value);
                    }
                }
            }
        }
    }
}
