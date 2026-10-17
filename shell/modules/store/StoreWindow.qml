// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Taris.Config
import Taris.I18n
import qs.components
import qs.services
import qs.modules.store

// The Store as the overlay Settings opens as (centred over everything on the focused screen,
// closed by clicking away), or as a window: its corner button turns the overlay into one, and it's
// a window when no screen has the shell's panels
Singleton {
    id: root

    function open(): void {
        const popouts = ShellState.componentsForActive()?.panels?.popouts;
        if (popouts)
            popouts.detach("store");
        else
            create();
    }

    function create(): void {
        windowComp.createObject(dummy);
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

            implicitWidth: store.implicitWidth
            implicitHeight: store.implicitHeight

            minimumSize.width: contentItem.Tokens.sizes.nexus.minWidth
            minimumSize.height: contentItem.Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: Screens.configOf(screen.name)
            contentItem.Tokens.screen: Screens.configOf(screen.name)

            title: Tr.tr("App Store")

            Store {
                id: store

                anchors.fill: parent
                sState.screen: win.screen
                sState.isWindow: true
                onClose: win.destroy()
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
