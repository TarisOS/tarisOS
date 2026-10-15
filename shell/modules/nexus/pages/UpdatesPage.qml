// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// System updates (Updates): the pending packages, the first few of them, the rest in the full list
// (UpdatesListPage, sub-page 1 here and in General)
PageBase {
    id: root

    readonly property int shown: 5

    title: Tr.tr("Updates")

    Component.onCompleted: Updates.check()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Updates.checking ? Tr.tr("Checking for updates…") : Updates.pending.length === 0 ? Tr.tr("Everything is up to date") : Tr.tr("%1 updates available").arg(Updates.pending.length)
        }

        UpdateButtons {}

        Repeater {
            model: Updates.pending.slice(0, root.shown)

            InfoRow {
                required property string modelData
                required property int index

                first: index === 0
                last: index === Math.min(Updates.pending.length, root.shown) - 1 && Updates.pending.length <= root.shown
                label: modelData.split(" ")[0]
                value: modelData.split(" ").slice(1).join(" ")
            }
        }

        NavRow {
            visible: Updates.pending.length > root.shown
            last: true
            text: Tr.tr("View all")
            onClicked: root.nState.openSubPage(1) // UpdatesListPage
        }
    }
}
