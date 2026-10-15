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
import qs.modules.nexus.common

// Windows, their transparency and blur, and the window border, as in the witchers-tweaks settings
// app (WindowStyle: window-style.conf, read by taris.lua). The border follows the colour scheme
// until a colour is picked here.
PageBase {
    id: root

    readonly property var style: WindowStyle.style
    readonly property bool themeBorder: style.bordertheme !== "0"
    // The border's colours as they are: the scheme's while it follows the scheme
    readonly property list<string> gradientColours: themeBorder ? [Colours.palette.m3primary, Colours.palette.m3secondary, Colours.palette.m3tertiary].map(c => String(c)) : style.colors.split(/\s+/).filter(c => /^[0-9a-fA-F]{6}$/.test(c)).map(c => `#${c}`)
    readonly property string inactiveColour: themeBorder ? String(Colours.palette.m3outlineVariant) : `#${style.inactive}`
    // The border's one colour while the gradient is off
    readonly property string solidColour: !themeBorder && /^[0-9a-fA-F]{6}$/.test(style.solid) ? `#${style.solid}` : gradientColours[0] ?? ""

    function save(changes: var): void {
        WindowStyle.save(changes);
    }

    // A colour picked by hand: the border keeps the colours shown and stops following the scheme
    function setBorder(colours: list<string>, inactive: string, solid: string): void {
        save({
            colors: colours.map(c => c.slice(1, 7)).join(" "),
            solid: solid.slice(1, 7),
            inactive: inactive.slice(1, 7),
            bordertheme: "0"
        });
    }

    function setGradient(i: int, c: color): void {
        const cols = [...gradientColours];
        cols[i] = String(c);
        setBorder(cols, inactiveColour, solidColour);
    }

    title: Tr.tr("Window style")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Windows")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Rounded window corners")
            checked: root.style.roundingon === "1"
            onToggled: root.save({
                    roundingon: checked ? "1" : "0"
                })
        }

        RangeRow {
            visible: root.style.roundingon === "1"
            icon: "rounded_corner"
            label: Tr.tr("Corner rounding")
            from: 0
            to: 100
            step: 5
            current: Number(root.style.rounding)
            format: v => `${Math.round(v)}%`
            onCommitted: v => root.save({
                    rounding: String(Math.round(v))
                })
        }

        RangeRow {
            icon: "border_outer"
            label: Tr.tr("Border size")
            from: 0
            to: 10
            step: 1
            current: Number(root.style.bordersize)
            format: v => `${Math.round(v)} px`
            onCommitted: v => root.save({
                    bordersize: String(Math.round(v))
                })
        }

        RangeRow {
            icon: "border_inner"
            label: Tr.tr("Gaps in")
            from: 0
            to: 30
            step: 1
            current: Number(root.style.gapsin)
            format: v => `${Math.round(v)} px`
            onCommitted: v => root.save({
                    gapsin: String(Math.round(v))
                })
        }

        RangeRow {
            icon: "padding"
            label: Tr.tr("Gaps out")
            from: 0
            to: 60
            step: 1
            current: Number(root.style.gapsout)
            format: v => `${Math.round(v)} px`
            onCommitted: v => root.save({
                    gapsout: String(Math.round(v))
                })
        }

        ToggleRow {
            text: Tr.tr("New windows open floating")
            subtext: root.style.floatnew === "1" ? Tr.tr("Floating") : Tr.tr("Tiled")
            checked: root.style.floatnew === "1"
            onToggled: root.save({
                    floatnew: checked ? "1" : "0"
                })
        }

        ToggleRow {
            text: Tr.tr("Window buttons and drag strip on floating windows")
            checked: root.style.titlebars !== "0"
            onToggled: root.save({
                    titlebars: checked ? "1" : "0"
                })
        }

        ToggleRow {
            text: Tr.tr("Resize floating windows by their border")
            checked: root.style.borderresize !== "0"
            onToggled: root.save({
                    borderresize: checked ? "1" : "0"
                })
        }

        ToggleRow {
            text: Tr.tr("Slide workspaces in with a fade")
            checked: root.style.fade === "1"
            onToggled: root.save({
                    fade: checked ? "1" : "0"
                })
        }

        ToggleRow {
            text: Tr.tr("Swipe between workspaces with three fingers")
            checked: root.style.swipe === "1"
            onToggled: root.save({
                    swipe: checked ? "1" : "0"
                })
        }

        ToggleRow {
            last: true
            text: Tr.tr("One column per screen in the scrolling layout")
            checked: root.style.columns === "1"
            onToggled: root.save({
                    columns: checked ? "1" : "0"
                })
        }

        SectionHeader {
            text: Tr.tr("Transparency & blur")
        }

        RangeRow {
            first: true
            icon: "opacity"
            label: Tr.tr("Window opacity")
            from: 30
            to: 100
            step: 5
            current: Number(root.style.opacity)
            format: v => `${Math.round(v)}%`
            onCommitted: v => root.save({
                    opacity: String(Math.round(v))
                })
        }

        ToggleRow {
            last: root.style.blur === "0" && root.style.shellblur === "0"
            text: Tr.tr("Blur behind windows")
            checked: root.style.blur !== "0"
            onToggled: root.save({
                    blur: checked ? "1" : "0"
                })
        }

        RangeRow {
            visible: root.style.blur !== "0" || root.style.shellblur !== "0"
            icon: "blur_on"
            label: Tr.tr("Blur size")
            from: 1
            to: 20
            step: 1
            current: Number(root.style.blursize)
            format: v => String(Math.round(v))
            onCommitted: v => root.save({
                    blursize: String(Math.round(v))
                })
        }

        RangeRow {
            visible: root.style.blur !== "0" || root.style.shellblur !== "0"
            last: true
            icon: "blur_linear"
            label: Tr.tr("Blur passes")
            from: 1
            to: 4
            step: 1
            current: Number(root.style.blurpasses)
            format: v => String(Math.round(v))
            onCommitted: v => root.save({
                    blurpasses: String(Math.round(v))
                })
        }

        SectionHeader {
            text: Tr.tr("Window border")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Animated gradient border")
            checked: root.style.gradient === "1"
            onToggled: root.save({
                    gradient: checked ? "1" : "0"
                })
        }

        ToggleRow {
            text: Tr.tr("Match the theme colours")
            checked: root.themeBorder
            onToggled: root.save({
                    bordertheme: checked ? "1" : "0"
                })
        }

        ColourRow {
            visible: root.style.gradient === "1"
            label: Tr.tr("Gradient colors")

            Repeater {
                model: root.gradientColours

                ColorWell {
                    required property string modelData
                    required property int index

                    color: modelData
                    onPicked: c => root.setGradient(index, c)
                }
            }
        }

        ColourRow {
            visible: root.style.gradient !== "1"
            label: Tr.tr("Border colour")

            ColorWell {
                color: root.solidColour
                onPicked: c => root.setBorder(root.gradientColours, root.inactiveColour, String(c))
            }
        }

        ColourRow {
            label: Tr.tr("Inactive windows")

            ColorWell {
                color: root.inactiveColour
                onPicked: c => root.setBorder(root.gradientColours, String(c), root.solidColour)
            }
        }

        RowButton {
            last: true
            icon: "restart_alt"
            text: Tr.tr("Default colors")
            // Back to the scheme's colours (the accent, or the gradient from them)
            onClicked: root.save({
                    colors: WindowStyle.defaults.colors,
                    solid: WindowStyle.defaults.solid,
                    inactive: WindowStyle.defaults.inactive,
                    bordertheme: WindowStyle.defaults.bordertheme
                })
        }
    }

    // Label on the left, colour swatches on the right
    component ColourRow: ConnectedRect {
        id: colourRow

        property alias label: rowLabel.text
        default property alias swatches: swatchRow.data

        Layout.fillWidth: true
        implicitHeight: Math.max(rowLabel.implicitHeight, swatchRow.implicitHeight) + Tokens.padding.large * 2

        StyledText {
            id: rowLabel

            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.large
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            id: swatchRow

            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.large
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.small
        }
    }
}
