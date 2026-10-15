// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Taris.Config
import Taris.I18n
import Taris.Services
import qs.components
import qs.components.filedialog
import qs.services
import qs.modules.kdeconnect

// KDE Connect as the overlay Settings and the App Store open as (centred over everything on the
// focused screen, closed by clicking away), or as a window: its corner button turns the overlay into
// one, and it's a window when no screen has the shell's panels. It also keeps what outlives a view:
// the device picked, and the file picker sending files (the view goes while the picker is over it).
Singleton {
    id: root

    property string deviceId
    // The device the file picker sends to
    property KdeConnectDevice sendTo: null

    readonly property FileDialog filePicker: FileDialog {
        title: Tr.tr("Send a file")
        onAccepted: path => {
            root.sendTo?.share([path]);
            root.sendTo = null;
        }
        onRejected: root.sendTo = null
    }

    function open(): void {
        const popouts = ShellState.componentsForActive()?.panels?.popouts;
        if (popouts)
            popouts.detach("kdeconnect");
        else
            create();
    }

    function create(): void {
        windowComp.createObject(dummy);
    }

    function sendFiles(device: KdeConnectDevice): void {
        sendTo = device;
        filePicker.open();
    }

    QtObject {
        id: dummy
    }

    Component {
        id: windowComp

        FloatingWindow {
            id: win

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible)
                    destroy();
            }

            implicitWidth: view.implicitWidth
            implicitHeight: view.implicitHeight

            minimumSize.width: contentItem.Tokens.sizes.nexus.minWidth
            minimumSize.height: contentItem.Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: Tr.tr("KDE Connect")

            ConnectView {
                id: view

                anchors.fill: parent
                cState.screen: win.screen
                cState.isWindow: true
                onClose: win.destroy()
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
