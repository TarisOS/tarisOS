// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Taris.Config
import Taris.I18n
import Taris.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

// The session's Bluetooth questions (its Bluetooth agent, BluetoothAgent): a device that wants to
// pair, the code both screens show, a PIN or passkey to type here or on the device, a device that
// isn't paired asking to connect. On the focused screen, over everything, styled like the password
// prompt (modules/polkit); its window only exists while BlueZ is waiting.
Scope {
    id: root

    // The window only appears once the shell's focus grabs are gone (the Binding below turns them
    // off), as the password prompt's does: Hyprland gives no keyboard focus to a surface outside an
    // active grab
    property bool grabsGone

    readonly property bool asking: BluetoothAgent.kind !== BluetoothAgent.None
    // A PIN or passkey is typed here
    readonly property bool typing: BluetoothAgent.kind === BluetoothAgent.PinCode || BluetoothAgent.kind === BluetoothAgent.Passkey
    // A code is shown to type on the device: nothing to answer, only to cancel
    readonly property bool displaying: BluetoothAgent.kind === BluetoothAgent.DisplayPinCode || BluetoothAgent.kind === BluetoothAgent.DisplayPasskey

    onAskingChanged: {
        grabsGone = false;
        if (asking)
            grabsGoneTimer.restart();
        else
            grabsGoneTimer.stop();
    }

    Binding {
        target: ShellState
        property: "bluetoothPrompt"
        value: root.asking
    }

    Timer {
        id: grabsGoneTimer

        interval: 100
        onTriggered: root.grabsGone = true
    }

    LazyLoader {
        active: root.asking && root.grabsGone

        StyledWindow {
            id: win

            readonly property string device: BluetoothAgent.deviceName || BluetoothAgent.deviceAddress

            // Each question (the next one reuses this window): an empty field, focused
            function startRequest(): void {
                field.text = "";
                if (root.typing)
                    field.forceActiveFocus();
                else
                    dialog.forceActiveFocus();
            }

            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
            name: "bluetooth-prompt"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Component.onCompleted: startRequest()

            Connections {
                function onRequestChanged(): void {
                    if (root.asking)
                        win.startRequest();
                }

                target: BluetoothAgent
            }

            StyledRect {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3scrim, 0.5)
                opacity: dialog.opacity
            }

            Item {
                id: dialog

                function confirm(): void {
                    if (root.typing) {
                        if (field.text.length > 0)
                            BluetoothAgent.submit(field.text);
                    } else if (!root.displaying) {
                        BluetoothAgent.accept();
                    }
                }

                anchors.centerIn: parent
                width: Math.min(parent.width * 0.9, 460)
                height: layout.implicitHeight + Tokens.padding.extraLarge * 2

                opacity: 0
                scale: 0.9
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }

                // Esc anywhere in the dialog says no (or stops the pairing), Enter says yes
                Keys.onEscapePressed: BluetoothAgent.reject()
                Keys.onReturnPressed: confirm()
                Keys.onEnterPressed: confirm()

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Behavior on scale {
                    Anim {}
                }

                Elevation {
                    anchors.fill: parent
                    radius: bg.radius
                    level: 4
                }

                StyledRect {
                    id: bg

                    anchors.fill: parent
                    radius: Tokens.rounding.extraLargeIncreased
                    color: Colours.tPalette.m3surface // The windows' background, as Settings and the Store have
                }

                ColumnLayout {
                    id: layout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.extraLarge
                    anchors.bottomMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.large

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.large

                        StyledRect {
                            implicitWidth: implicitHeight
                            implicitHeight: deviceIcon.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3secondaryContainer

                            MaterialIcon {
                                id: deviceIcon

                                anchors.centerIn: parent
                                text: Icons.getBluetoothIcon(BluetoothAgent.deviceIcon)
                                color: Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.large
                                fill: 1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                switch (BluetoothAgent.kind) {
                                case BluetoothAgent.AuthorizeService:
                                    return Tr.tr("Allow %1 to connect?").arg(win.device);
                                case BluetoothAgent.PinCode:
                                    return Tr.tr("PIN for %1").arg(win.device);
                                case BluetoothAgent.Passkey:
                                    return Tr.tr("Code shown on %1").arg(win.device);
                                case BluetoothAgent.DisplayPinCode:
                                case BluetoothAgent.DisplayPasskey:
                                    return Tr.tr("Type this code on %1").arg(win.device);
                                default:
                                    return Tr.tr("Pair with %1?").arg(win.device);
                                }
                            }
                            font: Tokens.font.title.builders.large.weight(Font.Normal).build()
                            wrapMode: Text.Wrap
                        }
                    }

                    // The code to compare, or to type on the device (the digits typed so far
                    // stand out)
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: BluetoothAgent.code !== ""
                        textFormat: Text.StyledText
                        text: {
                            const code = BluetoothAgent.code;
                            const typed = BluetoothAgent.kind === BluetoothAgent.DisplayPasskey ? Math.min(BluetoothAgent.entered, code.length) : 0;
                            if (typed === 0)
                                return code;
                            return `<font color="${Colours.palette.m3primary}">${code.slice(0, typed)}</font>${code.slice(typed)}`;
                        }
                        font: Tokens.font.mono.builders.large.scale(2).weight(Font.Medium).build()
                    }

                    StyledTextField {
                        id: field

                        Layout.fillWidth: true
                        visible: root.typing
                        leadingIcon: "password"
                        placeholderText: BluetoothAgent.kind === BluetoothAgent.Passkey ? Tr.tr("Code") : Tr.tr("PIN")
                        inputMethodHints: BluetoothAgent.kind === BluetoothAgent.Passkey ? Qt.ImhDigitsOnly : Qt.ImhNone
                        validator: RegularExpressionValidator {
                            regularExpression: BluetoothAgent.kind === BluetoothAgent.Passkey ? /[0-9]{0,6}/ : /.{0,16}/
                        }

                        onAccepted: dialog.confirm()
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Tokens.spacing.extraSmall

                        TextButton {
                            type: TextButton.Text
                            isRound: true
                            horizontalPadding: Tokens.padding.largeIncreased
                            verticalPadding: Tokens.padding.medium
                            text: BluetoothAgent.kind === BluetoothAgent.AuthorizeService ? Tr.trCtx("Deny", "button") : Tr.trCtx("Cancel", "button")
                            onClicked: BluetoothAgent.reject()
                        }

                        TextButton {
                            type: TextButton.Text
                            isRound: true
                            visible: !root.displaying
                            horizontalPadding: Tokens.padding.largeIncreased
                            verticalPadding: Tokens.padding.medium
                            disabled: root.typing && field.text.length === 0
                            text: BluetoothAgent.kind === BluetoothAgent.AuthorizeService ? Tr.trCtx("Allow", "button") : Tr.trCtx("Pair", "button")
                            onClicked: dialog.confirm()
                        }
                    }
                }
            }
        }
    }
}
