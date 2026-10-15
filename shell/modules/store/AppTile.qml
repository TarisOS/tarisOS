// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.store

// An app in a Store grid: icon, name, summary, where it's from; click for its page
StyledRect {
    id: root

    required property var modelData
    required property StoreState sState

    readonly property var job: AppStore.jobs[modelData.key] ?? null
    readonly property bool busy: job?.state === "running"

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    radius: Tokens.rounding.large
    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

    StateLayer {
        radius: root.radius
        onClicked: root.sState.app = root.modelData
    }

    RowLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        AppIcon {
            app: root.modelData
            size: 52
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.modelData.name
                font: Tokens.font.body.large
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.modelData.summary
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }

            SourceChip {
                Layout.topMargin: Tokens.spacing.extraSmall
                source: root.modelData.source
                visible: root.modelData.source !== "native"
            }
        }

        CircularProgress {
            visible: root.busy
            implicitSize: 24
            strokeWidth: 3
            value: root.job?.progress >= 0 ? root.job.progress : 0
        }

        MaterialIcon {
            visible: !root.busy && (!!root.modelData.installed || !!root.modelData.newVersion)
            text: root.modelData.newVersion ? "upgrade" : "check_circle"
            color: Colours.palette.m3primary
            fill: 1
        }
    }
}
