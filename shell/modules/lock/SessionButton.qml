// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Taris.Config
import Taris.Services
import qs.components
import qs.components.controls
import qs.services

// A power button under the password field on the lock screen and the login screen (log out, shut
// down, sleep, stash, restart), running one of Config.session.commands
IconButton {
    id: root

    required property list<string> command
    property real fontScale: 1

    function exec(): void {
        if (command.length === 1 && command[0] === "stash")
            Stash.stash();
        else if (!SessionManager.exec(command))
            Quickshell.execDetached(command);
    }

    inactiveColour: activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
    inactiveOnColour: activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
    radius: pressed ? Tokens.rounding.medium : activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
    padding: Tokens.padding.large * fontScale
    font: Tokens.font.icon.builders.large.scale(fontScale).build()
    onClicked: exec()
}
