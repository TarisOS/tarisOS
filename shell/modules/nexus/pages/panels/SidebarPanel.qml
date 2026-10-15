// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components.controls
import qs.modules.nexus.common

// The notifications sidebar: how hard the pointer has to push into the top-right corner to open it
// (modules/drawers/Interactions.qml), and what a click on a notification does, in the sidebar and
// as a pop-up
PageBase {
    id: root

    // In the order of notifs.clickAction's values
    readonly property list<string> clickActions: ["open", "dismiss", "expand"]
    readonly property list<MenuItem> clickItems: [
        MenuItem {
            text: Tr.tr("Open the app")
        },
        MenuItem {
            text: Tr.tr("Dismiss the notification")
        },
        MenuItem {
            text: Tr.tr("Expand the details")
        }
    ]

    title: Tr.tr("Notifications")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            visible: Config.sidebar.showOnHover
            text: Tr.tr("General")
        }

        SliderRow {
            first: true
            last: true
            visible: Config.sidebar.showOnHover
            icon: "north_east"
            label: Tr.tr("Push Force")
            valueLabel: Config.sidebar.pushTime
            value: Config.sidebar.pushTime / 200
            onMoved: v => GlobalConfig.sidebar.pushTime = Math.round(v * 40) * 5
        }

        // Notifications
        SectionHeader {
            first: !Config.sidebar.showOnHover
            text: Tr.tr("Notifications")
        }

        SelectRow {
            first: true
            last: true
            label: Tr.tr("Clicking a notification")
            menuItems: root.clickItems
            active: root.clickItems[root.clickActions.indexOf(GlobalConfig.notifs.clickAction)] ?? root.clickItems[0]
            onSelected: item => GlobalConfig.notifs.clickAction = root.clickActions[root.clickItems.indexOf(item)]
        }
    }
}
