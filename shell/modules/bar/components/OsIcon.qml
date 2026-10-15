// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Taris.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.store

// The taskbar's launcher button: the logo (Taris's or the distro's), or a Material symbol when
// general.logo is "symbol:<name>"; general.logoAction picks what it opens (Settings > Panels > Taskbar)
Item {
    id: root

    readonly property string symbol: (GlobalConfig.general.logo ?? "").startsWith("symbol:") ? GlobalConfig.general.logo.slice(7) : ""

    function toggleLauncher(): void {
        const screenState = ShellState.forActive();
        screenState.launcher = !screenState.launcher;
    }

    function activate(): void {
        const action = GlobalConfig.general.logoAction;
        if (action === "launcher") {
            toggleLauncher();
        } else if (action === "store") {
            StoreWindow.open();
        } else if (action === "terminal") {
            Quickshell.execDetached(GlobalConfig.general.apps.terminal);
        } else if (action === "files") {
            Quickshell.execDetached(GlobalConfig.general.apps.explorer);
        } else if (action === "overview") {
            Dock.showAllWindows();
        } else if (action.startsWith("app:")) {
            // An app that has since been removed: Settings, as by default, instead of nothing
            const entry = DesktopEntries.byId(action.slice(4));
            if (entry)
                Dock.launch(entry);
            else
                WindowFactory.open("");
        } else {
            WindowFactory.open("");
        }
    }

    implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.2)
    implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.2)

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
    }

    Loader {
        asynchronous: true
        anchors.centerIn: parent
        sourceComponent: root.symbol ? symbolIcon : SysInfo.isDefaultLogo ? tarisLogo : distroIcon
    }

    Component {
        id: symbolIcon

        MaterialIcon {
            text: root.symbol
            color: Colours.palette.m3tertiary
            fontStyle: Tokens.font.icon.medium
        }
    }

    Component {
        id: tarisLogo

        Logo {
            implicitWidth: Math.round(Tokens.font.body.large.pointSize * 1.6)
            implicitHeight: Math.round(Tokens.font.body.large.pointSize * 1.6)
        }
    }

    Component {
        id: distroIcon

        ColouredIcon {
            source: SysInfo.osLogo
            implicitSize: Math.round(Tokens.font.body.large.pointSize * 1.2)
            colour: Colours.palette.m3tertiary
        }
    }
}
