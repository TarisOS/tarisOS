// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Tor (services/Tor.qml, /usr/lib/taris/tor): the switch, a new identity, the bridges (Tor's
// built-in ones, or lines from bridges.torproject.org), a circuit of its own for each site and a
// random hardware address. Everything but the switch on and a new identity asks for the password.
PageBase {
    id: root

    // Custom picked, its lines not saved yet
    property bool pickingCustom
    readonly property string bridgesShown: pickingCustom ? "custom" : Tor.bridges
    readonly property list<string> typedBridges: bridgeLines.text.split("\n").map(l => l.trim()).filter(l => l)

    title: Tr.tr("Tor")
    isSubPage: true

    Component.onCompleted: {
        Tor.readSettings();
        bridgeLines.text = Tor.customBridges.join("\n");
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: Tr.trCtx("Connect", "tor switch")
            subtext: {
                if (Tor.failed)
                    return Tr.tr("Couldn't start");
                if (Tor.connected)
                    return Tor.exitAddress ? Tr.trCtx("Connected · %1", "tor state, the exit's address").arg(Tor.exitAddress) : Tr.trCtx("Connected", "vpn state");
                if (Tor.connecting)
                    return Tr.tr("Connecting...");
                return "";
            }
            checked: Tor.enabled
            disabled: Tor.switching
            onToggled: Tor.toggle()

            Timer {
                running: root.visible
                repeat: true
                triggeredOnStart: true
                interval: 5000
                onTriggered: Tor.refresh()
            }
        }

        RowButton {
            last: true
            icon: "autorenew"
            text: Tr.tr("New identity")
            disabled: !Tor.connected || Tor.changing
            onClicked: Tor.newIdentity()
        }

        // ---------- Bridges ----------
        SectionHeader {
            text: Tr.tr("Bridges")
        }

        ChoiceRow {
            first: true
            last: root.bridgesShown !== "custom"
            label: Tr.tr("Bridges")
            options: [
                {
                    value: "none",
                    label: Tr.trCtx("Off", "tor bridges")
                },
                {
                    value: "obfs4",
                    label: "obfs4"
                },
                {
                    value: "snowflake",
                    label: "Snowflake"
                },
                {
                    value: "meek",
                    label: "meek"
                },
                {
                    value: "custom",
                    label: Tr.trCtx("Custom", "tor bridges")
                }
            ]
            current: root.bridgesShown
            enabled: !Tor.changing
            onChosen: v => {
                // Custom bridges are only set once there are lines to save
                root.pickingCustom = v === "custom";
                if (v !== "custom")
                    Tor.setOption(["bridges", v]);
            }
        }

        ConnectedRect {
            visible: root.bridgesShown === "custom"
            Layout.fillWidth: true
            implicitHeight: Math.max(bridgeLines.implicitHeight, 120) + Tokens.padding.medium * 2

            TextArea {
                id: bridgeLines

                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                anchors.topMargin: Tokens.padding.medium
                anchors.bottomMargin: Tokens.padding.medium
                padding: 0
                background: null
                wrapMode: TextArea.WrapAnywhere
                placeholderText: "obfs4 192.0.2.1:443 …"
                placeholderTextColor: Colours.palette.m3outline
                color: Colours.palette.m3onSurface
                selectionColor: Colours.palette.m3secondary
                selectedTextColor: Colours.palette.m3onSecondary
                font: Tokens.font.body.small
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            }
        }

        ConnectedRect {
            visible: root.bridgesShown === "custom"
            last: true
            Layout.fillWidth: true
            implicitHeight: saveRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: saveRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    text: Tr.trCtx("Save", "button")
                    disabled: Tor.changing || root.typedBridges.length === 0 || (Tor.bridges === "custom" && root.typedBridges.join("\n") === Tor.customBridges.join("\n"))
                    onClicked: {
                        root.pickingCustom = false;
                        Tor.setOption(["bridges", "custom", ...root.typedBridges]);
                    }
                }
            }
        }

        // ---------- Privacy ----------
        SectionHeader {
            text: Tr.tr("Privacy")
        }

        ToggleRow {
            first: true
            text: Tr.tr("A separate circuit for each site")
            checked: Tor.isolate
            disabled: Tor.changing
            onToggled: Tor.setOption(["isolate", checked ? "on" : "off"])
        }

        ToggleRow {
            last: true
            text: Tr.tr("Random hardware address")
            checked: Tor.randomMac
            disabled: Tor.changing
            onToggled: Tor.setOption(["mac", checked ? "on" : "off"])
        }
    }
}
