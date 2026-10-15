// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.components.misc
import qs.services

Scope {
    id: scope

    function start(clipboardOnly: bool): void {
        root.closing = false;
        root.clipboardOnly = clipboardOnly;
        root.activeAsync = true;
    }

    // From the moment it's asked for until it's gone: the shell's focus grabs let go, so the click
    // that picks the area doesn't close the panel or settings being shot
    Binding {
        target: ShellState
        property: "picking"
        value: root.loading || root.active
    }

    LazyLoader {
        id: root

        property bool closing
        property bool clipboardOnly

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "area-picker"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
                mask: root.closing ? empty : null

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Region {
                    id: empty
                }

                Picker {
                    loader: root
                    screen: win.modelData
                }
            }
        }
    }

    // The screen always freezes while picking: the Freeze names stay for the binds and scripts that
    // use them (taris screenshot -r -f)
    IpcHandler {
        function open(): void {
            scope.start(false);
        }

        function openFreeze(): void {
            scope.start(false);
        }

        function openClip(): void {
            scope.start(true);
        }

        function openFreezeClip(): void {
            scope.start(true);
        }

        target: "picker"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshot"
        description: "Open screenshot tool"
        onPressed: scope.start(false)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotFreeze"
        description: "Open screenshot tool"
        onPressed: scope.start(false)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotClip"
        description: "Open screenshot tool (clipboard)"
        onPressed: scope.start(true)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "screenshotFreezeClip"
        description: "Open screenshot tool (clipboard)"
        onPressed: scope.start(true)
    }
}
