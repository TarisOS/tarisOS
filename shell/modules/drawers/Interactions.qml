// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Taris.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property ScreenState screenState
    required property Panels panels
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property bool fullscreen
    // The launcher has the keyboard (ContentWindow): every click comes here, and one outside the
    // shell closes the panels (pressedOutside), as the focus grab otherwise does
    property bool launcherExclusive

    property point dragStart
    property bool dashboardShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive
    // The Agent tab's terminal took the pointer as its surface came up: Hyprland gives a layer
    // surface that takes the keyboard the pointer too, wherever the pointer is, so the shell saw the
    // pointer leave though it hadn't moved (and gets it back only once it moves). Without this, a
    // pointer resting at the top edge closed the dashboard, which took the terminal away, which gave
    // the pointer back and opened the dashboard again, over and over.
    property bool agentTookPointer
    // The power panel is open: the notifications don't open from their corner then, nor the
    // dashboard from the top edge, as the quick toggles don't show (modules/utilities/Wrapper.qml)
    readonly property bool sessionOpen: screenState.session && Config.session.enabled
    // The panel being pushed open from its screen edge (pushToShow; "": none), when the pointer was
    // last put back from the edge, and when the push started
    property string pushPanel
    property double pushedAt
    property double pushStart

    signal pressedOutside

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = root.borderThickness + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panel.height + Config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = bar.implicitWidth + panel.x;
        return x >= panelX - Config.border.rounding && x <= panelX + panel.width + Config.border.rounding;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        return x < bar.implicitWidth + panel.x + panel.width && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panel.x) && withinPanelHeight(panel, x, y);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) - (isCorner ? Config.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    // The very top-right corner of the screen (the frame's corner), not the top edge, so panels that
    // open along the top (the dashboard) don't open the sidebar on their way past
    function inSidebarCorner(x: real, y: real): bool {
        const corner = Config.border.thickness + Config.border.rounding;
        return x >= width - corner && y <= corner;
    }

    // The very bottom-right corner of the screen, so the quick actions panel doesn't open on the way
    // along the bottom edge (to the dock); once open it stays while the pointer is on it
    function inUtilitiesCorner(x: real, y: real): bool {
        const corner = Config.border.thickness + Config.border.rounding;
        return x >= width - corner && y >= height - corner;
    }

    // The closed dashboard (top edge), the hidden dock (bottom edge), the sidebar (top-right corner)
    // and the utilities (bottom-right corner) show only when the pointer keeps being pushed into the
    // edge, not when it touches it, however fast (aiming for a browser's tabs at the top of the
    // screen). Pushed past the edge the pointer goes no further and Hyprland sends nothing, so each
    // touch puts it back 2 px (inside the border, which is the shell's): pushing on brings it to the
    // edge again at once, touch after touch. It shows once the touches have kept coming for time ms
    // (Settings: each panel's push force), each within 0.1 s of the one before; a flick is over well
    // before. A longer gap starts again. Where another display carries on past the edge the pointer
    // goes through instead of stopping, so nothing can be pushed: the panel shows on touch there.
    function pushToShow(panel: string, x: real, y: real, time: int): bool {
        const edges = ({
                dashboard: "top",
                dock: "bottom",
                sidebar: "top right",
                utilities: "bottom right"
            })[panel];
        if (edgeShared(edges, x, y)) {
            stopPush();
            return true;
        }
        const room = Math.min(2, Config.border.clampedThickness - 1);
        if (time <= 0 || room <= 0)
            return true;
        const atTop = edges.includes("top") && y <= 0;
        const atBottom = edges.includes("bottom") && y >= height - 1;
        const atRight = edges.includes("right") && x >= width - 1;
        if (!atTop && !atBottom && !atRight)
            return false;
        const now = Date.now();
        if (pushPanel !== panel || pushedAt <= 0 || now - pushedAt > 100) {
            pushPanel = panel;
            pushStart = now;
        }
        if (now - pushStart >= time) {
            stopPush();
            return true;
        }
        pushedAt = now;
        const gx = Math.round(screen.x + (atRight ? width - 1 - room : x));
        const gy = Math.round(screen.y + (atTop ? room : atBottom ? height - 1 - room : y));
        // In a corner, pushing on brings the pointer back to the very same point each time, and Qt
        // drops it: Qt Wayland merges the pointer's motion put back and pushed on into one
        // (QWaylandInputDevice::Pointer::setFrameEvent), and a move to where the pointer already was
        // is filtered out (QGuiApplicationPrivate::processMouseEvent). So a moment after it's put
        // back there Hyprland is asked where it is (cornerPush): back in the corner, it's being pushed
        // on; where it was put, it was let be.
        if (atRight && (atTop || atBottom)) {
            cornerPush.time = time;
            cornerPush.restart();
        }
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.cursor.move({ x = ${gx}, y = ${gy} })` : `movecursor ${gx} ${gy}`);
        return false;
    }

    // Whether another display carries on past one of this screen's edges ("top", "bottom", "right",
    // as pushToShow names them) where the pointer is
    function edgeShared(edges: string, x: real, y: real): bool {
        const gx = screen.x + x;
        const gy = screen.y + y;
        return Quickshell.screens.some(s => {
            if (s.name === screen.name)
                return false;
            const alongX = gx >= s.x && gx < s.x + s.width;
            const alongY = gy >= s.y && gy < s.y + s.height;
            const top = edges.includes("top") && alongX && Math.abs(s.y + s.height - screen.y) <= 1;
            const bottom = edges.includes("bottom") && alongX && Math.abs(s.y - (screen.y + screen.height)) <= 1;
            const right = edges.includes("right") && alongY && Math.abs(s.x - (screen.x + screen.width)) <= 1;
            return top || bottom || right;
        });
    }

    function stopPush(): void {
        cornerPush.stop();
        pushPanel = "";
        pushedAt = 0;
        pushStart = 0;
    }

    // Over the windows: inside the border and the bar, and on none of the panels that are out
    function overWindows(x: real, y: real): bool {
        const t = Config.border.clampedThickness;
        if (x < bar.clampedWidth || x > width - t || y < t || y > height - t)
            return false;
        if (inBottomPanel(panels.launcher, x, y) || inBottomPanel(panels.dock, x, y))
            return false;
        if (screenState.dashboard && inTopPanel(panels.dashboard, x, y))
            return false;
        if ((screenState.sidebar || screenState.session) && (inRightPanel(panels.sidebar, x, y) || inRightPanel(panels.sessionWrapper, x, y)))
            return false;
        if (screenState.utilities && inBottomPanel(panels.utilities, x, y, true))
            return false;
        if (popouts.hasCurrent && inLeftPanel(panels.popoutsWrapper, x, y))
            return false;
        return true;
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        if (event.x < bar.implicitWidth) {
            bar.handleWheel(event.y, event.angleDelta);
        }
    }

    anchors.fill: parent
    acceptedButtons: fullscreen ? Qt.NoButton : Qt.AllButtons
    hoverEnabled: true
    // The far right and bottom edges count as on the shell too. Hyprland keeps a pointer pushed into
    // them a billionth of a pixel inside (hyprutils' CBox::closestPoint), which Wayland's 1/256 px
    // positions round to the edge itself (x = width, y = height), and Qt counts that as outside: a
    // push there (pushToShow) came as the pointer leaving, worst in the corners
    containmentMask: QtObject {
        function contains(point: point): bool {
            return point.x >= 0 && point.y >= 0 && point.x <= root.width && point.y <= root.height;
        }
    }

    onPressed: event => {
        dragStart = Qt.point(event.x, event.y);
        if (launcherExclusive && overWindows(event.x, event.y))
            pressedOutside();
    }
    onContainsMouseChanged: {
        if (containsMouse) {
            agentTookPointer = false;
        } else {
            stopPush();

            // Only hide if not activated by shortcut
            if (!osdShortcutActive) {
                screenState.osd = false;
                root.panels.osd.hovered = false;
            }

            // A moment later: the pointer can have gone onto the Agent tab's terminal, a surface of its
            // own over the dashboard (services/AgentTerminal.qml), which keeps it open
            if (!dashboardShortcutActive)
                dashboardLeave.restart();

            if (!utilitiesShortcutActive)
                screenState.utilities = false;

            screenState.dock = false;

            if (!popouts.held && (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1)) {
                popouts.hasCurrent = false;
                bar.closeTray();
            }

            if (Config.bar.showOnHover)
                bar.isHovered = false;

            if (Config.sidebar.showOnHover)
                screenState.sidebar = false;
        }
    }

    onPositionChanged: event => {
        cornerPush.stop();
        if (popouts.isDetached)
            return;

        const x = event.x;
        const y = event.y;
        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y);
            return;
        }

        // Show bar in non-exclusive mode on hover
        if (!screenState.bar && Config.bar.showOnHover && x < bar.clampedWidth)
            bar.isHovered = true;

        // Show/hide bar on drag
        if (pressed && dragStart.x < bar.clampedWidth) {
            if (dragX > Config.bar.dragThreshold)
                screenState.bar = true;
            else if (dragX < -Config.bar.dragThreshold)
                screenState.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = Config.sidebar.enabled && pressed && dragStart.x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panels.sidebar.x);

            // Show sidebar on hover (the top-right corner only)
            if (Config.sidebar.enabled && Config.sidebar.showOnHover && !sessionOpen && inSidebarCorner(x, y) && !screenState.sidebar && pushToShow("sidebar", x, y, Config.sidebar.pushTime))
                screenState.sidebar = true;

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > Config.session.dragThreshold)
                    screenState.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.offsetScale <= 0 && dragX < -Config.sidebar.dragThreshold)
                    screenState.sidebar = true;
            } else if (showSidebar && dragX < -Config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                screenState.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            // Show osd on hover
            const showOsd = outOfSidebar && inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > Config.session.dragThreshold)
                    screenState.session = false;
            }

            // Show/hide sidebar on hover
            if (Config.sidebar.showOnHover && !pressed) {
                if (Config.sidebar.enabled && !sessionOpen && inSidebarCorner(x, y) && !screenState.sidebar && pushToShow("sidebar", x, y, Config.sidebar.pushTime)) {
                    screenState.sidebar = true;
                } else {
                    const inSidebarArea = inRightPanel(panels.sidebar, x, y) || inRightPanel(panels.sessionWrapper, x, y);
                    if (!inSidebarArea)
                        screenState.sidebar = false;
                }
            }

            // Hide sidebar on drag
            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
                screenState.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (Config.launcher.showOnHover) {
            if (!screenState.launcher && inBottomPanel(panels.launcher, x, y))
                screenState.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                screenState.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                screenState.launcher = false;
        }

        // Show dashboard on hover: once pushed into the top edge (pushToShow), and then while the
        // pointer is on it
        const showDashboard = Config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y);

        // Always update visibility based on hover if not in shortcut mode
        if (!dashboardShortcutActive) {
            if (showDashboard && !screenState.dashboard) {
                if (!sessionOpen && pushToShow("dashboard", x, y, Config.dashboard.pushTime))
                    screenState.dashboard = true;
            } else {
                if (pushPanel === "dashboard")
                    stopPush();
                screenState.dashboard = showDashboard;
            }
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
        if (pressed && inTopPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            if (dragY > Config.dashboard.dragThreshold)
                screenState.dashboard = true;
            else if (dragY < -Config.dashboard.dragThreshold)
                screenState.dashboard = false;
        }

        // Show the dock while the pointer is at the bottom edge under it, or on it
        // (once pushed into the bottom edge: pushToShow)
        const onDock = inBottomPanel(panels.dock, x, y);
        if (onDock && !screenState.dock && Dock.enabled) {
            if (pushToShow("dock", x, y, Dock.pushTime))
                screenState.dock = true;
        } else {
            if (pushPanel === "dock")
                stopPush();
            screenState.dock = onDock;
        }

        // Show utilities on hover (from the bottom-right corner, then while on it)
        // (once pushed into the corner: pushToShow)
        const inUtilities = inUtilitiesCorner(x, y);
        const showUtilities = (screenState.utilities && (inUtilities || inBottomPanel(panels.utilities, x, y, true))) || (inUtilities && (!Config.utilities.enabled || pushToShow("utilities", x, y, Config.utilities.pushTime)));

        // Always update visibility based on hover if not in shortcut mode
        if (!utilitiesShortcutActive) {
            screenState.utilities = showUtilities;
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Show popouts on hover
        if (x < bar.implicitWidth) {
            bar.checkPopout(y);
        } else if (!popouts.held && (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !inLeftPanel(panels.popoutsWrapper, x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    // A push into a corner going on with nothing arriving (pushToShow): where the pointer is, from
    // Hyprland (cornerPointer), says whether it's still being pushed. Back in the corner it's another
    // touch there; anywhere else the push is over.
    Timer {
        id: cornerPush

        property int time

        // With the answer, inside pushToShow's 0.1 s between touches
        interval: 40
        onTriggered: {
            if (root.pushPanel === "sidebar" && root.sessionOpen)
                root.stopPush();
            else if (!cornerPointer.running)
                cornerPointer.running = true;
        }
    }

    Process {
        id: cornerPointer

        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const panel = root.pushPanel;
                if (!panel)
                    return;
                const top = panel === "sidebar";
                let pos = null;
                try {
                    pos = JSON.parse(text);
                } catch (e) {}
                const x = (pos?.x ?? -1) - root.screen.x;
                const y = (pos?.y ?? -1) - root.screen.y;
                if (x < root.width - 1 || (top ? y > 0 : y < root.height - 1)) {
                    root.stopPush();
                } else if (root.pushToShow(panel, root.width, top ? 0 : root.height, cornerPush.time)) {
                    if (top)
                        root.screenState.sidebar = true;
                    else
                        root.screenState.utilities = true;
                }
            }
        }
    }

    // The dashboard closes once the pointer has left the shell (onContainsMouseChanged), unless it
    // went onto the Agent tab's terminal, which is part of the dashboard
    Timer {
        id: dashboardLeave

        interval: 50
        onTriggered: {
            if (!root.containsMouse && !AgentTerminal.hovered && !root.agentTookPointer && !root.dashboardShortcutActive)
                root.screenState.dashboard = false;
        }
    }

    Connections {
        function onVisibleChanged() {
            root.agentTookPointer = AgentTerminal.surface.visible && AgentTerminal.screen === root.screen;
        }

        target: AgentTerminal.surface
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            // If launcher is hidden, clear shortcut flags for dashboard and OSD
            if (!root.screenState.launcher) {
                // The dock stayed up for the app drawer: it goes too unless the pointer is on it
                root.screenState.dock = root.containsMouse && root.inBottomPanel(root.panels.dock, root.mouseX, root.mouseY);

                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);

                if (!inDashboardArea) {
                    root.screenState.dashboard = false;
                }
                if (!inOsdArea) {
                    root.screenState.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.screenState.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.screenState.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.screenState.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        target: root.screenState
    }
}
