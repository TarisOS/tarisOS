// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.components.misc
import qs.services

// Every keyboard shortcut (SUPER + K, taris:keybinds): the keys on the left, what they do on the
// right, in two columns. Read from Hyprland as it's bound now (hyprctl binds), from the
// descriptions the binds are given (packaging/hypr, and an account's own user.lua): a bind without
// one isn't listed, nor the Touch Bar's keys, the mouse's or switches. Binds with the same
// description share a row (SUPER + 1–9). Holding Fn (the emoji picker) is Hyprland's config too, but
// not a bind: it's listed last. On the focused screen, over everything, the size, shape
// and colour of Settings.
Scope {
    id: root

    // The window only appears once the panels' focus grabs are gone (ShellState.grabsReleased):
    // Hyprland gives no keyboard focus to a surface outside an active grab, and doesn't hand it over
    // when the grab ends
    property bool grabsGone
    // The grid's cells, row by row across both columns: { kind: "keys", keys: [{ text | sep }] } and
    // { kind: "action", text } (both empty after the last bind)
    property var cells: []

    readonly property var keyNames: ({
            RETURN: "Enter",
            SPACE: "Space",
            TAB: "Tab",
            ESCAPE: "Esc",
            GRAVE: "`",
            COMMA: ",",
            PERIOD: ".",
            PRINT: "Print",
            LEFT: "←",
            RIGHT: "→",
            UP: "↑",
            DOWN: "↓"
        })

    function modifiers(mask: int): var {
        const names = [];
        if (mask & 64)
            names.push("Super");
        if (mask & 4)
            names.push("Ctrl");
        if (mask & 8)
            names.push("Alt");
        if (mask & 1)
            names.push("Shift");
        return names.map(n => ({
                    text: n
                }));
    }

    function keyToken(key: string): var {
        return {
            text: keyNames[key] ?? (key.length === 1 ? key.toUpperCase() : key)
        };
    }

    // The keys of one row: shared modifiers once, then the keys (a run of digits as 1–9). Plain
    // loops: the QML engine has no Array.flatMap.
    function rowKeys(combos: var): var {
        if (combos[0].hold)
            return [
                {
                    text: combos[0].hold
                }
            ];
        const join = groups => {
            const out = [];
            groups.forEach((g, i) => {
                if (i > 0)
                    out.push({
                        sep: "/"
                    });
                out.push(...g);
            });
            return out;
        };
        const unique = tokens => tokens.filter((t, i) => tokens.findIndex(u => u.text === t.text) === i);
        // Arrows in reading order, however they were bound
        const arrows = ["LEFT", "RIGHT", "UP", "DOWN"];
        combos = [...combos].sort((a, b) => (arrows.indexOf(a.key) + 1 || 99) - (arrows.indexOf(b.key) + 1 || 99));
        if (!combos.every(c => c.mods === combos[0].mods))
            return join(combos.map(c => [...modifiers(c.mods), keyToken(c.key)]));

        const digits = combos.map(c => c.key).filter(k => /^[0-9]$/.test(k)).map(Number).sort((a, b) => a - b);
        let keys;
        if (combos.length > 2 && digits.length === combos.length && digits[digits.length - 1] - digits[0] === digits.length - 1)
            keys = [
                {
                    text: `${digits[0]}–${digits[digits.length - 1]}`
                }
            ];
        else
            keys = join(unique(combos.map(c => keyToken(c.key))).map(t => [t]));
        return [...modifiers(combos[0].mods), ...keys];
    }

    function read(json: string): void {
        let binds = [];
        try {
            binds = JSON.parse(json);
        } catch (e) {}
        const rows = [];
        const byAction = {};
        const seen = new Set();
        for (const b of binds) {
            const combo = `${b.modmask}:${b.key}`;
            // Keyboard shortcuts only: not the Touch Bar's keys (XF86…), the mouse's or switches
            const keyboard = !/^(XF86|mouse|switch:)/.test(b.key);
            if (!b.has_description || !keyboard || b.submap || seen.has(combo))
                continue;
            seen.add(combo);
            if (!(b.description in byAction)) {
                byAction[b.description] = [];
                rows.push(b.description);
            }
            byAction[b.description].push({
                mods: b.modmask,
                key: b.key
            });
        }
        rows.push(Tr.tr("Emojis"));
        byAction[Tr.tr("Emojis")] = [
            {
                hold: Tr.tr("Hold Fn")
            }
        ];

        // Two columns: the first half down the left, the rest down the right
        const half = Math.ceil(rows.length / 2);
        const out = [];
        const add = action => out.push({
                kind: "keys",
                keys: action === undefined ? [] : rowKeys(byAction[action])
            }, {
                kind: "action",
                text: action ?? ""
            });
        for (let i = 0; i < half; i++) {
            add(rows[i]);
            add(rows[i + half]);
        }
        cells = out;
    }

    Connections {
        function onKeybindsChanged(): void {
            root.grabsGone = false;
            if (ShellState.keybinds) {
                bindsProc.running = true;
                grabsGoneTimer.restart();
            } else {
                grabsGoneTimer.stop();
            }
        }

        target: ShellState
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "keybinds"
        description: "Show every keyboard shortcut"
        onPressed: ShellState.keybinds = !ShellState.keybinds
    }

    Process {
        id: bindsProc

        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: root.read(text)
        }
    }

    Timer {
        id: grabsGoneTimer

        interval: 100
        onTriggered: root.grabsGone = true
    }

    LazyLoader {
        active: ShellState.keybinds && root.grabsGone

        StyledWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
            name: "keybinds"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            StyledRect {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3scrim, 0.5)
                opacity: dialog.opacity
            }

            // A click outside the dialog closes it
            MouseArea {
                anchors.fill: parent
                onClicked: ShellState.keybinds = false
            }

            Item {
                id: dialog

                // Settings' size (modules/nexus/Nexus.qml)
                anchors.centerIn: parent
                width: Math.round(height * Tokens.sizes.nexus.ratio)
                height: Math.round(parent.height * Tokens.sizes.nexus.heightMult)

                focus: true
                opacity: 0
                scale: 0.9
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                    forceActiveFocus();
                }

                Keys.onEscapePressed: ShellState.keybinds = false

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Behavior on scale {
                    Anim {}
                }

                Elevation {
                    anchors.fill: parent
                    radius: bg.radius
                    level: 4
                }

                StyledRect {
                    id: bg

                    // As Settings is drawn (modules/drawers/ContentWindow.qml's dialog background)
                    anchors.fill: parent
                    radius: Tokens.rounding.extraLarge
                    color: Colours.tPalette.m3surface
                }

                // Clicks on the dialog stay in it
                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.large

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        StyledRect {
                            implicitWidth: implicitHeight
                            implicitHeight: titleIcon.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3secondaryContainer

                            MaterialIcon {
                                id: titleIcon

                                anchors.centerIn: parent
                                text: "keyboard"
                                color: Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.medium
                                fill: 1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Tr.tr("Keyboard shortcuts")
                            font: Tokens.font.title.builders.medium.weight(Font.Normal).build()
                        }
                    }

                    StyledFlickable {
                        id: list

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: grid.implicitHeight
                        clip: true

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: list
                        }

                        // Keys and action, twice across
                        GridLayout {
                            id: grid

                            width: list.width
                            height: implicitHeight
                            columns: 4
                            columnSpacing: Tokens.spacing.extraLarge
                            rowSpacing: Tokens.spacing.medium

                            Repeater {
                                model: root.cells

                                Loader {
                                    id: cell

                                    required property var modelData

                                    // The two action columns share what the keys leave, equally
                                    Layout.fillWidth: modelData.kind === "action"
                                    Layout.preferredWidth: modelData.kind === "action" ? 1 : -1
                                    Layout.alignment: Qt.AlignVCenter
                                    sourceComponent: modelData.kind === "keys" ? keysComp : actionComp

                                    Component {
                                        id: keysComp

                                        Row {
                                            spacing: Tokens.spacing.extraSmall

                                            Repeater {
                                                model: cell.modelData.keys

                                                Loader {
                                                    id: token

                                                    required property var modelData

                                                    anchors.verticalCenter: parent.verticalCenter
                                                    sourceComponent: modelData.sep ? sepComp : keyComp

                                                    Component {
                                                        id: sepComp

                                                        StyledText {
                                                            text: token.modelData.sep
                                                            color: Colours.palette.m3outline
                                                            font: Tokens.font.label.medium
                                                        }
                                                    }

                                                    Component {
                                                        id: keyComp

                                                        StyledRect {
                                                            implicitWidth: Math.max(implicitHeight, keyText.implicitWidth + Tokens.padding.medium * 2)
                                                            implicitHeight: keyText.implicitHeight + Tokens.padding.small * 2
                                                            radius: Tokens.rounding.small
                                                            color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                                                            StyledText {
                                                                id: keyText

                                                                anchors.centerIn: parent
                                                                text: token.modelData.text
                                                                font: Tokens.font.label.medium
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Component {
                                        id: actionComp

                                        StyledText {
                                            text: cell.modelData.text
                                            color: Colours.palette.m3onSurfaceVariant
                                            font: Tokens.font.body.medium
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
