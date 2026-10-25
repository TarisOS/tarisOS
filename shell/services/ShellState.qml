// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Taris
import Taris.Config
import qs.components
import qs.services

Singleton {
    property ShellRoot shellRoot
    // A password prompt (modules/polkit) is up: the shell's focus grabs let go meanwhile, so the
    // prompt gets every click and key
    property bool authenticating
    // The screenshot area picker is up (modules/areapicker): the focus grabs let go meanwhile too,
    // or the click that picks the area would count as a click away and close the panel being shot
    property bool picking
    // The keyboard shortcuts are shown (modules/Keybinds.qml): the focus grabs let go meanwhile too,
    // so its window gets the keyboard
    property bool keybinds
    // The emoji picker is up (modules/EmojiPicker.qml): the focus grabs let go meanwhile too
    property bool emojis
    // A Bluetooth question is up (modules/bluetooth): the focus grabs let go meanwhile too, so the
    // prompt gets every click and key
    property bool bluetoothPrompt
    // The shell's focus grabs (modules/drawers, the bar's popouts) are off: while a password is
    // asked for, an area is picked, the keyboard shortcuts or the emoji picker are shown, or
    // Bluetooth asks something
    readonly property bool grabsReleased: authenticating || picking || keybinds || emojis || bluetoothPrompt

    // A disabled sidebar never counts as open (it would silence notification popups for nothing)
    function anySidebarOpen(): bool {
        return GlobalConfig.sidebar.enabled && states.instances.some(s => s.sidebar);
    }

    function forScreen(screen: ShellScreen): ScreenState {
        for (const s of states.instances)
            if (s.modelData === screen)
                return s;
        return null;
    }

    // The focused display's, or the main display's when the focused one has no shell
    function forActive(): ScreenState {
        const mon = Hypr.focusedMonitor;
        for (const s of states.instances)
            if (Hypr.monitorFor(s.modelData) === mon)
                return s;
        return states.instances.find(s => s.modelData.name === Screens.mainName) ?? null;
    }

    function componentsFor(screen: ShellScreen): Components {
        for (const c of components.instances)
            if (c.modelData === screen)
                return c;
        return null;
    }

    // The focused display's, or the main display's when the focused one has no shell
    function componentsForActive(): Components {
        const mon = Hypr.focusedMonitor;
        for (const c of components.instances)
            if (Hypr.monitorFor(c.modelData) === mon)
                return c;
        return components.instances.find(c => c.modelData.name === Screens.mainName) ?? null;
    }

    Variants {
        id: states

        model: Screens.screens

        ScreenState {}
    }

    Variants {
        id: components

        model: Screens.screens

        Components {}
    }

    component Components: QtObject {
        required property ShellScreen modelData

        property var background
        property var rootWindow
        property var interactionWrapper
        property var bar
        property var panels

        function find(name: string, rootItem: Item): var {
            return CUtils.findChild(rootItem ?? rootWindow?.contentItem, name);
        }

        function findAll(name: string, rootItem: Item): var {
            return CUtils.findChildren(rootItem ?? rootWindow?.contentItem, name);
        }

        function findMatching(pattern: string, rootItem: Item): var {
            return CUtils.findChildrenMatching(rootItem ?? rootWindow?.contentItem, pattern);
        }
    }

    component ComponentRef: QtObject {
        required property ShellScreen screen
        required property string slot
        required property var component

        readonly property QtObject target: ShellState.componentsFor(screen)

        onTargetChanged: {
            if (target)
                target[slot] = component;
        }
        Component.onDestruction: {
            if (target && target[slot] === component)
                target[slot] = null;
        }
    }
}
