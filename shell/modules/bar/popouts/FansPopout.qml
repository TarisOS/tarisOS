// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    width: 300
    spacing: Tokens.spacing.small

    // Live readings while it's shown
    onVisibleChanged: Fans.watchers += visible ? 1 : -1
    Component.onCompleted: {
        if (visible)
            Fans.watchers++;
    }
    Component.onDestruction: {
        if (visible)
            Fans.watchers--;
    }

    // Sliders report their position (0-1); these map it to and from real values
    function toPos(v: real, from: real, to: real): real {
        return Math.max(0, Math.min(1, (v - from) / Math.max(1, to - from)));
    }

    function fromPos(p: real, from: real, to: real): real {
        return from + p * (to - from);
    }

    StyledText {
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        text: Tr.tr("Fans")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    StyledText {
        Layout.fillWidth: true
        Layout.rightMargin: Tokens.padding.extraSmall
        visible: !Fans.present || !Fans.control
        wrapMode: Text.WordWrap
        color: Colours.palette.m3onSurfaceVariant
        text: !Fans.present ? Tr.tr("No fan controller found") : Tr.tr("Read-only: add macsmc_hwmon.fan_control=1 to the kernel options and reboot to set speeds")
    }

    Repeater {
        model: Fans.fans

        ColumnLayout {
            id: fan

            required property var modelData
            readonly property var cfg: Fans.config(modelData.n)

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.rightMargin: Tokens.padding.extraSmall
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true

                MaterialIcon {
                    text: "mode_fan"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.large
                }

                StyledText {
                    Layout.fillWidth: true
                    text: fan.modelData.label
                    font: Tokens.font.title.small
                }

                StyledText {
                    text: Tr.tr("%1 RPM").arg(Fans.rpms[fan.modelData.n] ?? 0)
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: [
                        { mode: "auto", label: Tr.tr("Auto") },
                        { mode: "full", label: Tr.tr("Full") },
                        { mode: "constant", label: Tr.tr("Fixed") },
                        { mode: "range", label: Tr.tr("Range") }
                    ]

                    TextButton {
                        required property var modelData

                        Layout.fillWidth: true
                        disabled: !Fans.control || !fan.modelData.writable
                        type: TextButton.Tonal
                        isToggle: true
                        checked: fan.cfg.mode === modelData.mode
                        text: modelData.label
                        onClicked: Fans.setConfig(fan.modelData.n, { mode: modelData.mode })
                    }
                }
            }

            StyledText {
                visible: fan.cfg.mode === "constant"
                text: Tr.tr("Speed: %1 RPM").arg(Fans.clampRpm(fan.modelData, fan.cfg.rpm > 0 ? fan.cfg.rpm : fan.modelData.min))
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledSlider {
                Layout.fillWidth: true
                visible: fan.cfg.mode === "constant"
                implicitHeight: 24
                interactionOnMove: false // Apply on release only; each apply saves and re-reads the config
                value: root.toPos(fan.cfg.rpm, fan.modelData.min, fan.modelData.max)
                onInteraction: v => Fans.setConfig(fan.modelData.n, { rpm: Math.round(root.fromPos(v, fan.modelData.min, fan.modelData.max)) })
            }

            StyledText {
                visible: fan.cfg.mode === "range"
                text: Tr.tr("Quiet at %1°C, full at %2°C (hottest: %3)").arg(fan.cfg.from).arg(fan.cfg.to).arg(Fans.hottest ? `${Fans.hottest.label} ${Fans.hottest.celsius}°C` : "—")
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            StyledSlider {
                Layout.fillWidth: true
                visible: fan.cfg.mode === "range"
                implicitHeight: 24
                interactionOnMove: false // Apply on release only; each apply saves and re-reads the config
                value: root.toPos(fan.cfg.from, 30, 100)
                onInteraction: v => Fans.setConfig(fan.modelData.n, { from: Math.min(Math.round(root.fromPos(v, 30, 100)), fan.cfg.to - 5) })
            }

            StyledSlider {
                Layout.fillWidth: true
                visible: fan.cfg.mode === "range"
                implicitHeight: 24
                interactionOnMove: false // Apply on release only; each apply saves and re-reads the config
                value: root.toPos(fan.cfg.to, 30, 100)
                onInteraction: v => Fans.setConfig(fan.modelData.n, { to: Math.max(Math.round(root.fromPos(v, 30, 100)), fan.cfg.from + 5) })
            }
        }
    }

    // Temperatures
    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        Layout.bottomMargin: Tokens.padding.small
        columns: 2
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.extraSmall

        Repeater {
            model: Fans.temps.slice(0, 8)

            RowLayout {
                required property var modelData

                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: parent.modelData.label
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }

                StyledText {
                    text: `${Math.round(parent.modelData.celsius)}°C`
                    font: Tokens.font.label.medium
                }
            }
        }
    }
}
