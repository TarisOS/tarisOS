// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import Taris.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.kdeconnect

// KDE Connect's devices, paired ones first, styled like the App Store's and the Settings sidebar
ColumnLayout {
    id: root

    required property ConnectState cState
    property KdeConnectDevice current: null

    spacing: Tokens.spacing.large

    RowLayout {
        Layout.fillWidth: true
        // Over the list, which reaches up under it (its negative top margin): scrolled, its rows
        // would otherwise take the clicks meant for the refresh button
        z: 1
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("KDE Connect")
                font: Tokens.font.title.large
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: KdeConnect.name.length > 0
                text: KdeConnect.name
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }

        IconButton {
            icon: "refresh"
            font: Tokens.font.icon.medium
            type: IconButton.Tonal
            isRound: true
            inactiveColour: Colours.tPalette.m3surfaceContainerHigh
            inactiveOnColour: Colours.palette.m3onSurfaceVariant
            onClicked: {
                KdeConnect.rescan();
                KdeConnect.refresh();
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: KdeConnect.devices.length === 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        text: KdeConnect.available ? Tr.tr("No devices") : Tr.tr("KDE Connect isn't running")
        color: Colours.palette.m3outline
        font: Tokens.font.body.medium
    }

    VerticalFadeFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: -topMargin
        Layout.bottomMargin: -bottomMargin
        visible: KdeConnect.devices.length > 0
        topMargin: Tokens.padding.large
        bottomMargin: Tokens.padding.large
        contentHeight: content.implicitHeight

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: KdeConnect.devices

                StyledRect {
                    id: item

                    required property KdeConnectDevice modelData
                    required property int index

                    readonly property bool isCurrent: modelData === root.current
                    // Paired devices, then the others nearby: a group each
                    readonly property bool isGroupStart: index === 0 || KdeConnect.devices[index - 1].paired !== modelData.paired
                    readonly property bool isGroupEnd: index === KdeConnect.devices.length - 1 || KdeConnect.devices[index + 1].paired !== modelData.paired

                    Layout.fillWidth: true
                    Layout.topMargin: index !== 0 && isGroupStart ? Tokens.spacing.medium : 0
                    implicitHeight: {
                        const h = layout.implicitHeight + layout.anchors.margins * 2;
                        return h % 2 === 0 ? h : h + 1;
                    }

                    color: isCurrent ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                    topLeftRadius: stateLayer.pressed ? Tokens.rounding.medium : isCurrent ? Tokens.rounding.extraLargeIncreased : isGroupStart ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: stateLayer.pressed ? Tokens.rounding.medium : isCurrent ? Tokens.rounding.extraLargeIncreased : isGroupEnd ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
                    bottomRightRadius: bottomLeftRadius

                    RadiusBehavior on topLeftRadius {}
                    RadiusBehavior on bottomLeftRadius {}

                    StateLayer {
                        id: stateLayer

                        anchors.fill: parent
                        topLeftRadius: parent.topLeftRadius
                        topRightRadius: parent.topRightRadius
                        bottomLeftRadius: parent.bottomLeftRadius
                        bottomRightRadius: parent.bottomRightRadius
                        onClicked: root.cState.deviceId = item.modelData.id
                    }

                    RowLayout {
                        id: layout

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        anchors.leftMargin: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        StyledRect {
                            implicitWidth: implicitHeight
                            implicitHeight: icon.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: item.isCurrent ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer
                            opacity: item.modelData.reachable ? 1 : 0.5

                            MaterialIcon {
                                id: icon

                                anchors.centerIn: parent
                                text: DeviceTypes.iconFor(item.modelData.type)
                                color: item.isCurrent ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                                fill: 1
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: item.modelData.name
                                font: Tokens.font.body.medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const d = item.modelData;
                                    if (d.pairRequestedByPeer)
                                        return Tr.tr("Wants to pair");
                                    if (!d.paired)
                                        return d.reachable ? Tr.tr("Not paired") : Tr.tr("Not nearby");
                                    if (!d.reachable)
                                        return Tr.tr("Not connected");
                                    return d.hasBattery && d.charge >= 0 ? Tr.tr("Connected · %1%").arg(d.charge) : Tr.tr("Connected");
                                }
                                color: item.modelData.pairRequestedByPeer ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    component RadiusBehavior: Behavior {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
