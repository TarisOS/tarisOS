// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Taris
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge
    // The search at the top, the apps under it, and the dock (panels.dock, its own panel drawn over
    // this one) in the room left at the bottom, so the drawer opens around it
    readonly property real dockRoom: Dock.enabled ? panels.dock.nonAnimHeight : CUtils.clamp(padding - Config.border.thickness, 0, padding)

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: search.height + search.anchors.topMargin + listWrapper.height + dockRoom

    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: search.bottom

        ContentList {
            id: list

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 2 - root.dockRoom
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: Tr.tr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

        onAccepted: {
            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    if (Colours.scheme === "dynamic" && !Wallpapers.isCurrent(currentItem.modelData.path))
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        // In the app grid the arrows move through the apps (left and right wrap to the next or
        // previous row), and the picked app's whole name shows when it's cut short; elsewhere up and
        // down move through the list, left and right in the text
        Keys.onUpPressed: {
            if (list.showGrid) {
                const grid = list.currentList;
                if (grid) {
                    grid.moveCurrentIndexUp();
                    grid.keyboardPicked = true;
                }
            } else {
                list.currentList?.decrementCurrentIndex();
            }
        }
        Keys.onDownPressed: {
            if (list.showGrid) {
                const grid = list.currentList;
                if (grid) {
                    grid.moveCurrentIndexDown();
                    grid.keyboardPicked = true;
                }
            } else {
                list.currentList?.incrementCurrentIndex();
            }
        }
        Keys.onLeftPressed: event => {
            if (list.showGrid) {
                const grid = list.currentList;
                if (grid) {
                    grid.moveCurrentIndexLeft();
                    grid.keyboardPicked = true;
                }
            } else {
                event.accepted = false;
            }
        }
        Keys.onRightPressed: event => {
            if (list.showGrid) {
                const grid = list.currentList;
                if (grid) {
                    grid.moveCurrentIndexRight();
                    grid.keyboardPicked = true;
                }
            } else {
                event.accepted = false;
            }
        }

        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: forceActiveFocus()

        Connections {
            // The search is kept between openings (Wrapper): typed in again at each one, empty after
            function onLauncherChanged(): void {
                if (root.screenState.launcher)
                    search.forceActiveFocus();
                else
                    search.text = "";
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
