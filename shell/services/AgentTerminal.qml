// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QMLTermWidget
import Taris.Config
import qs.components
import qs.utils

// The agent's terminal, running the default agent through assets/agent/launch.sh, shown in the
// dashboard's Agent tab and in the agent workspace (special:agent, SUPER + A): one terminal and
// one session, which moves to whichever of the two is in use while the other shows its last
// picture. It lives as long as either is turned on: the dashboard unloads its content whenever
// it closes, and a terminal there would hang up the agent (and anything it started, like a
// sign-in browser) every time. Turning both off, or Quit, ends the session.
//
// In the tab it's drawn on a surface of its own, laid over the tab's terminal frame while the tab
// is shown and still (showAt, hide): an agent working redraws only it, at its size, rather than
// the shell's whole screen and everything Hyprland blurs behind the shell (about 1.5 W while an
// agent printed). While it's hidden (the dashboard opening or closing, a tab sliding in) the tab
// shows its last picture. In the workspace it's a window of the shell's (the title Hypr's
// agentWindowTitle, which taris.lua puts on the agent workspace), made when SUPER + A first shows
// it and gone when the session ends or the workspace is turned off.
Singleton {
    id: root

    readonly property Item terminal: loader.item
    readonly property PanelWindow surface: surface
    property bool running
    // The agent the running session started with
    property string sessionAgent
    // The pointer is on the terminal (the dashboard stays open while it is: modules/drawers)
    readonly property bool hovered: surface.visible && hover.hovered
    // Its picture when it last left the tab (ItemGrabResult), for the tab to show meanwhile
    property var snapshot: null
    // Its picture when it last left the workspace's window, for the window to show meanwhile
    property var windowSnapshot: null

    // Where the tab's frame is (the drawers window is the whole screen: its coordinates are the
    // screen's), and whether the terminal shows there
    property ShellScreen screen: null
    property rect area: Qt.rect(0, 0, 700, 360)
    property bool placed

    // The Agent tab is turned on (on any screen the shell is on; the global setting while there's
    // none, so screens coming and going don't end the session), and the agent workspace (Settings >
    // Panels > Taskbar > Workspaces)
    readonly property bool tabEnabled: Screens.screens.length > 0 ? Screens.screens.some(s => GlobalConfig.forScreen(Screens.configOf(s.name)).dashboard.showAgent) : GlobalConfig.dashboard.showAgent
    readonly property bool workspaceEnabled: GlobalConfig.bar.workspaces.agentWorkspace
    // The session's wanted and may run; Quit keeps it from starting again until Start
    property bool wanted
    property bool stopped
    property bool schemeReady
    // SUPER + A asked for the workspace's window; it's there while the session runs
    property bool windowWanted
    readonly property bool windowShown: windowWanted && workspaceEnabled && running && !!terminal
    // The terminal is in the workspace's window (not in the tab, or hidden on the tab's surface)
    readonly property bool inWindow: windowShown && !placed

    function showAt(onScreen: ShellScreen, rect: rect): void {
        hideTimer.stop();
        if (placeTimer.running)
            return;
        if (placed && root.screen === onScreen && area.x === rect.x && area.y === rect.y && area.width === rect.width && area.height === rect.height)
            return;
        root.screen = onScreen;
        area = rect;
        if (placed)
            return;
        // Leaving the workspace's window: its picture first, so the window has it while the
        // terminal is in the tab (the grab happens at the window's next frame); there within
        // placeTimer's wait whatever happens to the grab
        placeTimer.start();
        const dpr = agentWindow.screen?.devicePixelRatio ?? 1;
        const grabbing = inWindow && !!terminal && terminal.grabToImage(r => {
            root.windowSnapshot = r;
            if (placeTimer.running) {
                placeTimer.stop();
                root.placed = true;
            }
        }, Qt.size(terminal.width * dpr, terminal.height * dpr));
        if (!grabbing) {
            placeTimer.stop();
            placed = true;
        }
    }

    // Its picture first, so the tab has it while the surface is gone (the grab happens at the next
    // frame); gone within hideTimer's wait whatever happens to the grab
    function hide(): void {
        placeTimer.stop();
        if (!placed || hideTimer.running)
            return;
        hideTimer.start();
        const dpr = screen?.devicePixelRatio ?? 1;
        const grabbing = surface.visible && !!terminal && terminal.grabToImage(r => {
            root.snapshot = r;
            if (hideTimer.running) {
                hideTimer.stop();
                root.placed = false;
            }
        }, Qt.size(terminal.width * dpr, terminal.height * dpr));
        if (!grabbing) {
            hideTimer.stop();
            placed = false;
        }
    }

    // The agent's screen drawn as it is now (qmltermwidget-taris draws all of it, not only what
    // changed)
    function repaint(): void {
        if (!terminal)
            return;
        if (typeof terminal.updateImage === "function")
            terminal.updateImage();
        terminal.update();
    }

    // Arrived where it's shown: the keyboard for it, and the agent's screen as it is now, at once
    // and again as the new surface comes up (repaintTimer). The terminal only redraws when the agent
    // prints, and a surface shown again is a new one, which a redraw asked for before it's up never
    // reaches: an idle agent's screen stayed blank until something was typed
    function refresh(): void {
        if (!terminal)
            return;
        terminal.forceActiveFocus();
        repaint();
        repaintTimer.left = 3;
        repaintTimer.restart();
    }

    // Starts the session the first time the tab is shown (not after Quit: Start does then)
    function start(): void {
        if (!stopped)
            wanted = true;
    }

    function restart(): void {
        stopped = false;
        wanted = true;
        loader.active = false;
        loader.active = Qt.binding(() => root.wanted && root.schemeReady && (root.tabEnabled || root.workspaceEnabled));
    }

    // Quit: ends the session (the terminal hangs up the agent as it goes), in the tab and the
    // workspace
    function quit(): void {
        stopped = true;
        end();
    }

    function end(): void {
        wanted = false;
        windowWanted = false;
        running = false;
        sessionAgent = "";
        snapshot = null;
        windowSnapshot = null;
    }

    // SUPER + A: shows or hides the agent workspace, starting the agent first when it isn't running
    function toggleWorkspace(): void {
        if (!workspaceEnabled)
            return;
        if (windowShown) {
            Hypr.toggleAgent();
            return;
        }
        if (!running || !terminal)
            restart();
        // Opens on the agent workspace, shown (taris.lua)
        windowWanted = true;
    }

    onTabEnabledChanged: {
        if (!tabEnabled && !workspaceEnabled)
            end();
    }
    onWorkspaceEnabledChanged: {
        if (workspaceEnabled)
            return;
        windowWanted = false;
        if (!tabEnabled)
            end();
    }
    // The agent exited: the workspace's window goes, and comes back with SUPER + A
    onRunningChanged: {
        if (!running)
            windowWanted = false;
    }
    // Once it's in the window
    onInWindowChanged: {
        if (inWindow)
            Qt.callLater(refresh);
    }

    // The shell's terminals' colours (this one's and the overlay terminal's), from Taris's scheme:
    // Taris.colorscheme in the account's own folder for them, which qmltermwidget-taris looks in.
    // Written from the shell's start (ServiceLoader), as the overlay terminal can come first. It
    // looks schemes up once, so the terminal starts only once the file is written, and new colours
    // apply when the shell restarts.
    FileView {
        readonly property string scheme: {
            const p = Colours.palette;
            const rgb = c => `${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)}`;
            let out = `[General]\nDescription=Taris\nOpacity=1\n\n`;
            out += `[Background]\nColor=${rgb(p.m3surfaceContainerLowest)}\n\n[BackgroundIntense]\nColor=${rgb(p.m3surfaceContainerLowest)}\n\n`;
            out += `[Foreground]\nColor=${rgb(p.m3onSurface)}\n\n[ForegroundIntense]\nColor=${rgb(p.m3onSurface)}\n\n`;
            for (let i = 0; i < 8; i++)
                out += `[Color${i}]\nColor=${rgb(p[`term${i}`])}\n\n[Color${i}Intense]\nColor=${rgb(p[`term${i + 8}`])}\n\n`;
            return out;
        }

        path: `${Paths.state}/terminal/Taris.colorscheme`
        printErrors: false
        onSchemeChanged: setText(scheme)
        onSaved: root.schemeReady = true
        onSaveFailed: root.schemeReady = true
        Component.onCompleted: setText(scheme)
    }

    Timer {
        id: hideTimer

        interval: 150
        onTriggered: root.placed = false
    }

    Timer {
        id: placeTimer

        interval: 150
        onTriggered: root.placed = true
    }

    Timer {
        id: repaintTimer

        property int left

        interval: 100
        repeat: true
        onTriggered: {
            root.repaint();
            if (--left <= 0)
                stop();
        }
    }

    PanelWindow {
        id: surface

        // Over the shell's panels, on their layer (the Overlay one over a fullscreen app); never over
        // a dialog (Settings, the Store), which covers the dashboard; not while the agent has exited,
        // so the tab's "exited" text shows
        readonly property var drawers: root.screen ? ShellState.componentsFor(root.screen)?.rootWindow ?? null : null
        readonly property var popouts: root.screen ? ShellState.componentsFor(root.screen)?.panels?.popouts ?? null : null

        screen: root.screen
        visible: root.placed && root.running && !!root.terminal && !popouts?.isDetached
        anchors.top: true
        anchors.left: true
        margins.left: root.area.x
        margins.top: root.area.y
        // The terminal keeps this size while it's hidden, so the agent's screen doesn't reflow
        implicitWidth: Math.max(1, root.area.width)
        implicitHeight: Math.max(1, root.area.height)
        color: Colours.palette.m3surfaceContainerLowest
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "taris-agent"
        WlrLayershell.layer: drawers?.WlrLayershell.layer ?? WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        onVisibleChanged: {
            if (visible)
                root.refresh();
        }

        HoverHandler {
            id: hover
        }
    }

    FloatingWindow {
        id: agentWindow

        visible: root.windowShown
        title: Hypr.agentWindowTitle
        color: Colours.palette.m3surfaceContainerLowest
        implicitWidth: 1000
        implicitHeight: 700

        // While the terminal is in the tab
        Image {
            anchors.fill: parent
            visible: !root.inWindow && !!root.windowSnapshot
            source: root.windowSnapshot?.url ?? ""
            fillMode: Image.Stretch
            smooth: true
        }
    }

    // What the terminal is in: the workspace's window, or the tab's surface (hidden there when
    // neither shows it)
    Item {
        parent: root.inWindow ? agentWindow.contentItem : surface.contentItem
        anchors.fill: parent

        Loader {
            id: loader

            anchors.fill: parent
            active: root.wanted && root.schemeReady && (root.tabEnabled || root.workspaceEnabled)

            sourceComponent: QMLTermWidget {
                id: terminal

                font.family: "CaskaydiaCove NF"
                // Same size as the Witcher's Tweaks agent terminal
                font.pixelSize: 12
                colorScheme: "Taris"
                // A blink redraws the terminal twice a second (agents draw their own cursor anyway)
                blinkingCursor: false
                enableBold: true
                antialiasText: true
                smooth: true
                focus: true

                session: QMLTermSession {
                    id: agentSession

                    initialWorkingDirectory: Quickshell.env("HOME")
                    shellProgram: `${Agents.scriptDir}/launch.sh`
                    shellProgramArgs: [Agents.defaultAgent]
                    // Not a session restarted away from, which can end after the new one started
                    onFinished: {
                        if (root.terminal !== terminal)
                            return;
                        root.running = false;
                        root.sessionAgent = "";
                    }
                }

                Component.onCompleted: {
                    root.sessionAgent = Agents.defaultAgent;
                    agentSession.startShellProgram();
                    root.running = true;
                }

                // The terminal renders scrollback itself; the wheel scrolls it
                QMLTermScrollbar {
                    terminal: terminal
                    width: 6

                    StyledRect {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colours.palette.m3onSurfaceVariant
                        opacity: 0.35
                    }
                }
            }
        }
    }
}
