// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris.Config
import qs.components
import qs.services
import qs.modules.drawers
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property alias icon: icon.text
    property alias label: label.text
    property alias status: status.text
    property bool keepPopupAsChild
    readonly property alias popup: popup
    default required property Item content

    // The settings page this sits on (as ChoiceRow finds it): the popup stays inside its visible part
    readonly property Item page: {
        let p = parent;
        while (p && !(p.flickable && p.nState !== undefined && !p.embedded)) // An embedded page doesn't scroll: the one it's in
            p = p.parent;
        return p;
    }
    // How far the open popup moves up from the row: enough to end above the page's bottom edge,
    // never past its top one
    readonly property real topMovement: {
        tWatcher.transform;
        popup.open;
        page?.flickable.contentY;
        if (!page)
            return Tokens.padding.large;
        const y = mapToItem(page.flickable, 0, 0).y;
        const height = content.implicitHeight + Tokens.padding.small * 2;
        const below = y + height - (page.flickable.height - Tokens.padding.large);
        return Math.max(0, Math.min(Math.max(below, Tokens.padding.large), y - Tokens.padding.large));
    }

    Layout.fillWidth: true
    implicitHeight: navLayout.implicitHeight + navLayout.anchors.margins * 2

    // The page scrolled the row out of view (even partly): the popup closes, rather than following
    // it past the settings' edge
    Connections {
        function onContentYChanged(): void {
            if (!popup.open)
                return;
            const y = root.mapToItem(root.page.flickable, 0, 0).y;
            if (y < 0 || y + root.height > root.page.flickable.height)
                popup.open = false;
        }

        target: root.page?.flickable ?? null
    }

    StateLayer {
        id: stateLayer

        manualHoverOverride: popup.hovered && !popup.open
        onClicked: popup.open = true
    }

    RowLayout {
        id: navLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: icon

            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                id: status

                Layout.fillWidth: true
                visible: text
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
                animate: true
            }
        }

        Item {
            id: triggerArea

            implicitWidth: popup.implicitWidth
            implicitHeight: popup.implicitHeight

            TransformWatcher {
                id: tWatcher

                a: area.parent
                b: triggerArea
            }

            MouseArea {
                id: area

                parent: {
                    // In the row while closed, so it scrolls, fades and clips with the page (in the
                    // window, a row scrolled out of view would leave its button showing past the
                    // settings' edge); out in the window only while open, to grow over the page
                    if (root.keepPopupAsChild || (!popup.open && popup.animDriver <= 0))
                        return triggerArea;

                    const win = QsWindow.window;
                    const contentWin = win as ContentWindow; // If inside the drawer content window, put it inside the interaction wrapper so hover works
                    return contentWin ? contentWin.interactionWrapper : (win as QsWindow).contentItem;
                }
                anchors.fill: parent
                enabled: popup.open
                hoverEnabled: popup.open
                cursorShape: popup.open ? Qt.ArrowCursor : undefined
                z: popup.animDriver > 0 ? 1 : 0

                onClicked: popup.open = false

                BlobPopup {
                    id: popup

                    x: {
                        tWatcher.transform;
                        return triggerArea.mapToItem(area.parent, 0, 0).x;
                    }
                    y: {
                        tWatcher.transform;
                        return triggerArea.mapToItem(area.parent, 0, 0).y;
                    }
                    padding: Tokens.padding.small
                    topMovement: root.topMovement
                    content: root.content
                    pressOverride: stateLayer.pressed
                    hoverOverride: stateLayer.containsMouse
                    color: open || hovered || stateLayer.containsMouse ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest
                }
            }
        }
    }
}
