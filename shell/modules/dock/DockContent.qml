// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus

// The dock's row: the apps button and Settings first, then the pinned and running apps, and the
// Trash at the end (Settings > Dock shows or hides those three). Left click focuses (cycling windows) or launches,
// middle click opens a new instance, right click opens the app's menu (as in the Witcher's Tweaks
// dock): its windows, Keep in Dock, Open at Login, Show All Windows, then Open, or New Window, Hide
// and Quit. Apps are dragged left and right to rearrange them, in from the app drawer to pin them,
// and onto the Trash to take them out of the dock.
RowLayout {
    id: root

    required property ScreenState screenState
    // The widest it gets (the app drawer's width): past it the icons get smaller to fit, the dock
    // doesn't get wider
    required property real maxWidth
    // A menu is open from it (the dock stays up while it is)
    property bool held

    // Tiles in the row: the dock's own items and the apps (and room for one dragged in). Each
    // keeps the full height, so the dock's size stays the same: only the icons get smaller.
    readonly property int tileCount: Dock.previewApps.length + (Dock.showTrash ? 1 : 0) + (Dock.settingsApp ? 1 : 0) + (Dock.showAppsButton ? 1 : 0)
    readonly property int fullTileSize: 40 + Tokens.padding.small * 2
    // The divider before the Trash (1 px)
    readonly property int dividers: Dock.showTrash ? 1 : 0
    // A gap between each two things in the row (the apps' own row has the same spacing)
    readonly property int gaps: Math.max(0, tileCount + dividers - 1)
    // Too many icons for full size: the dock is then as wide as it gets, and they share it
    readonly property bool capped: tileCount * fullTileSize + gaps * spacing + dividers > maxWidth
    readonly property int tileSize: capped ? Math.max(16, Math.floor((maxWidth - gaps * spacing - dividers) / Math.max(1, tileCount))) : fullTileSize
    readonly property int iconSize: Math.round(tileSize * 40 / fullTileSize)
    readonly property string trashPath: `${Quickshell.env("XDG_DATA_HOME") || `${Paths.home}/.local/share`}/Trash/files`
    readonly property bool trashFull: trashFiles.count > 0

    // Where an app dragged over this dock would land (Dock.dropIndex, Dock.overTrash)
    function updateDrop(): void {
        const win = QsWindow.window as QsWindow;
        if (!Dock.dragApp || !win || Dock.dragWindow !== win)
            return;

        const t = trashTile.mapFromItem(win.contentItem, Dock.dragPos.x, Dock.dragPos.y);
        const overTrash = trashTile.visible && t.x >= 0 && t.y >= 0 && t.x <= trashTile.width && t.y <= trashTile.height;
        // Only an app the dock keeps can be taken out of it
        Dock.overTrash = overTrash && Dock.pinnedApps.some(e => e.id === Dock.dragApp.id);

        const p = appRow.mapFromItem(win.contentItem, Dock.dragPos.x, Dock.dragPos.y);
        const slack = Tokens.padding.large * 2;
        if (overTrash || p.y < -slack || p.y > appRow.height + slack || p.x < -slack || p.x > root.width + slack) {
            Dock.dropIndex = -1;
            return;
        }
        // Tiles are all the same width, so the slot under the pointer doesn't move as the dock
        // makes room; past the pinned apps it lands at their end
        const slot = Math.floor(p.x / (root.tileSize + appRow.spacing));
        const pins = Dock.pinnedApps.filter(e => e.id !== Dock.dragApp.id).length;
        Dock.dropIndex = Math.max(0, Math.min(slot, pins));
    }

    spacing: Tokens.spacing.small

    Component.onCompleted: updateDrop()
    Component.onDestruction: {
        if (Dock.dragApp && Dock.dragWindow === QsWindow.window) {
            Dock.dropIndex = -1;
            Dock.overTrash = false;
        }
    }

    Connections {
        function onDragPosChanged(): void {
            root.updateDrop();
        }

        function onDragAppChanged(): void {
            root.updateDrop();
        }

        target: Dock
    }

    // The Trash's folder, made first (private to the account, as GIO makes it): the model can't
    // watch a folder that isn't there yet (a new account's), so it never saw the first file trashed,
    // and the Trash showed empty with no Empty Trash in its menu
    Process {
        id: trashDir

        property bool ready

        command: ["sh", "-c", 'umask 077 && mkdir -p "$1"', "sh", root.trashPath]
        running: true
        onExited: ready = true
    }

    FolderListModel {
        id: trashFiles

        folder: trashDir.ready ? `file://${root.trashPath}` : ""
        showDirs: true
        showHidden: true
        showDotAndDotDot: false
    }

    // App drawer (Settings > Dock can hide it)
    Item {
        visible: Dock.showAppsButton
        implicitWidth: root.tileSize
        implicitHeight: root.fullTileSize

        StyledRect {
            id: drawerTile

            anchors.centerIn: parent
            implicitWidth: root.tileSize
            implicitHeight: root.tileSize
            // No highlight of its own, so it doesn't draw attention: just the icon, about as big as
            // the apps' (and shrinking with them)
            radius: Tokens.rounding.large
            color: "transparent"

            StateLayer {
                radius: drawerTile.radius
                onClicked: root.screenState.launcher = !root.screenState.launcher
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "apps"
                fontStyle: Tokens.font.icon.builders.large.size(Math.round(root.iconSize * 0.65)).build()
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    // Settings in its own place (Settings > Dock can hide it)
    Loader {
        active: Dock.settingsApp !== null
        visible: active

        sourceComponent: AppTile {
            modelData: Dock.settingsApp
            index: -1
        }
    }

    RowLayout {
        id: appRow

        spacing: Tokens.spacing.small

        Repeater {
            model: ScriptModel {
                values: Dock.apps
            }

            AppTile {}
        }

        // Room for an app dragged in from the app drawer
        Item {
            visible: Dock.previewApps.length > Dock.apps.length
            implicitWidth: root.tileSize
            implicitHeight: 1
        }
    }

    // Between the apps and the Trash
    StyledRect {
        visible: Dock.showTrash
        Layout.fillHeight: true
        Layout.topMargin: Tokens.padding.medium
        Layout.bottomMargin: Tokens.padding.medium
        implicitWidth: 1
        color: Colours.palette.m3outlineVariant
    }

    // Trash: opens in the file manager, and its menu empties it; an app dropped on it leaves the dock
    Item {
        id: trashItem

        property var menuRows: []

        visible: Dock.showTrash
        implicitWidth: root.tileSize
        implicitHeight: root.fullTileSize

        Variants {
            id: trashMenuItems

            model: trashItem.menuRows

            MenuItem {
                required property var modelData

                text: modelData.label
                icon: modelData.icon
                onClicked: modelData.action()
            }
        }

        Menu {
            id: trashMenu

            attachTo: trashTile
            attachSideX: Menu.Left
            thisSideX: Menu.Left
            attachSideY: Menu.Top
            thisSideY: Menu.Bottom
            marginY: -Tokens.spacing.small
            items: trashMenuItems.instances
            active: null
            onExpandedChanged: root.held = expanded
        }

        StyledRect {
            id: trashTile

            anchors.centerIn: parent
            implicitWidth: root.tileSize
            implicitHeight: root.tileSize
            radius: Tokens.rounding.large
            color: Dock.overTrash ? Colours.palette.m3errorContainer : "transparent"
            scale: Dock.overTrash ? 1.15 : 1

            Behavior on scale {
                Anim {}
            }

            StateLayer {
                id: trashLayer

                acceptedButtons: Qt.LeftButton | Qt.RightButton
                radius: trashTile.radius
                onClicked: event => {
                    if (event.button === Qt.RightButton) {
                        const rows = [
                            {
                                label: Tr.tr("Open"),
                                icon: "open_in_new",
                                action: () => Dock.openTrash()
                            }
                        ];
                        if (root.trashFull)
                            rows.push({
                                label: Tr.tr("Empty Trash"),
                                icon: "delete_forever",
                                action: () => Dock.emptyTrash()
                            });
                        trashItem.menuRows = rows;
                        trashMenu.expanded = true;
                    } else {
                        Dock.openTrash();
                    }
                }
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: root.iconSize
                source: Quickshell.iconPath(root.trashFull ? "user-trash-full" : "user-trash", "user-trash")
                scale: trashLayer.pressed ? 0.85 : 1

                Behavior on scale {
                    Anim {}
                }
            }
        }
    }

    component AppTile: Item {
        id: app

        required property DesktopEntry modelData
        required property int index // -1 for Settings in its own place
        // Steam with its window closed counts as one: it's still running
        readonly property int windows: Dock.windowsFor(modelData).length || (Dock.runsInBackground(modelData) ? 1 : 0)
        readonly property bool active: Dock.entryForToplevel(Hypr.activeToplevel)?.id === modelData.id
        readonly property bool dragged: Dock.dragApp?.id === modelData.id
        // An app installed on first use, installing now
        readonly property bool installing: OnDemandInstaller.isInstalling(modelData.id)
        // Slots this app moves by to make room for an app being dragged: the list itself stays put
        // while dragging (rebuilding it would take the dragged tile, and its drag, away)
        readonly property int shift: {
            const i = Dock.previewApps.indexOf(modelData);
            return index < 0 || i < 0 ? 0 : i - index;
        }

        // The menu's rows: { label, icon, action }
        property var menuRows: []

        function openMenu(): void {
            const entry = modelData;
            const wins = Dock.windowsFor(entry);
            const rows = wins.slice(0, 8).map(w => ({
                        label: w.title || entry.name,
                        icon: w === Hypr.activeToplevel ? "radio_button_checked" : Dock.isMinimized(w) ? "minimize" : "web_asset",
                        action: () => Dock.focusWindow(w)
                    }));
            const pinned = Dock.isPinned(entry.id);
            if (index >= 0)
                rows.push({
                    label: Tr.tr("Keep in Dock"),
                    icon: pinned ? "check_box" : "check_box_outline_blank",
                    action: () => Dock.togglePin(entry.id)
                });
            const atLogin = Dock.opensAtLogin(entry);
            rows.push({
                label: Tr.tr("Open at Login"),
                icon: atLogin ? "check_box" : "check_box_outline_blank",
                action: () => Dock.setOpensAtLogin(entry, !atLogin)
            });
            if (wins.length > 0)
                rows.push({
                    label: Tr.tr("Show All Windows"),
                    icon: "view_quilt",
                    action: () => Dock.showAllWindows()
                });
            if (wins.length === 0 && Dock.runsInBackground(entry)) {
                rows.push({
                    label: Tr.tr("Open"),
                    icon: "open_in_new",
                    action: () => Dock.activate(entry)
                });
                rows.push({
                    label: Tr.tr("Quit"),
                    icon: "close",
                    action: () => Dock.closeAll(entry)
                });
            } else if (wins.length === 0) {
                rows.push({
                    label: Tr.tr("Open"),
                    icon: "open_in_new",
                    action: () => Dock.launch(entry)
                });
                if (OnDemand.isPlaceholder(entry))
                    rows.push({
                        label: Tr.tr("Remove"),
                        icon: "delete",
                        action: () => Dock.removeStandIn(entry)
                    });
            } else {
                rows.push({
                    label: Tr.tr("New Window"),
                    icon: "add",
                    action: () => Dock.launch(entry)
                });
                rows.push({
                    label: Tr.tr("Hide"),
                    icon: "visibility_off",
                    action: () => Dock.minimizeAll(entry)
                });
                rows.push({
                    label: Tr.tr("Quit"),
                    icon: "close",
                    action: () => Dock.closeAll(entry)
                });
            }
            Dock.refreshAutostart();
            menuRows = rows;
            appMenu.expanded = true;
        }

        implicitWidth: root.tileSize
        implicitHeight: root.fullTileSize
        // The dragged app's place (the app itself follows the pointer); an app installed on first
        // use, greyed out until it is (while it installs, its icon fills with colour instead)
        opacity: dragged ? 0.35 : OnDemand.isPlaceholder(modelData) && !installing ? 0.5 : 1
        transform: Translate {
            x: app.shift * (root.tileSize + appRow.spacing)

            Behavior on x {
                Anim {}
            }
        }

        Behavior on opacity {
            Anim {}
        }

        Variants {
            id: menuItems

            model: app.menuRows

            MenuItem {
                required property var modelData

                text: modelData.label
                icon: modelData.icon
                onClicked: modelData.action()
            }
        }

        // Above the app, keeping the dock up while it's open
        Menu {
            id: appMenu

            attachTo: tile
            attachSideX: Menu.Left
            thisSideX: Menu.Left
            attachSideY: Menu.Top
            thisSideY: Menu.Bottom
            marginY: -Tokens.spacing.small
            items: menuItems.instances
            active: null
            onExpandedChanged: root.held = expanded
        }

        StyledRect {
            id: tile

            anchors.centerIn: parent
            implicitWidth: root.tileSize
            implicitHeight: root.tileSize
            radius: Tokens.rounding.large
            color: app.active ? Colours.palette.m3secondaryContainer : "transparent"

            AppDragLayer {
                id: tileLayer

                entry: app.modelData
                draggable: app.index >= 0
                fromDock: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                radius: tile.radius
                onActivated: event => {
                    if (event.button === Qt.RightButton)
                        app.openMenu();
                    else if (event.button === Qt.MiddleButton && OnDemand.isPlaceholder(app.modelData))
                        OnDemandInstaller.install(app.modelData);
                    else if (event.button === Qt.MiddleButton)
                        Quickshell.execDetached({
                            command: [Paths.runApp, ...app.modelData.command],
                            workingDirectory: app.modelData.workingDirectory
                        });
                    else if (app.modelData.id === Dock.settingsId && app.windows === 0)
                        // Settings opens as the overlay over everything (a Settings window popped
                        // out of it is focused like any app's)
                        WindowFactory.open("");
                    else
                        Dock.activate(app.modelData);
                }
            }

            IconImage {
                id: tileIcon

                anchors.centerIn: parent
                implicitSize: root.iconSize
                source: Dock.iconsClearing ? "" : Quickshell.iconPath(app.modelData.icon, "image-missing")
                scale: tileLayer.pressed ? 0.85 : 1
                opacity: app.installing ? 0.5 : 1

                Behavior on scale {
                    Anim {}
                }
            }

            IconFill {
                anchors.fill: tileIcon
                scale: tileIcon.scale
                visible: app.installing
                source: tileIcon.source
                progress: OnDemandInstaller.current === app.modelData.id ? OnDemandInstaller.progress : 0
            }
        }

        // Running indicator under the app: one dot per window, up to three
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            spacing: 2

            Repeater {
                model: Math.min(app.windows, 3)

                StyledRect {
                    implicitWidth: app.active ? 8 : 4
                    implicitHeight: 4
                    radius: 2
                    color: app.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                    Behavior on implicitWidth {
                        Anim {}
                    }
                }
            }
        }
    }
}
