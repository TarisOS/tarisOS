// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Taris.Blobs
import Taris.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.store

// The Store: apps from the repos, Flathub and the AUR (services/AppStore.qml), framed like
// Settings (Nexus): navigation on the left, the view or an app's page on the right
Item {
    id: root

    readonly property StoreState sState: StoreState {
        onClose: root.close()
    }

    property color blobColour: Colours.tPalette.m3surfaceContainerLow

    signal close

    // No wider than the screen allows (a rotated one is narrower than it is tall)
    implicitWidth: Math.round(Math.min(implicitHeight * Tokens.sizes.nexus.ratio, (sState.screen?.width ?? 1600) * 0.8))
    implicitHeight: Math.round((sState.screen?.height ?? 900) * Tokens.sizes.nexus.heightMult)

    // The helper runs while a Store is open
    Component.onCompleted: AppStore.users++
    Component.onDestruction: AppStore.users--

    TapHandler {
        onTapped: root.focus = true
    }

    BlobGroup {
        id: blobGroup

        smoothing: root.Tokens.rounding.medium
        color: root.blobColour
    }

    BlobInvertedRect {
        anchors.fill: parent
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.large
        borderLeft: nav.width + nav.anchors.margins * 2
        borderRight: Tokens.padding.medium
        borderTop: Tokens.padding.medium
        borderBottom: Tokens.padding.medium
    }

    BlobRect {
        id: windowBtnRect

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.sState.isWindow ? 0 : Tokens.padding.extraSmall
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.medium
        implicitWidth: windowBtn.implicitWidth + (root.sState.isWindow ? Tokens.padding.extraSmall : Tokens.padding.small) * 2
        implicitHeight: windowBtn.implicitHeight + (root.sState.isWindow ? Tokens.padding.extraSmall : Tokens.padding.small)
    }

    IconButton {
        id: windowBtn

        anchors.centerIn: windowBtnRect
        icon: root.sState.isWindow ? "close" : "pip"
        type: IconButton.Text
        label.fill: 0
        inactiveOnColour: hovered ? root.sState.isWindow ? Colours.palette.m3error : Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        stateLayer.opacity: 0
        onClicked: {
            if (!root.sState.isWindow)
                StoreWindow.create();
            root.close();
        }
        label.scale: pressed ? 0.8 : 1
        label.renderType: Text.QtRendering

        Behavior on label.scale {
            Anim {}
        }
    }

    StoreNav {
        id: nav

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large
        sState: root.sState
        width: Math.min(Tokens.sizes.nexus.maxNavWidth, Math.round(root.width / 3.4))
    }

    Loader {
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: nav.anchors.margins + anchors.margins
        anchors.margins: Tokens.padding.extraLarge

        sourceComponent: root.sState.app ? appPage : root.sState.searchText ? searchView : root.sState.view === "discover" ? discoverView : root.sState.view === "updates" ? updatesView : root.sState.view === "installed" ? installedView : categoryView
    }

    // A screenshot's preview, over everything else in the Store
    ShotViewer {
        anchors.fill: parent
        z: 1
        sState: root.sState
    }

    Component {
        id: appPage

        AppPage {
            sState: root.sState
        }
    }

    Component {
        id: searchView

        SearchView {
            sState: root.sState
        }
    }

    Component {
        id: discoverView

        DiscoverView {
            sState: root.sState
        }
    }

    Component {
        id: categoryView

        CategoryView {
            sState: root.sState
        }
    }

    Component {
        id: installedView

        InstalledView {
            sState: root.sState
        }
    }

    Component {
        id: updatesView

        UpdatesView {
            sState: root.sState
        }
    }
}
