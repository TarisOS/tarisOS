// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import Taris.Config
import qs.components
import qs.components.controls
import qs.services

// A colour swatch; clicking it opens a picker (saturation/brightness square, hue strip
// and hex field). Emits picked when Done is pressed (ported from witchers-tweaks' ColorWell).
Item {
    id: well

    property color color: "#a855f7"
    property real hue: 0
    property real sat: 0
    property real val: 0
    readonly property color working: Qt.hsva(hue, sat, val, 1)

    signal picked(color value)

    function hex(c: color): string {
        const h = x => {
            const s = Math.round(x * 255).toString(16);
            return s.length < 2 ? `0${s}` : s;
        };
        return `#${h(c.r)}${h(c.g)}${h(c.b)}`;
    }

    // Opens the picker inside the settings page around the swatch, above it or below it, wherever
    // it fits. Outside the page it could reach past the settings overlay, where the shell's window
    // takes no input: a click there lands on the window below and closes the overlay.
    function openPicker(): void {
        let bounds = well.parent;
        while (bounds && (bounds.cappedWidth === undefined || bounds.embedded)) // The page (PageBase), not one embedded in it
            bounds = bounds.parent;
        const at = bounds ? well.mapToItem(bounds, 0, 0) : Qt.point(0, popup.implicitHeight + 6);
        const boundsHeight = bounds?.height ?? at.y + well.height + popup.implicitHeight + 6;
        const h = popup.implicitHeight, gap = 6;
        let y;
        if (at.y >= h + gap)
            y = -h - gap;
        else if (boundsHeight - at.y - well.height >= h + gap)
            y = well.height + gap;
        else
            y = Math.max(-at.y, Math.min(boundsHeight - at.y - h, -h - gap));
        popup.y = y;
        popup.x = Math.max(bounds ? -at.x : -Infinity, Math.min(0, well.width - popup.width));
        popup.open();
    }

    implicitWidth: 44
    implicitHeight: 28

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: well.color
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
    }

    StateLayer {
        radius: Tokens.rounding.full
        onClicked: {
            well.hue = Math.max(0, well.color.hsvHue);
            well.sat = well.color.hsvSaturation;
            well.val = well.color.hsvValue;
            hexField.text = well.hex(well.color);
            well.openPicker();
        }
    }

    Popup {
        id: popup

        // x and y: openPicker
        margins: Tokens.padding.small
        // Drawn in the settings' own window: a popup window of its own would sit outside the
        // settings overlay's focus grab, and clicking it would close the overlay
        popupType: Popup.Item
        width: 260
        padding: Tokens.padding.medium
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: StyledRect {
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh
        }

        contentItem: Column {
            spacing: Tokens.spacing.medium

            // Saturation left to right, brightness bottom to top
            Item {
                width: parent.width
                height: 150

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    color: Qt.hsva(well.hue, 1, 1, 1)

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#ffffffff" }
                            GradientStop { position: 1; color: "#00ffffff" }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#00000000" }
                            GradientStop { position: 1; color: "#ff000000" }
                        }
                    }
                }

                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    x: well.sat * parent.width - 7
                    y: (1 - well.val) * parent.height - 7
                    color: "transparent"
                    border.width: 2
                    border.color: well.val > 0.5 ? "black" : "white"
                }

                MouseArea {
                    function set(m: var): void {
                        well.sat = Math.max(0, Math.min(1, m.x / width));
                        well.val = Math.max(0, Math.min(1, 1 - m.y / height));
                        hexField.text = well.hex(well.working);
                    }

                    anchors.fill: parent
                    preventStealing: true
                    onPressed: m => set(m)
                    onPositionChanged: m => set(m)
                }
            }

            // Hue
            Item {
                width: parent.width
                height: 14

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0 / 6; color: "#ff0000" }
                        GradientStop { position: 1 / 6; color: "#ffff00" }
                        GradientStop { position: 2 / 6; color: "#00ff00" }
                        GradientStop { position: 3 / 6; color: "#00ffff" }
                        GradientStop { position: 4 / 6; color: "#0000ff" }
                        GradientStop { position: 5 / 6; color: "#ff00ff" }
                        GradientStop { position: 6 / 6; color: "#ff0000" }
                    }
                }

                Rectangle {
                    width: 6
                    height: parent.height + 4
                    y: -2
                    radius: 3
                    x: well.hue * parent.width - 3
                    color: "white"
                    border.width: 1
                    border.color: "black"
                }

                MouseArea {
                    function set(m: var): void {
                        well.hue = Math.max(0, Math.min(0.999, m.x / width));
                        hexField.text = well.hex(well.working);
                    }

                    anchors.fill: parent
                    preventStealing: true
                    onPressed: m => set(m)
                    onPositionChanged: m => set(m)
                }
            }

            Row {
                spacing: Tokens.spacing.small

                StyledRect {
                    width: 30
                    height: 30
                    radius: Tokens.rounding.small
                    color: well.working
                }

                StyledRect {
                    width: 110
                    height: 30
                    radius: Tokens.rounding.small
                    color: Colours.tPalette.m3surfaceContainer

                    TextInput {
                        id: hexField

                        x: Tokens.padding.small
                        width: parent.width - Tokens.padding.small * 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                        maximumLength: 7
                        onTextEdited: {
                            const t = text.replace(/^#/, "");
                            if (/^[0-9a-fA-F]{6}$/.test(t)) {
                                const c = Qt.color(`#${t}`);
                                well.hue = Math.max(0, c.hsvHue);
                                well.sat = c.hsvSaturation;
                                well.val = c.hsvValue;
                            }
                        }
                    }
                }

                TextButton {
                    text: qsTr("Done")
                    onClicked: {
                        well.picked(well.working);
                        popup.close();
                    }
                }
            }
        }
    }
}
