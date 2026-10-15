// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Quickshell.Widgets
import Taris.Config
import qs.components
import qs.services

// An app's icon from store.py: a local file, "theme:<name>" from the icon theme, or (AUR packages,
// apps without one) a symbol
Item {
    id: root

    required property var app
    property real size: 48

    readonly property string icon: app?.icon ?? ""
    readonly property bool isTheme: icon.startsWith("theme:")

    implicitWidth: size
    implicitHeight: size

    IconImage {
        anchors.fill: parent
        visible: root.isTheme
        asynchronous: true
        source: root.isTheme ? Quickshell.iconPath(root.icon.slice(6), "application-x-executable") : ""
        implicitSize: root.size
    }

    Image {
        id: img

        anchors.fill: parent
        visible: !root.isTheme && root.icon !== ""
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: visible ? "file://" + root.icon : ""
        sourceSize: {
            const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
            return Qt.size(root.size * dpr, root.size * dpr);
        }
    }

    StyledRect {
        anchors.fill: parent
        visible: root.icon === "" || (!root.isTheme && img.status === Image.Error)
        radius: Tokens.rounding.large
        color: Colours.palette.m3secondaryContainer

        MaterialIcon {
            anchors.centerIn: parent
            text: root.app?.source === "aur" ? "deployed_code" : "apps"
            color: Colours.palette.m3onSecondaryContainer
            fontStyle: root.size > 64 ? Tokens.font.icon.extraLarge : Tokens.font.icon.large
        }
    }
}
