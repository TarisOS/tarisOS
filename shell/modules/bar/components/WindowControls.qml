// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Taris.Config
import qs.components
import qs.services

// Close, minimize and restore for the active window, shown in the bar while it's
// maximized or fullscreen. Minimized windows wait in special:minimized; the dock restores them.
// The bar's own look: a pill as wide as the others, with three alike buttons in the Highlights
// colour (like the power button), their round hover fitting the pill's rounded ends.
StyledRect {
    id: root

    readonly property var win: Hypr.activeToplevel
    readonly property bool shown: !!win && (Hypr.focusedWorkspace?.hasFullscreen ?? false)
    readonly property string addr: win ? `address:0x${win.address}` : ""
    readonly property real padding: Math.max(0, (implicitWidth - closeButton.implicitHeight) / 2)

    function run(lua: string, legacy: string): void {
        Hypr.dispatch(Hypr.usingLua ? lua : legacy);
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: shown ? column.implicitHeight + padding * 2 : 0
    opacity: shown ? 1 : 0
    clip: true
    radius: Tokens.rounding.full
    color: Colours.tPalette.m3surfaceContainer

    Behavior on implicitHeight {
        Anim {}
    }
    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    component ControlButton: Item {
        id: control

        required property string icon

        signal clicked

        implicitWidth: Tokens.sizes.bar.innerWidth
        implicitHeight: label.implicitHeight + Tokens.padding.small

        StateLayer {
            anchors.fill: undefined
            anchors.centerIn: parent
            implicitWidth: control.implicitHeight
            implicitHeight: control.implicitHeight
            radius: Tokens.rounding.full
            onClicked: control.clicked()
        }

        MaterialIcon {
            id: label

            anchors.centerIn: parent
            text: control.icon
            color: Colours.palette.m3secondary
            fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
        }
    }

    Column {
        id: column

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        ControlButton {
            id: closeButton

            icon: "close"
            onClicked: root.run(`hl.dsp.window.close({ window = "${root.addr}" })`, `closewindow ${root.addr}`)
        }

        ControlButton {
            // (Material Symbols' "minimize" sits at the bottom of its box: "remove" is centred)
            icon: "remove"
            onClicked: root.run(`hl.dsp.window.move({ window = "${root.addr}", workspace = "special:minimized", follow = false })`, `movetoworkspacesilent special:minimized,${root.addr}`)
        }

        ControlButton {
            icon: "fullscreen_exit"
            onClicked: root.run(`hl.dsp.window.fullscreen({ mode = "maximized" })`, "fullscreen 1")
        }
    }
}
