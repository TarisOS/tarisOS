// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Taris.Blobs
import Taris.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: contentItem.Config.border.thickness * (1 - fsTransitionProg)
    readonly property real borderRounding: contentItem.Config.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness

    property color surfaceColour: Colours.tPalette.m3surface
    // The launcher has the keyboard while it's open, wherever the pointer is: Exclusive, which
    // Hyprland gives the keyboard to at once and keeps it on (on demand, it got it only once the
    // pointer had been over it, the focus grab not always handing it over). Not while a password
    // prompt, the area picker, the shortcuts or the emoji picker need it (ShellState.grabsReleased).
    // Turning Exclusive ends any focus grab (Hyprland's LayerSurface::onCommit: setGrab(nullptr)),
    // which would close the launcher as a click outside does, so there's no grab meanwhile: Hyprland
    // sends an Exclusive layer every click, and a click outside closes the panels (Interactions)
    readonly property bool launcherExclusive: screenState.launcher && contentItem.Config.launcher.enabled && !ShellState.grabsReleased

    readonly property int dragMaskPadding: {
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.toplevels.values.length > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    // A click outside the shell: what the focus grab's cleared does, and Interactions while the
    // launcher has the keyboard
    function closePanels(): void {
        screenState.launcher = false;
        screenState.session = false;
        screenState.sidebar = false;
        screenState.dashboard = false;
        panels.popouts.hasCurrent = false;
        bar.closeTray();
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close("fullscreen changed");
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    // The dashboard's status takes the keyboard while it's typed in (on demand, it would only get it
    // at the next click): Enter, Escape or the dashboard closing ends that
    // (The Agent tab's terminal takes the keyboard on its own surface: services/AgentTerminal.qml)
    WlrLayershell.keyboardFocus: (screenState.dashboard && screenState.statusEditing) || launcherExclusive ? WlrKeyboardFocus.Exclusive : screenState.launcher || screenState.session ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: hasFullscreen ? emptyRegion : regions

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {}
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    Region {
        id: emptyRegion

        x: panels.notifications.x + bar.implicitWidth
        y: panels.notifications.y + root.borderThickness
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: root.width - width
            y: panels.osdWrapper.y + root.borderThickness
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + root.borderThickness
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: {
            // A password prompt (modules/polkit) or the screenshot area picker is up: it gets the
            // clicks and the keyboard
            if (ShellState.grabsReleased || root.launcherExclusive)
                return false;
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled))
                return true;
            if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            if (panels.popouts.held)
                return true;
            return false;
        }
        // With the Agent tab's terminal, a surface of its own over the dashboard: a click in it is a
        // click in the dashboard
        windows: AgentTerminal.surface.visible && AgentTerminal.screen === root.screen ? [root, AgentTerminal.surface] : [root]
        onCleared: root.closePanels()
    }

    // Under the shell's shapes: it darkens the apps, not the shell (the panels behind a dialog have
    // their contents faded as much instead: Panels.dim)
    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.surfaceColour.a
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }

        BlobGroup {
            id: blobGroup

            color: root.surfaceColour
            smoothing: root.contentItem.Config.border.smoothing
        }

        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: root.borderRounding
            borderLeft: bar.implicitWidth - anchors.margins - root.sdfBorderOffset
            borderRight: root.borderThickness - anchors.margins - root.sdfBorderOffset
            borderTop: root.borderThickness - anchors.margins - root.sdfBorderOffset
            borderBottom: root.borderThickness - anchors.margins - root.sdfBorderOffset
        }

        PanelBg {
            id: dashBg

            panel: panels.dashboard
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }

        // Kept apart from the app drawer's: the drawer is wider and already goes around the dock,
        // so melting the two would only bulge the edges beside it
        PanelBg {
            id: dockBg

            // EXPERIMENT, dock bounces with the app drawer (to undo: delete these marked lines and
            // the dock.transform ones below). While the drawer covers the dock, the dock's own shape
            // gives way to the drawer's, which carries the bounce.
            readonly property bool underDrawer: panels.launcher.visible && panels.launcher.height * (1 - panels.launcher.offsetScale) >= panels.dock.height

            implicitHeight: underDrawer ? 0 : panel.height // EXPERIMENT (as above)
            panel: panels.dock
            deformAmount: 0.1
            exclude: [launcherBg]
        }

        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.sessionWrapper.x + panels.session.x + bar.implicitWidth
            implicitWidth: panels.session.width
        }

        PanelBg {
            id: sidebarBg

            panel: panels.sidebar
            deformAmount: 0.03
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            exclude: [utilsBg] // Separate panels: without this their blobs melt into a bridge
            bottomLeftRadius: radius
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.osdWrapper.x + panels.osd.x + bar.implicitWidth
            implicitWidth: panels.osd.width
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            exclude: [sidebarBg]
            topLeftRadius: radius
        }

        // A bar popout's shape; a dialog's is drawn over the other panels instead (dialogBg)
        PanelBg {
            id: popoutBg

            // Extra width to prevent vertical movement deformation partially detaching panel from bar
            property real extraWidth: panels.popouts.isDetached ? 0 : 0.2

            group: panels.popouts.isDetached ? null : blobGroup
            panel: panels.popoutsWrapper
            deformAmount: panels.popouts.hasCurrent ? 0.15 : 0.1
            x: panels.popoutsWrapper.x + panels.popouts.x + bar.implicitWidth - panels.popouts.width * extraWidth
            implicitWidth: panels.popouts.width * (1 + extraWidth)

            Behavior on extraWidth {
                Anim {}
            }
        }
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen
        launcherExclusive: root.launcherExclusive
        onPressedOutside: root.closePanels()

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            borderThickness: root.borderThickness

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            dock.transform: Matrix4x4 {
                // EXPERIMENT, dock bounces with the app drawer (to undo: back to just
                // `matrix: dockBg.deformMatrix`). Under the drawer, the dock squashes and stretches
                // with it, around the drawer's centre (its deform, moved into the dock's coordinates)
                matrix: {
                    if (!dockBg.underDrawer)
                        return dockBg.deformMatrix;
                    const cx = panels.launcher.x + panels.launcher.width / 2 - panels.dock.x;
                    const cy = panels.launcher.y + panels.launcher.height / 2 - panels.dock.y;
                    const to = Qt.matrix4x4(1, 0, 0, cx, 0, 1, 0, cy, 0, 0, 1, 0, 0, 0, 0, 1);
                    const back = Qt.matrix4x4(1, 0, 0, -cx, 0, 1, 0, -cy, 0, 0, 1, 0, 0, 0, 0, 1);
                    return to.times(launcherBg.rawDeformMatrix).times(back);
                }
                // END EXPERIMENT
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: panels.popouts.isDetached ? dialogBg.deformMatrix : popoutBg.deformMatrix
            }
            // A dialog (Settings, the Store, the file picker, the terminal) is over every other
            // panel: notifications, the OSD and the rest stay behind it, their contents faded as much
            // as the scrim darkens the apps
            dim: panels.popouts.isDetached ? 0.5 : 0
            popoutsWrapper.z: panels.popouts.isDetached ? 2 : 0

            Behavior on dim {
                Anim {
                    type: Anim.SlowEffects
                }
            }

            // The dialog's shape, with its own shadow: above the other panels' shapes and contents,
            // under the dialog's (it's in the panels' item, which starts after the bar and border)
            Item {
                x: -bar.implicitWidth
                y: -root.borderThickness
                z: 1
                width: root.width
                height: root.height
                visible: panels.popouts.isDetached
                opacity: root.surfaceColour.a
                layer.enabled: visible
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    blurMax: 15
                    shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
                }

                BlobGroup {
                    id: dialogBlobGroup

                    color: root.surfaceColour
                    smoothing: root.contentItem.Config.border.smoothing
                }

                PanelBg {
                    id: dialogBg

                    group: panels.popouts.isDetached ? dialogBlobGroup : null
                    panel: panels.popoutsWrapper
                    deformAmount: 0.05
                    x: panels.popoutsWrapper.x + panels.popouts.x + bar.implicitWidth
                    implicitWidth: panels.popouts.width
                }
            }
        }

        BarWrapper {
            id: bar

            anchors.top: parent.top
            anchors.bottom: parent.bottom

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts

            fullscreen: root.hasFullscreen
        }

        // While a dialog is open, nothing behind it takes clicks (Regions gives this window the
        // whole screen then): a click anywhere outside it closes it and does nothing else. Clicks
        // and scrolling inside it go on to it, and its open menus are above this.
        MouseArea {
            id: dialogOutside

            function inDialog(x: real, y: real): bool {
                return panels.popoutsWrapper.contains(panels.popoutsWrapper.mapFromItem(dialogOutside, x, y));
            }

            anchors.fill: parent
            enabled: panels.popouts.isDetached
            acceptedButtons: Qt.AllButtons

            onPressed: mouse => mouse.accepted = !inDialog(mouse.x, mouse.y)
            onClicked: panels.popouts.close("clicked outside")
            onWheel: wheel => wheel.accepted = !inDialog(wheel.x, wheel.y)
        }
    }

    // An app being dragged to the dock follows the pointer, over everything
    IconImage {
        readonly property bool shown: Dock.dragApp !== null && Dock.dragWindow === root

        z: 100
        visible: shown
        x: Dock.dragPos.x - implicitSize / 2
        y: Dock.dragPos.y - implicitSize / 2
        implicitSize: 44
        source: shown ? Quickshell.iconPath(Dock.dragApp.icon, "image-missing") : ""
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15

        group: blobGroup
        x: panel.x + bar.implicitWidth
        y: panel.y + root.borderThickness
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.extraLarge
        deformScale: (deformAmount * Config.appearance.deformScale) / 10000
    }
}
