// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

// The setup screen's Wi-Fi step (optional: everything is installed already): the networks around,
// a password for a secured one
ColumnLayout {
    id: root

    // The network a password is being typed for
    property string selected
    property string connectError

    function connect(ssid: string, password: string): void {
        connectError = "";
        Nmcli.connectToNetwork(ssid, password, "", result => {
            if (result?.success) {
                root.selected = "";
                passwordField.text = "";
            } else if (result?.needsPassword) {
                root.selected = ssid;
                passwordField.forceActiveFocus();
            } else {
                root.connectError = Tr.tr("Couldn't join %1").arg(ssid);
            }
        });
    }

    function choose(ap: var): void {
        if (ap.active)
            return;
        if (ap.isSecure && !Nmcli.hasSavedProfile(ap.ssid)) {
            selected = ap.ssid;
            passwordField.text = "";
            passwordField.forceActiveFocus();
        } else {
            selected = "";
            connect(ap.ssid, "");
        }
    }

    spacing: Tokens.spacing.medium

    Component.onCompleted: Nmcli.rescanWifi()

    TextButton {
        visible: !Nmcli.wifiEnabled
        type: TextButton.Tonal
        isRound: true
        horizontalPadding: Tokens.padding.largeIncreased
        verticalPadding: Tokens.padding.medium
        text: Tr.tr("Turn Wi-Fi on")
        onClicked: Nmcli.enableWifi(true)
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        StyledText {
            anchors.centerIn: parent
            visible: view.count === 0
            text: Nmcli.scanning ? Tr.tr("Looking for networks…") : Tr.tr("No networks found")
            color: Colours.palette.m3outline
        }

        StyledListView {
            id: view

            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            spacing: Tokens.spacing.extraSmall / 2
            boundsBehavior: Flickable.StopAtBounds

            model: ScriptModel {
                values: [...Nmcli.networks].filter(n => n.ssid).sort((a, b) => (b.active - a.active) || (b.strength - a.strength))
            }

            delegate: Item {
                id: row

                required property var modelData
                readonly property bool connecting: Nmcli.connectingSsid() === modelData.ssid

                width: view.width
                implicitHeight: name.implicitHeight + Tokens.padding.medium * 2

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.medium
                    color: row.modelData.active || root.selected === row.modelData.ssid ? Colours.palette.m3secondaryContainer : "transparent"
                }

                StateLayer {
                    radius: Tokens.rounding.medium
                    disabled: row.connecting
                    onClicked: root.choose(row.modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: Icons.getNetworkIcon(row.modelData.strength)
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        id: name

                        Layout.fillWidth: true
                        text: row.modelData.ssid
                        elide: Text.ElideRight
                    }

                    MaterialIcon {
                        visible: row.modelData.isSecure
                        text: "lock"
                        color: Colours.palette.m3outline
                    }

                    LoadingIndicator {
                        visible: row.connecting
                        implicitSize: name.implicitHeight
                    }

                    MaterialIcon {
                        visible: row.modelData.active
                        text: "check"
                        color: Colours.palette.m3onSecondaryContainer
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.selected !== ""
        spacing: Tokens.spacing.small

        StyledTextField {
            id: passwordField

            // Shown as typed while the eye is on
            property bool revealed

            echoMode: revealed ? TextInput.Normal : TextInput.Password
            trailingIcon: "visibility"
            trailingIconClickable: true
            trailingIconColour: revealed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            onTrailingIconClicked: revealed = !revealed

            Layout.fillWidth: true
            leadingIcon: "password"
            placeholderText: Tr.tr("Password for %1").arg(root.selected)
            onAccepted: {
                if (text)
                    root.connect(root.selected, text);
            }
        }

        TextButton {
            type: TextButton.Tonal
            isRound: true
            horizontalPadding: Tokens.padding.largeIncreased
            verticalPadding: Tokens.padding.medium
            disabled: passwordField.text === ""
            text: Tr.tr("Join")
            onClicked: root.connect(root.selected, passwordField.text)
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.connectError
        color: Colours.palette.m3error
    }
}
