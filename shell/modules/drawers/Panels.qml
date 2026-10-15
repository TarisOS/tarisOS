// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Effects
import Quickshell
import Taris.Config
import qs.components
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.dock as Dock
import qs.modules.launcher as Launcher
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.session as Session
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness
    // How much the panels' contents fade into their shapes (0 to 1): behind a dialog, as much as the
    // scrim darkens the apps. Their shapes, drawn with the shell's, keep its colour, and the cards on
    // them stay apart from them (darkened towards black, they'd be the shapes' colour).
    property real dim

    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias launcher: launcher
    readonly property alias dashboard: dashboard
    readonly property alias dock: dock
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias sidebar: sidebar

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: bar.implicitWidth

    Item {
        id: osdWrapper

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: session.width * (1 - session.offsetScale)
        clip: session.visible

        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight

        Osd.Wrapper {
            id: osd

            screen: root.screen
            screenState: root.screenState
            sidebarOrSessionVisible: session.visible // The short sidebar never sits beside the OSD

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Notifications.Wrapper {
        id: notifications

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        screenState: root.screenState
        sidebarPanel: sidebar
        dashboardPanel: dashboard
        osdPanel: osdWrapper
        sessionPanel: sessionWrapper
        utilitiesPanel: utilities

        anchors.top: parent.top
        anchors.right: parent.right
    }

    Item {
        id: sessionWrapper

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        // The notification sidebar is short now (top only), so the OSD and session menu stay on
        // the screen edge in the middle instead of moving out beside it
        anchors.rightMargin: 0

        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight

        Session.Wrapper {
            id: session

            screenState: root.screenState
            sidebarVisible: false // The short sidebar never sits beside the session menu

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Launcher.Wrapper {
        id: launcher

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        screen: root.screen
        screenState: root.screenState
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    // Over the app drawer, which opens around it
    Dock.Wrapper {
        id: dock

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        screenState: root.screenState

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    Dashboard.Wrapper {
        id: dashboard

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        screenState: root.screenState

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    BarPopouts.ClipWrapper {
        id: popoutsWrapper

        screen: root.screen
        borderThickness: root.borderThickness
    }

    Utilities.Wrapper {
        id: utilities

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        screenState: root.screenState
        sidebar: sidebar
        popouts: popoutsWrapper.content

        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }

    Sidebar.Wrapper {
        id: sidebar

        layer.enabled: root.dim > 0
        layer.effect: Dim {}
        screenState: root.screenState

        // Drops down from the top, as tall as the quick actions panel
        fullHeight: utilities.nonAnimHeight
        anchors.top: notifications.bottom
        anchors.right: parent.right
        anchors.topMargin: -notifications.anchors.topMargin - (implicitHeight + 5) * offsetScale
    }

    component Dim: MultiEffect {
        opacity: 1 - root.dim
    }
}
