// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.utils

// App drawer: apps as a grid of icons, filtered by the search text. Drag one to the dock to pin it.
// Right click for its menu, as in the Witcher's Tweaks app drawer: Open, Keep in Dock, Open at
// Login and Remove… (asks first, then uninstalls it: Installer.remove).
GridView {
    id: root

    required property var search
    required property ScreenState screenState
    readonly property int columns: 6
    readonly property int rows: Math.min(4, Math.ceil(count / columns))
    // The open menu's rows: { label, icon, action }
    property var menuRows: []
    // The app was picked with the arrow keys: its whole name shows when it's cut short, until the
    // pointer goes over the apps or the search changes
    property bool keyboardPicked

    function launch(entry: DesktopEntry): void {
        Apps.launch(entry);
        root.screenState.launcher = false;
    }

    function openMenu(cell: Item, entry: DesktopEntry): void {
        const pinned = Dock.isPinned(entry.id);
        const atLogin = Dock.opensAtLogin(entry);
        menuRows = [
            {
                label: Tr.tr("Open"),
                icon: "open_in_new",
                action: () => root.launch(entry)
            },
            {
                label: Tr.tr("Keep in Dock"),
                icon: pinned ? "check_box" : "check_box_outline_blank",
                action: () => Dock.togglePin(entry.id)
            },
            {
                label: Tr.tr("Open at Login"),
                icon: atLogin ? "check_box" : "check_box_outline_blank",
                action: () => Dock.setOpensAtLogin(entry, !atLogin)
            },
            {
                label: Tr.tr("Remove…"),
                icon: "delete",
                // Once this menu has closed, it opens again to ask
                action: () => Qt.callLater(() => root.askRemove(entry))
            }
        ];
        Dock.refreshAutostart();

        // Opens over the grid, towards its middle, so it stays on the drawer
        const p = cell.mapToItem(root, 0, 0);
        const left = p.x + cell.width / 2 < root.width / 2;
        const down = p.y + cell.height / 2 < root.height / 2;
        appMenu.attachTo = cell;
        appMenu.attachSideX = left ? Menu.Left : Menu.Right;
        appMenu.thisSideX = appMenu.attachSideX;
        appMenu.attachSideY = down ? Menu.Bottom : Menu.Top;
        appMenu.thisSideY = down ? Menu.Top : Menu.Bottom;
        appMenu.expanded = true;
    }

    function askRemove(entry: DesktopEntry): void {
        menuRows = [
            {
                label: Tr.tr("Remove %1").arg(entry.name),
                icon: "delete_forever",
                action: () => {
                    // A stand-in is only hidden: uninstalling its entry would remove taris-desktop
                    if (OnDemand.isPlaceholder(entry)) {
                        Dock.removeStandIn(entry);
                    } else {
                        Installer.remove(entry);
                        root.screenState.launcher = false;
                    }
                }
            },
            {
                label: Tr.tr("Cancel"),
                icon: "close",
                action: () => {}
            }
        ];
        appMenu.expanded = true;
    }

    model: ScriptModel {
        values: Apps.search(root.search.text)
        onValuesChanged: {
            root.currentIndex = 0;
            root.keyboardPicked = false;
        }
    }

    clip: true
    cellWidth: width / columns
    cellHeight: Math.round(cellWidth * 1.05)
    implicitHeight: cellHeight * rows
    keyNavigationWraps: true
    highlightFollowsCurrentItem: false
    // Keeps every app's tile around once made (as the settings pages keep their rows), so a glide
    // never stalls building tiles and loading their icons as rows scroll into view
    cacheBuffer: 100000

    highlight: StyledRect {
        radius: Tokens.rounding.large
        color: Colours.palette.m3onSurface
        opacity: 0.08
        x: root.currentItem?.x ?? 0
        y: root.currentItem?.y ?? 0
        implicitWidth: root.cellWidth
        implicitHeight: root.cellHeight

        Behavior on x {
            Anim {}
        }
        Behavior on y {
            Anim {}
        }
    }

    delegate: Item {
        id: app

        required property DesktopEntry modelData
        required property int index

        // An app installed on first use, installing now (its icon fills with colour)
        readonly property bool installing: OnDemandInstaller.isInstalling(modelData.id)
        // An app installed on first use, not installed yet: greyed out, all but its whole name
        readonly property bool greyed: OnDemand.isPlaceholder(modelData) && !installing
        // Its name is cut short and it's pointed at or picked with the arrow keys: the whole name
        // shows over it
        readonly property bool showFullName: name.truncated && (hover.hovered || (GridView.isCurrentItem && root.keyboardPicked))

        implicitWidth: root.cellWidth
        implicitHeight: root.cellHeight
        // Over the tiles beside it, which the whole name can reach into
        z: showFullName ? 1 : 0

        // Dragged to the dock (at the bottom of the drawer) to pin the app there
        AppDragLayer {
            entry: app.modelData
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            radius: Tokens.rounding.large
            opacity: app.greyed ? 0.5 : 1
            onActivated: event => {
                if (event.button === Qt.RightButton)
                    root.openMenu(app, app.modelData);
                else
                    root.launch(app.modelData);
            }
        }

        IconImage {
            id: icon

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Tokens.padding.medium
            implicitSize: Math.round(root.cellWidth * 0.5)
            source: Quickshell.iconPath(app.modelData.icon, "image-missing")
            opacity: app.installing || app.greyed ? 0.5 : 1
        }

        IconFill {
            anchors.fill: icon
            visible: app.installing
            source: icon.source
            progress: OnDemandInstaller.current === app.modelData.id ? OnDemandInstaller.progress : 0
        }

        StyledText {
            id: name

            anchors.top: icon.bottom
            anchors.topMargin: Tokens.spacing.small
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Tokens.padding.small
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: app.modelData.name
            font: Tokens.font.label.medium
            opacity: app.greyed ? 0.5 : 1
        }

        // The whole name, centred on the cut one and kept inside the grid
        StyledRect {
            x: Math.max(-app.x, Math.min(root.width - app.x - width, (app.width - width) / 2))
            y: name.y + (name.height - height) / 2
            implicitWidth: fullName.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: fullName.implicitHeight + Tokens.padding.small * 2
            visible: opacity > 0
            opacity: app.showFullName ? 1 : 0
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHighest

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            StyledText {
                id: fullName

                anchors.centerIn: parent
                text: app.modelData.name
                font: name.font
            }
        }

        HoverHandler {
            id: hover

            onHoveredChanged: {
                if (hovered)
                    root.keyboardPicked = false;
            }
        }
    }

    Variants {
        id: menuItems

        model: root.menuRows

        MenuItem {
            required property var modelData

            text: modelData.label
            icon: modelData.icon
            onClicked: modelData.action()
        }
    }

    Menu {
        id: appMenu

        attachTo: root
        items: menuItems.instances
        active: null
    }

    // Kept between openings (the launcher is): each opens at the top with the first app picked, as
    // a new one did, and a menu left open closes with the launcher
    Connections {
        function onLauncherChanged(): void {
            if (root.screenState.launcher) {
                root.currentIndex = 0;
                root.keyboardPicked = false;
                root.positionViewAtBeginning();
            } else {
                appMenu.expanded = false;
            }
        }

        target: root.screenState
    }

    // Momentum scrolling for wheels and touchpads
    Glide {
        flickable: root
    }
}
