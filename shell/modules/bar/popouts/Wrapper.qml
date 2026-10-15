// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QMLTermWidget
import Taris.Config
import qs.components
import qs.components.filedialog
import qs.services
import qs.modules.kdeconnect
import qs.modules.nexus
import qs.modules.store
import qs.modules.windowinfo

Item {
    id: root

    required property ShellScreen screen
    required property real offsetScale

    readonly property alias content: content
    readonly property alias winfo: winfo
    readonly property alias nexus: nexus

    readonly property real nonAnimWidth: children.find(c => c.shouldBeActive)?.implicitWidth ?? content.implicitWidth
    readonly property real nonAnimHeight: children.find(c => c.shouldBeActive)?.implicitHeight ?? content.implicitHeight
    readonly property Item current: (content.item as Content)?.current ?? null
    readonly property bool isDetached: detachedMode.length > 0

    property alias currentName: popoutState.currentName
    property alias hasCurrent: popoutState.hasCurrent
    property alias held: popoutState.held
    property real currentCenter

    property string detachedMode
    property string queuedMode
    // A FileDialog shown here (detachedMode "file"), and what was showing before it (the settings,
    // when it was opened from them), which comes back when it's done
    property var fileDialog: null
    property string modeBeforeFile
    // A command run in a terminal here (detachedMode "terminal": the Updates page's update, the app
    // drawer's Remove…), and its title; it closes when the command ends. While the command runs,
    // nothing else closes or replaces it: that would end the command partway (a package transaction
    // included). Ctrl+C or Escape cancel the command, which closes it; once it has ended, clicking
    // away closes it too.
    property string terminalCommand
    property string terminalTitle
    property bool terminalRunning

    // Dummy object so Tokens attached prop resolves to global config
    // Anim configs are not per-monitor
    readonly property QtObject dummy: QtObject {}
    property int animLength: dummy.Tokens.anim.durations.expressiveDefaultSpatial
    property var animCurve: dummy.Tokens.anim.expressiveDefaultSpatial // The easingCurve type is Qt 6.11+ so we gotta use var for now

    // The terminal is gone (closed, or this screen's shell went away with it)
    signal terminalClosed

    function setAnims(detach: bool): void {
        const type = `expressive${detach ? "Slow" : "Default"}Spatial`;
        animLength = dummy.Tokens.anim.durations[type];
        animCurve = dummy.Tokens.anim[type];
    }

    function detach(mode: string): void {
        if (terminalRunning)
            return;
        setAnims(true);
        if (mode === "winfo" || mode === "store" || mode === "kdeconnect") {
            detachedMode = mode;
        } else {
            queuedMode = mode;
            detachedMode = "any";
        }
        setAnims(false);
        focus = true;
    }

    // reason: what closed it, logged while the settings overlay is open (to find what closes it)
    function close(reason: string): void {
        if (terminalRunning) {
            console.info(`Detached popout (terminal) kept open while its command runs: ${reason || "unknown"}`);
            return;
        }
        if (isDetached)
            console.info(`Detached popout (${detachedMode}) closed: ${reason || "unknown"}`);
        const dialog = detachedMode === "file" ? fileDialog : null;
        const wasTerminal = detachedMode === "terminal";
        fileDialog = null;
        modeBeforeFile = "";
        hasCurrent = false;
        detachedMode = "";
        dialog?.rejected(); // Closing the overlay cancels the pick
        if (wasTerminal)
            terminalClosed();
    }

    // False when another command is still running here, or its terminal is still fading out (it
    // would come back instead of a new one)
    function showTerminal(title: string, command: string): bool {
        if (terminalRunning || terminalComp.item)
            return false;
        terminalRunning = true;
        terminalTitle = title;
        terminalCommand = command;
        // Focus here first: the terminal made below takes it from here, and setting it afterwards
        // would take it back from the terminal (typing, a sudo password included, then went
        // nowhere, and Escape closed the overlay)
        focus = true;
        setAnims(true);
        detachedMode = "terminal";
        setAnims(false);
        return true;
    }

    // False while a terminal's command runs here (the dialog then shows as a window)
    function showFileDialog(dialog: var): bool {
        if (terminalRunning)
            return false;
        if (fileDialog && fileDialog !== dialog)
            fileDialog.rejected();
        if (detachedMode !== "file")
            modeBeforeFile = detachedMode;
        fileDialog = dialog;
        setAnims(true);
        detachedMode = "file";
        setAnims(false);
        focus = true;
        return true;
    }

    // The dialog picked or was cancelled: back to what was showing before it
    function closeFileDialog(dialog: var): void {
        if (fileDialog !== dialog)
            return;
        fileDialog = null;
        if (detachedMode === "file") {
            detachedMode = modeBeforeFile;
            if (!detachedMode)
                hasCurrent = false;
        }
        modeBeforeFile = "";
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    focus: hasCurrent
    Keys.onEscapePressed: {
        // Forward escape to password popout if active, otherwise close
        if (currentName === "wirelesspassword" && content.item) {
            const passwordPopout = (content.item as Content)?.children.find(c => c.name === "wirelesspassword");
            if (passwordPopout && passwordPopout.item) {
                passwordPopout.item.closeDialog();
                return;
            }
        }
        // The terminal cancels its command (and closes once it has ended) even when the keyboard
        // has slipped from it to here
        if (detachedMode === "terminal" && terminalComp.item) {
            terminalComp.item.cancel();
            return;
        }
        close("escape");
    }

    Keys.onPressed: event => {
        // Don't intercept keys when password popout is active - let it handle them
        if (currentName === "wirelesspassword") {
            event.accepted = false;
        }
    }

    Component.onDestruction: {
        if (detachedMode === "terminal")
            terminalClosed();
    }

    PopoutState {
        id: popoutState

        onDetachRequested: mode => root.detach(mode)
    }

    HyprlandFocusGrab {
        id: detachedGrab

        // Briefly off to take the grab again when it's dropped without the user clicking away: after
        // a reload the shell asked for (Window style changes), or while the pointer is on the
        // overlay itself (clicking its colour picker drops it)
        property bool regrabbing

        // Off while a password prompt or the screenshot area picker is up (ShellState.grabsReleased):
        // it gets the clicks and the keyboard, and the overlay stays open under it
        active: root.isDetached && !regrabbing && !ShellState.grabsReleased
        windows: [QsWindow.window]
        onCleared: {
            if (root.terminalRunning || Hypr.reloading() || detachedHover.hovered || fileDialogHover.hovered || terminalHover.hovered || storeHover.hovered || connectHover.hovered) {
                regrabbing = true;
                Qt.callLater(() => regrabbing = false);
            } else {
                root.close("focus grab cleared");
            }
        }
    }

    Binding {
        when: root.isDetached || (root.hasCurrent && root.currentName === "wirelesspassword")

        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }

    Comp {
        id: content

        shouldBeActive: root.hasCurrent && !root.detachedMode
        anchors.fill: parent

        sourceComponent: Content {
            screen: root.screen
            popouts: popoutState
        }
    }

    Comp {
        id: winfo

        shouldBeActive: root.detachedMode === "winfo"
        anchors.centerIn: parent

        sourceComponent: WindowInfo {
            screen: root.screen
            client: Hypr.activeToplevel
        }
    }

    Comp {
        id: terminalComp

        shouldBeActive: root.detachedMode === "terminal"
        anchors.centerIn: parent

        sourceComponent: StyledClippingRect {
            id: terminalBox

            // Ctrl+C, as the user would type it: the command gets the interrupt
            function cancel(): void {
                terminalSession.sendText("\x03");
            }

            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainerLowest
            implicitWidth: 760
            implicitHeight: 420

            StyledText {
                id: titleText

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Tokens.padding.large
                text: root.terminalTitle
                font: Tokens.font.title.small
                elide: Text.ElideRight
            }

            QMLTermWidget {
                id: terminal

                anchors.top: titleText.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Tokens.padding.large

                font.family: "CaskaydiaCove NF"
                font.pixelSize: 13
                colorScheme: "Taris"
                blinkingCursor: true
                enableBold: true
                antialiasText: true
                smooth: true
                focus: true
                // Escape cancels, as Ctrl+C does
                Keys.onEscapePressed: terminalBox.cancel()

                session: QMLTermSession {
                    id: terminalSession

                    initialWorkingDirectory: Quickshell.env("HOME")
                    shellProgram: "bash"
                    // The title it sets once the command has ended tells the overlay it may close.
                    // Ctrl+C (and Escape) cancel: the command gets the interrupt and bash then exits
                    // normally, as the session never reports a bash killed by a signal as finished
                    // and the overlay would stay. Ctrl+Z is ignored: it would stop the command for
                    // good, with nothing here to resume it.
                    shellProgramArgs: ["-c", `trap 'exit 0' INT QUIT TERM HUP; trap '' TSTP; ${root.terminalCommand}; printf '\\e]2;taris-done\\a\\nDone. Press Enter to close.'; read -r`]
                    onTitleChanged: {
                        if (title === "taris-done")
                            root.terminalRunning = false;
                    }
                    onFinished: {
                        root.terminalRunning = false;
                        root.close("terminal finished");
                    }
                }

                Component.onCompleted: {
                    terminalSession.startShellProgram();
                    forceActiveFocus();
                    // Again once whatever opened it is done (it may set the focus as it goes)
                    Qt.callLater(() => terminal.forceActiveFocus());
                }

                // A click in it gives it the keyboard back
                TapHandler {
                    onTapped: terminal.forceActiveFocus()
                }
            }
        }

        HoverHandler {
            id: terminalHover
        }
    }

    Comp {
        id: fileDialogComp

        shouldBeActive: root.detachedMode === "file"
        anchors.centerIn: parent

        sourceComponent: StyledClippingRect {
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surface
            implicitWidth: Math.min(1000, (QsWindow.window as QsWindow)?.width * 0.8 || 1000)
            implicitHeight: Math.min(600, (QsWindow.window as QsWindow)?.height * 0.8 || 600)

            DialogContent {
                anchors.fill: parent
                loader: root.fileDialog
            }
        }

        HoverHandler {
            id: fileDialogHover
        }
    }

    Comp {
        id: nexus

        shouldBeActive: root.detachedMode === "any"
        anchors.centerIn: parent

        sourceComponent: StyledClippingRect {
            radius: Tokens.rounding.extraLarge
            implicitWidth: nexusInner.implicitWidth
            implicitHeight: nexusInner.implicitHeight

            Nexus {
                id: nexusInner

                anchors.fill: parent
                nState.screen: root.screen
                nState.animatingContainer: nexus.opacity < 1
                // The page whose id is the mode ("bluetooth", "audio"...), else the default one
                nState.currentPageIdx: PageRegistry.indexOf(root.queuedMode)
                onClose: root.close("closed from settings")
                Component.onDestruction: console.info(`Detached settings destroyed (detachedMode "${root.detachedMode}")`)
            }
        }

        HoverHandler {
            id: detachedHover
        }
    }

    // The Store (modules/store), the same way: its corner button turns it into a window
    Comp {
        id: store

        shouldBeActive: root.detachedMode === "store"
        anchors.centerIn: parent

        sourceComponent: StyledClippingRect {
            radius: Tokens.rounding.extraLarge
            implicitWidth: storeInner.implicitWidth
            implicitHeight: storeInner.implicitHeight

            Store {
                id: storeInner

                anchors.fill: parent
                sState.screen: root.screen
                sState.animatingContainer: store.opacity < 1
                onClose: root.close("closed from the Store")
            }
        }

        HoverHandler {
            id: storeHover
        }
    }

    // KDE Connect (modules/kdeconnect), the same way
    Comp {
        id: kdeconnect

        shouldBeActive: root.detachedMode === "kdeconnect"
        anchors.centerIn: parent

        sourceComponent: StyledClippingRect {
            radius: Tokens.rounding.extraLarge
            implicitWidth: connectInner.implicitWidth
            implicitHeight: connectInner.implicitHeight

            ConnectView {
                id: connectInner

                anchors.fill: parent
                cState.screen: root.screen
                cState.animatingContainer: kdeconnect.opacity < 1
                onClose: root.close("closed from KDE Connect")
            }
        }

        HoverHandler {
            id: connectHover
        }
    }

    Behavior on implicitWidth {
        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }

    Behavior on implicitHeight {
        enabled: root.offsetScale < 1

        Anim {
            duration: root.animLength
            easing: root.animCurve
        }
    }

    component Comp: Loader {
        id: comp

        property bool shouldBeActive

        active: false
        opacity: 0

        // Makes the loader load on the same frame shouldBeActive becomes true, which ensures size is set
        states: State {
            name: "active"
            when: comp.shouldBeActive

            PropertyChanges {
                comp.opacity: 1
                comp.active: true
            }
        }

        transitions: [
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                }
            },
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        type: Anim.DefaultEffects
                        property: "opacity"
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            }
        ]
    }
}
