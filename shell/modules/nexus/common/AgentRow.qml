// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.services
import qs.modules.nexus.common

// The coding agent the dashboard's Agent tab runs: every agent with its logo and whether it's
// installed; picking one that isn't installed installs it (Agents.pick)
PopupRow {
    id: agentRow

    icon: "smart_toy"
    label: Tr.trCtx("Agent", "default app category")
    status: Agents.defaultAgent ? Agents.nameOf(Agents.defaultAgent) : Tr.trCtx("None", "default agent")

    readonly property Item page: {
        let p = parent;
        while (p && !(p.flickable && p.nState !== undefined && !p.embedded)) // An embedded page doesn't scroll: the one it's in
            p = p.parent;
        return p;
    }
    readonly property int popupHeight: page ? page.flickable.height - mapToItem(page.flickable.contentItem, 0, 0).y + page.flickable.contentY - Tokens.padding.large - Tokens.padding.extraExtraLarge : Tokens.sizes.nexus.maxPopupHeight

    keepPopupAsChild: {
        if (!page || page.nState.animatingContainer || page.opacity < 1)
            return true;

        let p = page.parent;
        while (p && p.objectName !== "PageContainer")
            p = p.parent;
        return p?.opacity < 1;
    }
    popup.topMovement: Math.max(Tokens.sizes.nexus.minPopupHeight - popupHeight, Tokens.padding.large)

    Loader {
        anchors.centerIn: parent
        active: agentRow.popup.animDriver > 0

        sourceComponent: VerticalFadeListView {
            id: agentList

            implicitWidth: Tokens.sizes.nexus.popupWidth
            implicitHeight: CUtils.clamp(agentRow.popupHeight, Tokens.sizes.nexus.minPopupHeight, Tokens.sizes.nexus.maxPopupHeight)

            model: Agents.list

            Component.onCompleted: Agents.checkInstalled()

            delegate: StateLayer {
                id: agentItem

                required property var modelData
                readonly property bool isInstalled: Agents.installed.includes(modelData.id)

                anchors.fill: undefined
                anchors.left: agentList.contentItem.left
                anchors.right: agentList.contentItem.right
                implicitHeight: agentLayout.implicitHeight + agentLayout.anchors.margins * 2
                radius: Tokens.rounding.small

                onClicked: {
                    agentRow.popup.open = false;
                    Agents.pick(modelData.id);
                }

                RowLayout {
                    id: agentLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    Item {
                        readonly property real size: Math.round(Tokens.font.icon.large.pointSize * 1.8)

                        implicitWidth: size
                        implicitHeight: size

                        Image {
                            id: agentIcon

                            anchors.fill: parent
                            asynchronous: true
                            visible: !!source.toString() && status === Image.Ready
                            source: Agents.iconOf(agentItem.modelData.id)
                            sourceSize: Qt.size(width * 2, height * 2)
                            fillMode: Image.PreserveAspectFit
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: !agentIcon.visible
                            text: "smart_toy"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.large
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: agentItem.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: agentItem.isInstalled ? Tr.tr("Installed") : Tr.tr("Not installed, installs when picked")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    MaterialIcon {
                        visible: agentItem.modelData.id === Agents.defaultAgent
                        text: "check"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }
                }
            }
        }
    }
}
