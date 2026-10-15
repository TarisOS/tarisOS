// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.store

// A Store view's frame: its title (and a way back on an app's page), then its content, which
// scrolls; while it loads, or when there's nothing to show, a note instead
ColumnLayout {
    id: root

    required property StoreState sState
    property string title
    property bool canGoBack
    property bool loading
    property bool empty
    property string emptyText
    property string error
    property Item trailing: null // Beside the title
    default property alias content: column.data

    spacing: Tokens.spacing.large

    // Over the content, which reaches up under it (its negative top margin): scrolled, the content
    // would otherwise be on top here and take the clicks meant for the way back (as in Settings)
    MouseArea {
        Layout.fillWidth: true
        z: 1
        implicitHeight: header.implicitHeight

        RowLayout {
            id: header

            anchors.fill: parent
            spacing: Tokens.spacing.medium

            IconButton {
                visible: root.canGoBack
                icon: "arrow_back"
                font: Tokens.font.icon.medium
                type: IconButton.Tonal
                isRound: true
                inactiveColour: Colours.tPalette.m3surfaceContainerHigh
                inactiveOnColour: Colours.palette.m3onSurfaceVariant
                onClicked: root.sState.app = null
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font: Tokens.font.title.large
                elide: Text.ElideRight
            }

            Item {
                implicitWidth: root.trailing?.implicitWidth ?? 0
                implicitHeight: root.trailing?.implicitHeight ?? 0
                children: root.trailing ? [root.trailing] : []
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.empty

        LoadingIndicator {
            anchors.centerIn: parent
            visible: root.loading
            implicitSize: 56
        }

        StyledText {
            anchors.centerIn: parent
            width: parent.width
            visible: !root.loading
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.error || root.emptyText
            color: root.error ? Colours.palette.m3error : Colours.palette.m3outline
            font: Tokens.font.body.medium
        }
    }

    VerticalFadeFlickable {
        id: flickable

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: -topMargin
        visible: !root.empty
        topMargin: Tokens.padding.large
        bottomMargin: Tokens.padding.extraLarge
        contentHeight: column.implicitHeight

        ColumnLayout {
            id: column

            width: flickable.width
            spacing: Tokens.spacing.extraLarge
        }
    }
}
