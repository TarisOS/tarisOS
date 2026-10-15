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

// All the pending updates (UpdatesPage's View all)
PageBase {
    id: root

    title: Tr.tr("Updates")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        UpdateButtons {}

        SectionHeader {
            first: true
            text: Updates.checking ? Tr.tr("Checking for updates…") : Updates.pending.length === 0 ? Tr.tr("Everything is up to date") : Tr.tr("%1 updates available").arg(Updates.pending.length)
        }

        Repeater {
            model: Updates.pending

            InfoRow {
                required property string modelData
                required property int index

                first: index === 0
                last: index === Updates.pending.length - 1
                label: modelData.split(" ")[0]
                value: modelData.split(" ").slice(1).join(" ")
            }
        }
    }
}
