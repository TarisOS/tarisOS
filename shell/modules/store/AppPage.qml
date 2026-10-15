// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.store

// An app's page: install, open, remove or update it (from the source picked when it's in more
// than one), its screenshots, description and details
StorePage {
    id: root

    readonly property var app: sState.app
    // The sources it's in: its own first (native first), then the others
    readonly property var sources: [
        {
            source: app.source,
            pkg: app.pkg,
            key: app.key
        },
        ...(app.alt ?? [])
    ]
    property int sourceIdx
    readonly property var current: sources[Math.min(sourceIdx, sources.length - 1)]

    property var details: null
    property int req: -1
    property bool confirmRemove

    readonly property var job: AppStore.jobs[current.key] ?? null
    // A job of the helper's, or a terminal working on it (AUR apps)
    readonly property bool busy: job?.state === "running" || AppStore.awaitingAur[current.pkg] !== undefined
    // A repo app comes with the system's pending updates (installing it alone from outdated package
    // lists fails, and refreshing them alone is a partial upgrade)
    readonly property int systemUpdates: current.source === "native" && !installed ? (details?.systemUpdates ?? 0) : 0
    readonly property bool installed: details?.installed ?? false

    function load(): void {
        AppStore.cancel(req);
        const cur = current;
        req = AppStore.request("app", {
            source: cur.source,
            pkg: cur.pkg,
            appId: app.id
        }, (result, err) => {
            req = -1;
            details = result;
            error = err;
        });
    }

    title: ""
    canGoBack: true
    loading: details === null
    empty: details === null
    onCurrentChanged: {
        details = null;
        load();
    }

    Component.onCompleted: load()
    Component.onDestruction: AppStore.cancel(req)

    Connections {
        function onChangesChanged(): void {
            root.load();
        }

        target: AppStore
    }

    Timer {
        id: confirmTimer

        interval: 4000
        onTriggered: root.confirmRemove = false
    }

    // Icon, name, where it's from, and what can be done with it
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraLarge

        AppIcon {
            Layout.alignment: Qt.AlignTop
            app: root.app
            size: 96
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: root.app.name
                font: Tokens.font.headline.small
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.details?.developer ?? ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            // The sources it's in; the picked one is what the buttons install, open or remove
            Row {
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.sources

                    StyledRect {
                        id: chip

                        required property var modelData
                        required property int index
                        readonly property bool picked: index === root.sourceIdx

                        implicitWidth: chipLabel.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: chipLabel.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.full
                        color: picked ? Colours.palette.m3secondaryContainer : "transparent"
                        border.width: picked ? 0 : 1
                        border.color: Colours.palette.m3outlineVariant

                        StateLayer {
                            radius: chip.radius
                            disabled: root.sources.length < 2
                            onClicked: root.sourceIdx = chip.index
                        }

                        StyledText {
                            id: chipLabel

                            anchors.centerIn: parent
                            text: chip.modelData.source === "flathub" ? "Flathub" : chip.modelData.source === "aur" ? "AUR" : Tr.tr("Arch")
                            font: Tokens.font.label.large
                            color: chip.picked ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Tokens.spacing.small
                visible: !root.busy

                TextButton {
                    visible: root.installed
                    type: TextButton.Tonal
                    text: root.confirmRemove ? Tr.tr("Confirm") : Tr.tr("Remove")
                    onClicked: {
                        if (!root.confirmRemove) {
                            root.confirmRemove = true;
                            confirmTimer.restart();
                            return;
                        }
                        root.confirmRemove = false;
                        AppStore.remove(root.app, root.current.source, root.current.pkg, root.current.key);
                    }
                }

                TextButton {
                    visible: root.installed && !!root.app.newVersion && root.current.source === root.app.source
                    text: Tr.tr("Update")
                    onClicked: AppStore.update(root.app)
                }

                TextButton {
                    visible: root.installed && !root.app.newVersion
                    text: Tr.tr("Open")
                    onClicked: {
                        AppStore.launch(Object.assign({}, root.app, {
                            source: root.current.source,
                            pkg: root.current.pkg,
                            desktop: root.current.source === "flathub" ? root.current.pkg + ".desktop" : root.app.desktop
                        }));
                        if (!root.sState.isWindow)
                            root.sState.close();
                    }
                }

                TextButton {
                    visible: !root.installed
                    disabled: !(root.details?.buildsHere ?? true)
                    text: root.systemUpdates > 0 ? Tr.tr("Update & install") : Tr.tr("Install")
                    onClicked: AppStore.install(root.app, root.current.source, root.current.pkg, root.current.key)
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignRight
                visible: !root.busy && root.systemUpdates > 0
                text: root.systemUpdates === 1 ? Tr.tr("With 1 system update") : Tr.tr("With %1 system updates").arg(root.systemUpdates)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }

            StyledText {
                Layout.alignment: Qt.AlignRight
                visible: !root.installed && !(root.details?.buildsHere ?? true)
                text: Tr.tr("No ARM build")
                color: Colours.palette.m3error
                font: Tokens.font.label.medium
            }

            // Working: how far, and what it's doing
            ColumnLayout {
                Layout.preferredWidth: 220
                visible: root.busy
                spacing: Tokens.spacing.extraSmall

                StyledProgressBar {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.padding.small
                    value: root.job?.progress >= 0 ? root.job.progress : 0
                    indeterminate: !(root.job?.progress >= 0)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.job?.message ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.app.summary
        font: Tokens.font.title.small
        wrapMode: Text.Wrap
    }

    // Screenshots, side by side: the arrows move through them (scrolling scrolls the page), a
    // click opens the preview
    Item {
        Layout.fillWidth: true
        implicitHeight: 260
        visible: (root.details?.screenshots?.length ?? 0) > 0

        ListView {
            id: shots

            // The scroll a step goes to: about a view's width, within the gallery
            function step(dir: int): void {
                const max = Math.max(0, contentWidth - width);
                contentX = Math.max(0, Math.min(max, contentX + dir * width * 0.8));
            }

            anchors.fill: parent
            orientation: ListView.Horizontal
            spacing: Tokens.spacing.medium
            clip: true
            interactive: false // No dragging or wheel: the arrows move it
            model: root.details?.screenshots ?? []

            delegate: StyledClippingRect {
                id: shot

                required property var modelData
                required property int index

                implicitHeight: shots.height
                implicitWidth: img.status === Image.Ready && img.implicitHeight > 0 ? Math.round(shots.height * img.implicitWidth / img.implicitHeight) : shots.height * 16 / 9
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                Image {
                    id: img

                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    source: "file://" + shot.modelData.thumb
                    sourceSize.height: shots.height * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
                }

                StateLayer {
                    radius: shot.radius
                    onClicked: root.sState.viewer = {
                        shots: root.details.screenshots,
                        index: shot.index
                    }
                }
            }

            Behavior on contentX {
                Anim {}
            }
        }

        GalleryArrow {
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.medium
            icon: "chevron_left"
            shown: shots.contentX > 1
            onClicked: shots.step(-1)
        }

        GalleryArrow {
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.medium
            icon: "chevron_right"
            shown: shots.contentX < shots.contentWidth - shots.width - 1
            onClicked: shots.step(1)
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.details?.description ?? ""
        font: Tokens.font.body.medium
        color: Colours.palette.m3onSurface
        wrapMode: Text.Wrap
        lineHeight: 1.15
    }

    // Details
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Tokens.spacing.extraLarge
        rowSpacing: Tokens.spacing.small

        Repeater {
            model: [
                {
                    label: Tr.tr("Version"),
                    value: root.details?.version ?? ""
                },
                {
                    label: Tr.tr("Size"),
                    value: root.details?.size ?? ""
                },
                {
                    label: Tr.tr("License"),
                    value: root.details?.license ?? ""
                },
                {
                    label: Tr.tr("Votes"),
                    value: root.details?.votes !== undefined ? String(root.details.votes) : ""
                },
                {
                    label: Tr.tr("Package"),
                    value: root.current.pkg
                }
            ].filter(r => r.value)

            delegate: RowLayout {
                id: info

                required property var modelData

                Layout.columnSpan: 2
                spacing: Tokens.spacing.large

                StyledText {
                    Layout.preferredWidth: 90
                    text: info.modelData.label
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: info.modelData.value
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }
    }

    TextButton {
        visible: (root.details?.homepage ?? "") !== ""
        type: TextButton.Tonal
        text: Tr.tr("Website")
        onClicked: Qt.openUrlExternally(root.details.homepage)
    }
}
