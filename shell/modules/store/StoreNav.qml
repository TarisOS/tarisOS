// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.store

// The Store's search and its places, styled like the Settings sidebar (NavLocations)
ColumnLayout {
    id: root

    required property StoreState sState

    // Grouped like the settings categories: the Store's own places, then the app categories
    // (freedesktop main categories, which Flathub's are too)
    readonly property list<var> places: [
        {
            view: "discover",
            label: Tr.tr("Discover"),
            icon: "explore",
            group: 0
        },
        {
            view: "installed",
            label: Tr.tr("Installed"),
            icon: "apps",
            group: 0
        },
        {
            view: "updates",
            label: Tr.tr("Updates"),
            icon: "update",
            group: 0
        },
        {
            view: "category",
            category: "AudioVideo",
            label: Tr.tr("Audio & video"),
            icon: "music_video",
            group: 1
        },
        {
            view: "category",
            category: "Development",
            label: Tr.tr("Development"),
            icon: "code",
            group: 1
        },
        {
            view: "category",
            category: "Education",
            label: Tr.tr("Education"),
            icon: "school",
            group: 1
        },
        {
            view: "category",
            category: "Game",
            label: Tr.tr("Games"),
            icon: "sports_esports",
            group: 1
        },
        {
            view: "category",
            category: "Graphics",
            label: Tr.tr("Graphics & photos"),
            icon: "palette",
            group: 1
        },
        {
            view: "category",
            category: "Network",
            label: Tr.tr("Internet"),
            icon: "language",
            group: 1
        },
        {
            view: "category",
            category: "Office",
            label: Tr.tr("Productivity"),
            icon: "work",
            group: 1
        },
        {
            view: "category",
            category: "Science",
            label: Tr.tr("Science"),
            icon: "science",
            group: 1
        },
        {
            view: "category",
            category: "System",
            label: Tr.tr("System"),
            icon: "settings_suggest",
            group: 1
        },
        {
            view: "category",
            category: "Utility",
            label: Tr.tr("Utilities"),
            icon: "build",
            group: 1
        }
    ]

    spacing: Tokens.spacing.large

    SearchBar {
        id: searchField

        Layout.fillWidth: true
        // Over the list, which reaches up under it (its negative top margin): scrolled, the list's
        // rows would otherwise be on top here and take the clicks meant for the search (as in Settings)
        z: 1
        placeholderText: Tr.tr("Search apps")
        font: Tokens.font.body.large
        bg.color: Colours.tPalette.m3surfaceContainerLowest
        bg.border.color: Colours.palette.m3outlineVariant
        searchIcon.fontStyle: Tokens.font.icon.medium
        searchIcon.anchors.leftMargin: Tokens.padding.largeIncreased
        clearIcon.font: Tokens.font.icon.medium
        clearIcon.padding: Tokens.padding.extraSmall

        // Searches once typing pauses (each search asks the repos, Flathub and the AUR)
        onTextChanged: searchTimer.restart()

        Timer {
            id: searchTimer

            interval: 350
            onTriggered: root.sState.searchText = searchField.text.trim()
        }

        Connections {
            function onSearchTextChanged(): void {
                if (!root.sState.searchText && searchField.text)
                    searchField.text = "";
            }

            target: root.sState
        }
    }

    VerticalFadeFlickable {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: -topMargin
        Layout.bottomMargin: -bottomMargin
        topMargin: Tokens.padding.large
        bottomMargin: Tokens.padding.large
        contentHeight: content.implicitHeight

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root.places

                StyledRect {
                    id: item

                    required property var modelData
                    required property int index

                    readonly property bool isCurrent: !root.sState.searchText && root.sState.view === modelData.view && (modelData.view !== "category" || root.sState.category === modelData.category)
                    readonly property bool isGroupStart: index === 0 || root.places[index - 1].group !== modelData.group
                    readonly property bool isGroupEnd: index === root.places.length - 1 || root.places[index + 1].group !== modelData.group

                    Layout.fillWidth: true
                    Layout.topMargin: index !== 0 && isGroupStart ? Tokens.spacing.medium : 0
                    implicitHeight: {
                        const h = layout.implicitHeight + layout.anchors.margins * 2;
                        return h % 2 === 0 ? h : h + 1;
                    }

                    color: isCurrent ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                    topLeftRadius: stateLayer.pressed ? Tokens.rounding.medium : isCurrent ? Tokens.rounding.extraLargeIncreased : isGroupStart ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: stateLayer.pressed ? Tokens.rounding.medium : isCurrent ? Tokens.rounding.extraLargeIncreased : isGroupEnd ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
                    bottomRightRadius: bottomLeftRadius

                    RadiusBehavior on topLeftRadius {}
                    RadiusBehavior on bottomLeftRadius {}

                    StateLayer {
                        id: stateLayer

                        anchors.fill: parent
                        topLeftRadius: parent.topLeftRadius
                        topRightRadius: parent.topRightRadius
                        bottomLeftRadius: parent.bottomLeftRadius
                        bottomRightRadius: parent.bottomRightRadius
                        onClicked: {
                            root.sState.searchText = "";
                            root.sState.show(item.modelData.view, item.modelData.category ?? "", item.modelData.label);
                        }
                    }

                    RowLayout {
                        id: layout

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        anchors.leftMargin: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        StyledRect {
                            implicitWidth: implicitHeight
                            implicitHeight: icon.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: item.isCurrent ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                            MaterialIcon {
                                id: icon

                                anchors.centerIn: parent
                                text: item.modelData.icon
                                color: item.isCurrent ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.builders.medium.weight(Font.Medium).build()
                                fill: 1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: item.modelData.label
                            font: Tokens.font.body.medium
                            elide: Text.ElideRight
                        }

                        // Waiting updates
                        StyledRect {
                            visible: item.modelData.view === "updates" && AppStore.updateCount > 0
                            implicitWidth: Math.max(implicitHeight, count.implicitWidth + Tokens.padding.small * 2)
                            implicitHeight: count.implicitHeight + Tokens.padding.extraSmall * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primary

                            StyledText {
                                id: count

                                anchors.centerIn: parent
                                text: AppStore.updateCount
                                color: Colours.palette.m3onPrimary
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }
    }

    component RadiusBehavior: Behavior {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
