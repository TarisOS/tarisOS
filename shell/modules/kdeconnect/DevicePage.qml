// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris
import Taris.Config
import Taris.I18n
import Taris.Services
import qs.components
import qs.components.containers
import qs.services
import qs.modules.kdeconnect
import qs.modules.nexus.common

// A KDE Connect device: what it is and its battery, then pairing it, or what can be done with it
// once paired (each when its plugin runs and the device is connected)
Item {
    id: root

    property KdeConnectDevice device: null

    readonly property bool usable: device?.paired && device?.reachable

    function has(plugin: string): bool {
        return usable && (device?.plugins.includes(plugin) ?? false);
    }

    Connections {
        // Its files, mounted: opened in the file manager
        function onMounted(path: string): void {
            Quickshell.execDetached([...GlobalConfig.general.apps.explorer, path]);
        }

        function onBrowseFailed(error: string): void {
            Toaster.toast(Tr.tr("Couldn't open the files"), error, "folder_off", Toast.Error);
        }

        target: root.device
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.device
        text: Tr.tr("No device")
        color: Colours.palette.m3outline
        font: Tokens.font.body.medium
    }

    VerticalFadeFlickable {
        anchors.fill: parent
        visible: !!root.device
        contentHeight: column.implicitHeight

        ColumnLayout {
            id: column

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.extraSmall / 2

            // The device
            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: hero.implicitHeight + Tokens.padding.extraLarge * 2

                RowLayout {
                    id: hero

                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.largeIncreased * 2
                    spacing: Tokens.spacing.large

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: typeIcon.implicitHeight + Tokens.padding.large * 2
                        radius: Tokens.rounding.full
                        color: root.usable ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest

                        MaterialIcon {
                            id: typeIcon

                            anchors.centerIn: parent
                            text: DeviceTypes.iconFor(root.device?.type ?? "")
                            color: root.usable ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.large
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.device?.name ?? ""
                            font: Tokens.font.headline.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const d = root.device;
                                if (!d)
                                    return "";
                                if (!d.reachable)
                                    return d.paired ? Tr.tr("Not connected") : Tr.tr("Not nearby");
                                return d.paired ? Tr.tr("Connected") : Tr.tr("Not paired");
                            }
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.medium
                            elide: Text.ElideRight
                        }
                    }

                    // Its battery
                    RowLayout {
                        visible: root.usable && (root.device?.hasBattery ?? false) && (root.device?.charge ?? -1) >= 0
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: root.device?.charging ? "battery_android_bolt" : "battery_android_full"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                        }

                        StyledText {
                            text: `${root.device?.charge ?? 0}%`
                            font: Tokens.font.title.medium
                        }
                    }
                }
            }

            // Pairing: asked for by the device, asked for from here, or not yet
            SectionHeader {
                visible: !(root.device?.paired ?? true)
                text: Tr.tr("Pairing")
            }

            ConnectedRect {
                Layout.fillWidth: true
                visible: (root.device?.pairRequestedByPeer || root.device?.pairRequested) ?? false
                first: true
                implicitHeight: keyLayout.implicitHeight + Tokens.padding.large * 2

                ColumnLayout {
                    id: keyLayout

                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.largeIncreased * 2
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Code")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.device?.verificationKey ?? ""
                        font: Tokens.font.mono.large
                        wrapMode: Text.Wrap
                    }
                }
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device?.pairRequestedByPeer ?? false
                icon: "check"
                text: Tr.tr("Accept")
                onClicked: root.device.acceptPairing()
            }

            RowButton {
                Layout.fillWidth: true
                visible: (root.device?.pairRequestedByPeer || root.device?.pairRequested) ?? false
                last: true
                icon: "close"
                text: root.device?.pairRequestedByPeer ? Tr.tr("Reject") : Tr.tr("Cancel")
                onClicked: root.device.cancelPairing()
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device && !root.device.paired && !root.device.pairRequested && !root.device.pairRequestedByPeer
                first: true
                last: true
                icon: "link"
                text: Tr.tr("Pair")
                disabled: !(root.device?.reachable ?? false)
                onClicked: root.device.requestPairing()
            }

            // Once paired
            SectionHeader {
                visible: root.device?.paired ?? false
                text: Tr.tr("Actions")
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device?.paired ?? false
                first: true
                icon: "upload_file"
                text: Tr.tr("Send a file")
                disabled: !root.has("kdeconnect_share")
                onClicked: ConnectWindow.sendFiles(root.device)
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device?.paired ?? false
                icon: "folder_open"
                text: Tr.tr("Browse files")
                subtext: root.device?.mounting ? Tr.tr("Connecting…") : ""
                disabled: !root.has("kdeconnect_sftp") || (root.device?.mounting ?? false)
                onClicked: root.device.browse()
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device?.paired ?? false
                icon: "content_paste_go"
                text: Tr.tr("Send the clipboard")
                disabled: !root.has("kdeconnect_clipboard")
                onClicked: root.device.sendClipboard()
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device?.paired ?? false
                icon: "ring_volume"
                text: Tr.tr("Ring")
                disabled: !root.has("kdeconnect_findmyphone")
                onClicked: root.device.ring()
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device?.paired ?? false
                last: true
                icon: "notifications_active"
                text: Tr.tr("Ping")
                disabled: !root.has("kdeconnect_ping")
                onClicked: root.device.ping()
            }

            SectionHeader {
                visible: root.device?.paired ?? false
                text: Tr.tr("Device")
            }

            RowButton {
                Layout.fillWidth: true
                visible: root.device?.paired ?? false
                first: true
                last: true
                icon: "link_off"
                text: Tr.tr("Unpair")
                onClicked: root.device.unpair()
            }
        }
    }
}
