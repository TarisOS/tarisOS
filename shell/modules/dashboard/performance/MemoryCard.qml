// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import Taris.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

StyledRect {
    id: root

    readonly property color accent: Colours.palette.m3tertiary

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.medium

    implicitWidth: layout.implicitWidth + Tokens.padding.large * 2
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ServiceRef {
        service: root.visible ? Memory : null
    }

    // Beside the CPU: the name and the amount used on the left, the usage ring on the right
    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "memory_alt"
                    fill: 1
                    color: root.accent
                    fontStyle: Tokens.font.icon.builders.medium.weight(Font.DemiBold).build() // DemiBold to fix fill issues
                }

                StyledText {
                    text: Tr.tr("Memory")
                    font: Tokens.font.title.medium
                }
            }

            Item {
                Layout.fillHeight: true
            }

            StyledText {
                text: Units.formatKibUsage(Memory.used, Memory.total)
                font: Tokens.font.body.medium
            }
        }

        CircularProgress {
            Layout.alignment: Qt.AlignVCenter
            implicitSize: usageColumn.implicitHeight + thickness + Tokens.padding.largeIncreased * 2
            startAngle: -225
            sweepAngle: 270

            fgColour: root.accent
            value: Memory.percentage

            Behavior on clampedVal {
                Anim {}
            }

            ColumnLayout {
                id: usageColumn

                anchors.centerIn: parent
                anchors.verticalCenterOffset: Tokens.padding.extraSmall
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Strings.percentOne(Memory.percentage)
                    font: Tokens.font.title.builders.large.width(90).build()
                    color: root.accent
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.trCtx("Used", "memory used")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
