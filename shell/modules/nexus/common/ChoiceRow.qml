// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.drawers
import qs.modules.nexus.common

// A setting picked from a list, the way the Witcher's Tweaks settings change it (instead of a
// text field or a stepper): the label on the left, the current choice on the right, and clicking
// opens the choices (with a search field when there are many).
// options: [{ value, label, sublabel? }]; emits chosen(value).
ConnectedRect {
    id: root

    property alias icon: icon.text
    property alias label: label.text
    property string subtext
    property var options: []
    property var current
    property string placeholder: Tr.tr("Choose…")
    property bool searchable: options.length > 12
    property bool busy
    property string query

    readonly property var currentOption: options.find(o => o.value === current) ?? null
    readonly property var shownOptions: query ? options.filter(o => `${o.label} ${o.sublabel ?? ""}`.toLowerCase().includes(query.toLowerCase())) : options
    readonly property alias popup: popup

    // The settings page this sits on, for the room the list has below the row
    readonly property Item page: {
        let p = parent;
        while (p && !(p.flickable && p.nState !== undefined && !p.embedded)) // An embedded page doesn't scroll: the one it's in
            p = p.parent;
        return p;
    }
    readonly property real popupHeight: page ? page.flickable.height - mapToItem(page.flickable.contentItem, 0, 0).y + page.flickable.contentY - Tokens.padding.large - Tokens.padding.extraExtraLarge : Tokens.sizes.nexus.maxPopupHeight

    // Kept inside the row while the page (or the page container) is still animating in: placed in
    // the window then, it would be measured mid-animation and stay there (as PopupRow rows do)
    readonly property bool keepPopupAsChild: {
        if (!page || page.nState.animatingContainer || page.opacity < 1)
            return true;
        let p = page.parent;
        while (p && p.objectName !== "PageContainer")
            p = p.parent;
        return p?.opacity < 1;
    }
    // Bumped when the list opens, so its place is measured again then
    property int reposition
    // Room above the row inside the page's visible part: the list moved up to fit below never
    // goes past the settings' top edge
    readonly property real roomAbove: {
        tWatcher.transform;
        root.reposition;
        page?.flickable.contentY;
        if (!page)
            return Tokens.padding.large;
        return mapToItem(page.flickable, 0, 0).y - Tokens.padding.large;
    }

    signal chosen(value: var)

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2

    // The page scrolled the row out of view (even partly): the list closes, rather than following
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
        id: rowLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: icon

            visible: !!text
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
                Layout.fillWidth: true
                visible: !!root.subtext
                text: root.subtext
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        CircularIndicator {
            visible: root.busy
            implicitSize: Tokens.font.body.medium.pointSize * 2
            running: root.busy
        }

        StyledText {
            Layout.maximumWidth: root.width * 0.45
            text: root.currentOption?.label ?? root.placeholder
            color: root.currentOption ? Colours.palette.m3onSurface : Colours.palette.m3outline
            font: Tokens.font.body.small
            elide: Text.ElideRight
            animate: true
        }

        Item {
            id: triggerArea

            implicitWidth: popup.implicitWidth
            implicitHeight: popup.implicitHeight

            TransformWatcher {
                id: tWatcher

                a: root.parent ? area.parent : null
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
                    return contentWin ? contentWin.interactionWrapper : (win as QsWindow)?.contentItem ?? triggerArea;
                }
                anchors.fill: parent
                // Placed in the window, it would stay on screen when the row is hidden (Mirror
                // with one display, Remove an input source with one layout)
                visible: root.visible
                enabled: popup.open
                hoverEnabled: popup.open
                cursorShape: popup.open ? Qt.ArrowCursor : undefined
                z: popup.animDriver > 0 ? 1 : 0

                onClicked: popup.open = false

                BlobPopup {
                    id: popup

                    // The row's own place and the page's scroll too: a row a Repeater makes is
                    // moved into place after the watcher has looked
                    x: {
                        tWatcher.transform;
                        root.x;
                        root.y;
                        root.width;
                        root.page?.flickable.contentY;
                        root.reposition;
                        return triggerArea.mapToItem(area.parent, 0, 0).x;
                    }
                    y: {
                        tWatcher.transform;
                        root.x;
                        root.y;
                        root.width;
                        root.page?.flickable.contentY;
                        root.reposition;
                        return triggerArea.mapToItem(area.parent, 0, 0).y;
                    }
                    icon: "unfold_more"
                    padding: Tokens.padding.small
                    topMovement: Math.max(0, Math.min(Math.max(Tokens.sizes.nexus.minPopupHeight - root.popupHeight, Tokens.padding.large), root.roomAbove))
                    pressOverride: stateLayer.pressed
                    hoverOverride: stateLayer.containsMouse
                    color: open || hovered || stateLayer.containsMouse ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest
                    onOpenChanged: {
                        if (open)
                            root.reposition++;
                        else
                            root.query = "";
                    }

                    Loader {
                        active: popup.animDriver > 0

                        sourceComponent: ColumnLayout {
                            spacing: Tokens.spacing.small

                            StyledTextField {
                                Layout.fillWidth: true
                                visible: root.searchable
                                leadingIcon: "search"
                                verticalPadding: Tokens.padding.small
                                placeholderText: Tr.tr("Search")
                                onTextChanged: root.query = text
                            }

                            VerticalFadeListView {
                                id: list

                                implicitWidth: Tokens.sizes.nexus.popupWidth
                                implicitHeight: CUtils.clamp(Math.min(root.popupHeight, contentHeight), Math.min(Tokens.sizes.nexus.minPopupHeight, contentHeight), Tokens.sizes.nexus.maxPopupHeight)

                                model: root.shownOptions

                                delegate: StateLayer {
                                    id: item

                                    required property var modelData
                                    readonly property bool selected: modelData.value === root.current

                                    anchors.fill: undefined
                                    anchors.left: list.contentItem.left
                                    anchors.right: list.contentItem.right
                                    implicitHeight: itemLayout.implicitHeight + itemLayout.anchors.margins * 2
                                    radius: Tokens.rounding.small

                                    onClicked: {
                                        popup.open = false;
                                        if (!selected)
                                            root.chosen(modelData.value);
                                    }

                                    RowLayout {
                                        id: itemLayout

                                        anchors.fill: parent
                                        anchors.margins: Tokens.padding.medium
                                        spacing: Tokens.spacing.medium

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: item.modelData.label
                                                font: Tokens.font.body.small
                                                color: item.selected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                visible: !!item.modelData.sublabel
                                                text: item.modelData.sublabel ?? ""
                                                color: Colours.palette.m3outline
                                                font: Tokens.font.label.small
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MaterialIcon {
                                            visible: item.selected
                                            text: "check"
                                            color: Colours.palette.m3primary
                                            fontStyle: Tokens.font.icon.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
