// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Taris.Blobs
import Taris.Config
import Taris.Services
import qs.components
import qs.components.controls
import qs.services
import qs.modules.kdeconnect

// KDE Connect (the KdeConnect service, kdeconnectd's devices), framed like the App Store: the
// devices on the left, the one picked on the right
Item {
    id: root

    readonly property ConnectState cState: ConnectState {
        onClose: root.close()
    }
    // The device picked, else the first one (paired ones come first)
    readonly property KdeConnectDevice device: {
        const devices = Array.from(KdeConnect.devices);
        return devices.find(d => d.id === cState.deviceId) ?? devices[0] ?? null;
    }

    property color blobColour: Colours.tPalette.m3surfaceContainerLow

    signal close

    // No wider than the screen allows (a rotated one is narrower than it is tall)
    implicitWidth: Math.round(Math.min(implicitHeight * Tokens.sizes.nexus.ratio, (cState.screen?.width ?? 1600) * 0.8))
    implicitHeight: Math.round((cState.screen?.height ?? 900) * Tokens.sizes.nexus.heightMult)

    // Starts kdeconnectd if it isn't running, and asks it what it knows
    Component.onCompleted: KdeConnect.refresh()

    TapHandler {
        onTapped: root.focus = true
    }

    BlobGroup {
        id: blobGroup

        smoothing: root.Tokens.rounding.medium
        color: root.blobColour
    }

    BlobInvertedRect {
        anchors.fill: parent
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.large
        borderLeft: nav.width + nav.anchors.margins * 2
        borderRight: Tokens.padding.medium
        borderTop: Tokens.padding.medium
        borderBottom: Tokens.padding.medium
    }

    BlobRect {
        id: windowBtnRect

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.cState.isWindow ? 0 : Tokens.padding.extraSmall
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.medium
        implicitWidth: windowBtn.implicitWidth + (root.cState.isWindow ? Tokens.padding.extraSmall : Tokens.padding.small) * 2
        implicitHeight: windowBtn.implicitHeight + (root.cState.isWindow ? Tokens.padding.extraSmall : Tokens.padding.small)
    }

    IconButton {
        id: windowBtn

        anchors.centerIn: windowBtnRect
        icon: root.cState.isWindow ? "close" : "pip"
        type: IconButton.Text
        label.fill: 0
        inactiveOnColour: hovered ? root.cState.isWindow ? Colours.palette.m3error : Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        stateLayer.opacity: 0
        onClicked: {
            if (!root.cState.isWindow)
                ConnectWindow.create();
            root.close();
        }
        label.scale: pressed ? 0.8 : 1
        label.renderType: Text.QtRendering

        Behavior on label.scale {
            Anim {}
        }
    }

    DeviceNav {
        id: nav

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large
        cState: root.cState
        current: root.device
        width: Math.min(Tokens.sizes.nexus.maxNavWidth, Math.round(root.width / 3.4))
    }

    DevicePage {
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: nav.anchors.margins + anchors.margins
        anchors.margins: Tokens.padding.extraLarge

        device: root.device
    }
}
