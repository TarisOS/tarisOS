// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Taris.Config
import Taris.I18n
import qs.components
import qs.services
import qs.modules.nexus

Singleton {
    id: root

    function create(parent: Item, props: var): void {
        nexusComp.createObject(parent ?? dummy, props);
    }

    // Settings as the overlay a popout's "Open settings" gives: centred over everything on the
    // focused screen, no window frame, closed by clicking away; page is a PageRegistry id (the first
    // page when empty). A window when no screen has the shell's panels (create() is the window).
    function open(page: string): void {
        const popouts = ShellState.componentsForActive()?.panels?.popouts;
        if (popouts)
            popouts.detach(page || PageRegistry.defaultPage);
        else
            create();
    }

    QtObject {
        id: dummy
    }

    Component {
        id: nexusComp

        FloatingWindow {
            id: win

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible)
                    destroy();
            }

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: contentItem.Tokens.sizes.nexus.minWidth
            minimumSize.height: contentItem.Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: Tr.tr("Nexus — %1").arg(PageRegistry.pages[nexus.nState.currentPageIdx].label)

            Nexus {
                id: nexus

                anchors.fill: parent
                nState.screen: win.screen
                nState.isWindow: true
                nState.currentPageIdx: PageRegistry.indexOf(PageRegistry.defaultPage)
                onClose: win.destroy()
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
