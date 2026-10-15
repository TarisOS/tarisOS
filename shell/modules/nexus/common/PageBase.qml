// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.nexus

ColumnLayout {
    id: root

    required property string title
    required property NexusState nState
    property bool isSubPage
    // Shown inside another page (General, Appearance: PageRegistry.consolidated): no title, its
    // content flows with that page's, which scrolls it
    property bool embedded
    readonly property int cappedWidth: Math.min(Tokens.sizes.nexus.maxContentWidth, width)
    readonly property alias flickable: flickable

    default property Item contentChild
    // Tries left to find the option the search picked (rows load a moment after the page)
    property int revealTries
    // Over the option the search picked, for a moment (in the flickable's content, not this layout)
    property StyledRect _flash: StyledRect {
        id: flash

        z: 2
        opacity: 0
        radius: Tokens.rounding.large
        color: Colours.palette.m3primary

        SequentialAnimation {
            id: flashAnim

            Anim {
                target: flash
                property: "opacity"
                to: 0.25
            }
            Anim {
                target: flash
                property: "opacity"
                to: 0
            }
            Anim {
                target: flash
                property: "opacity"
                to: 0.25
            }
            Anim {
                target: flash
                property: "opacity"
                to: 0
                type: Anim.SlowEffects
            }
        }
    }

    // The search picked an option on this page: find its row (its label is its text or label),
    // scroll to it and flash it
    function reveal(): void {
        const label = nState.revealLabel;
        if (!label || !visible || embedded)
            return;
        const find = item => {
            for (const child of item?.children ?? []) {
                if (child.visible !== false && (child.text === label || child.label === label) && child.height > 0 && child !== root)
                    return child;
                const deeper = find(child);
                if (deeper)
                    return deeper;
            }
            return null;
        };
        const row = find(contentChild);
        if (!row) {
            if (revealTries-- > 0)
                revealTimer.restart();
            return;
        }
        nState.revealLabel = "";
        // The row itself, not its label inside it: up to the widest item under the content
        let target = row;
        while (target.parent && target.parent !== contentChild && target.parent.width <= contentChild.width && target.width < contentChild.width * 0.9)
            target = target.parent;
        const pos = target.mapToItem(flickable.contentItem, 0, 0);
        const maxY = Math.max(0, flickable.contentHeight - flickable.height);
        flickable.contentY = Math.max(0, Math.min(maxY, pos.y - flickable.height / 3));
        flash.x = pos.x;
        flash.y = pos.y;
        flash.width = target.width;
        flash.height = target.height;
        flashAnim.restart();
    }

    function startReveal(): void {
        revealTries = 15;
        revealTimer.restart();
    }

    spacing: Tokens.spacing.extraLargeIncreased

    Component.onCompleted: startReveal()

    Connections {
        function onRevealLabelChanged(): void {
            if (root.nState.revealLabel)
                root.startReveal();
        }

        target: root.nState
    }

    Timer {
        id: revealTimer

        interval: 100
        onTriggered: root.reveal()
    }

    MouseArea { // Prevent clicks from reaching flickable
        z: 1
        visible: !root.embedded // Embedded, its section headers are enough
        implicitWidth: header.implicitWidth
        implicitHeight: header.implicitHeight - Layout.bottomMargin
        Layout.bottomMargin: -flickable.topMargin // Extra height to block clicks on flickable top margin
        onClicked: focus = true

        RowLayout {
            id: header

            spacing: Tokens.spacing.largeIncreased

            Loader {
                visible: active
                active: root.isSubPage
                asynchronous: true
                sourceComponent: IconButton {
                    icon: "arrow_back"
                    font: Tokens.font.icon.medium
                    type: IconButton.Tonal
                    isRound: true
                    inactiveColour: Colours.tPalette.m3surfaceContainerHigh
                    inactiveOnColour: Colours.palette.m3onSurfaceVariant
                    onClicked: root.nState.closeSubPage()
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }
        }
    }

    VerticalFadeFlickable {
        id: flickable

        Layout.fillWidth: true
        Layout.fillHeight: !root.embedded
        // Embedded, as tall as its content (the page it's in scrolls)
        Layout.preferredHeight: root.embedded ? contentHeight + topMargin + bottomMargin : -1

        Layout.topMargin: -topMargin
        topMargin: root.embedded ? 0 : Tokens.padding.large
        bottomMargin: root.embedded ? 0 : Tokens.padding.extraLarge
        interactive: !root.embedded

        contentHeight: root.contentChild?.implicitHeight ?? 0
        // This replaces the content's children, so it keeps the momentum scrolling among them (and
        // the flash over an option the search picked)
        contentItem.children: [flickable.glide, root.contentChild, flash]

        TapHandler {
            onTapped: flickable.focus = true
        }
    }
}
