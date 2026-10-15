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
import qs.utils

// The emoji picker (holding Fn, taris:emoji), as macOS's: a search field, every emoji in its
// category (the ones used most first) and the categories along the bottom. Typing searches,
// arrows move, Enter or a click puts the emoji where the keyboard was (wtype, once the app has the
// keyboard back), Esc closes. The emoji are Unicode's own list (assets/emoji.py), read the first
// time it opens. On the focused screen, over everything, in the middle the first time (a Wayland
// app doesn't say where its text cursor is); dragged by its frame, it opens where it was left.
Scope {
    id: root

    // The window only appears once the panels' focus grabs are gone (ShellState.grabsReleased), as
    // the keyboard shortcuts' does (Keybinds.qml)
    property bool grabsGone
    property var groups: []
    // The emoji picked most recently first, kept between sessions (the state folder)
    property list<string> recent: []
    property string query
    property int selected
    // Where it was dragged to (until the session ends); NaN: the middle of the screen
    property real lastX: NaN
    property real lastY: NaN

    readonly property int columns: 9
    readonly property int recentMax: columns * 2
    // Unicode's categories: their icons, and their names here
    readonly property var categoryIcons: ({
            "Smileys & Emotion": "mood",
            "People & Body": "emoji_people",
            "Animals & Nature": "pets",
            "Food & Drink": "restaurant",
            "Travel & Places": "directions_car",
            "Activities": "sports_soccer",
            "Objects": "lightbulb",
            "Symbols": "emoji_symbols",
            "Flags": "flag"
        })
    readonly property var categoryNames: ({
            "Smileys & Emotion": Tr.tr("Smileys & emotion"),
            "People & Body": Tr.tr("People & body"),
            "Animals & Nature": Tr.tr("Animals & nature"),
            "Food & Drink": Tr.tr("Food & drink"),
            "Travel & Places": Tr.tr("Travel & places"),
            "Activities": Tr.tr("Activities"),
            "Objects": Tr.tr("Objects"),
            "Symbols": Tr.tr("Symbols"),
            "Flags": Tr.tr("Flags")
        })

    // The sections shown: the matches while searching, otherwise the ones used most and every
    // category. Each is { title, icon, emojis: [[emoji, name], ...] }
    readonly property var sections: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        if (words.length > 0) {
            const found = [];
            for (const g of groups)
                for (const e of g.emojis)
                    if (words.every(w => e[1].toLowerCase().includes(w)))
                        found.push(e);
            return found.length > 0 ? [
                {
                    title: "",
                    icon: "",
                    emojis: found
                }
            ] : [];
        }
        const list = [];
        if (recent.length > 0) {
            const names = {};
            for (const g of groups)
                for (const e of g.emojis)
                    names[e[0]] = e[1];
            list.push({
                title: Tr.tr("Frequently used"),
                icon: "schedule",
                emojis: recent.filter(e => e in names).map(e => [e, names[e]])
            });
        }
        for (const g of groups)
            list.push({
                title: categoryNames[g.group] ?? g.group,
                icon: categoryIcons[g.group] ?? "category",
                emojis: g.emojis
            });
        return list;
    }

    // The list's rows (a section's title, or up to `columns` emoji) and where each emoji is in them,
    // for the arrows: { rows: [{ title } | { emojis, start }], flat: [[emoji, name]...], rowOf,
    // colOf, headers (each section's title row) }
    readonly property var layout: {
        const rows = [];
        const flat = [];
        const rowOf = [];
        const colOf = [];
        const headers = [];
        for (const s of sections) {
            if (s.title) {
                headers.push(rows.length);
                rows.push({
                    title: s.title
                });
            } else {
                headers.push(rows.length);
            }
            for (let i = 0; i < s.emojis.length; i += columns) {
                const chunk = s.emojis.slice(i, i + columns);
                chunk.forEach((e, c) => {
                    rowOf.push(rows.length);
                    colOf.push(c);
                });
                rows.push({
                    emojis: chunk,
                    start: flat.length
                });
                flat.push(...chunk);
            }
        }
        return {
            rows,
            flat,
            rowOf,
            colOf,
            headers
        };
    }

    function open(): void {
        query = "";
        selected = 0;
        ShellState.emojis = true;
    }

    function close(): void {
        ShellState.emojis = false;
    }

    // Puts the emoji where the keyboard was: the picker closes, and once the app has the keyboard
    // back it's typed there
    function pick(emoji: string): void {
        recent = [emoji, ...recent.filter(e => e !== emoji)].slice(0, recentMax);
        recentFile.setText(recent.join("\n") + "\n");
        close();
        typeTimer.emoji = emoji;
        typeTimer.restart();
    }

    // The emoji in the row above or below, in the same column as near as it goes
    function moveRow(step: int): void {
        const l = layout;
        if (l.flat.length === 0)
            return;
        let r = l.rowOf[selected] + step;
        while (r >= 0 && r < l.rows.length && !l.rows[r].emojis)
            r += step;
        if (r < 0 || r >= l.rows.length)
            return;
        selected = l.rows[r].start + Math.min(l.colOf[selected], l.rows[r].emojis.length - 1);
    }

    function move(step: int): void {
        selected = Math.max(0, Math.min(layout.flat.length - 1, selected + step));
    }

    onQueryChanged: selected = 0

    Connections {
        function onEmojisChanged(): void {
            root.grabsGone = false;
            if (ShellState.emojis) {
                if (root.groups.length === 0)
                    emojiProc.running = true;
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
        name: "emoji"
        description: "Show the emoji picker"
        onPressed: ShellState.emojis ? root.close() : root.open()
    }

    Process {
        id: emojiProc

        command: ["python3", "-I", `${Quickshell.shellDir}/assets/emoji.py`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.groups = JSON.parse(text);
                } catch (e) {
                    root.groups = [];
                }
            }
        }
    }

    FileView {
        id: recentFile

        path: `${Paths.state}/emoji-recent.txt`
        printErrors: false
        onLoaded: root.recent = text().split("\n").filter(e => e).slice(0, root.recentMax)
    }

    Timer {
        id: typeTimer

        property string emoji

        interval: 150
        onTriggered: Quickshell.execDetached(["wtype", "--", emoji])
    }

    Timer {
        id: grabsGoneTimer

        interval: 100
        onTriggered: root.grabsGone = true
    }

    LazyLoader {
        active: ShellState.emojis && root.grabsGone

        StyledWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
            name: "emoji-picker"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // A click outside the picker closes it
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Item {
                id: picker

                readonly property real cell: 34

                width: cell * root.columns + Tokens.padding.large * 2
                height: Math.min(parent.height * 0.8, 400)
                x: isNaN(root.lastX) ? (parent.width - width) / 2 : Math.min(root.lastX, parent.width - width)
                y: isNaN(root.lastY) ? (parent.height - height) / 2 : Math.min(root.lastY, parent.height - height)

                opacity: 0
                scale: 0.9
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                    search.forceActiveFocus();
                }

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

                    anchors.fill: parent
                    radius: Tokens.rounding.large
                    color: Colours.tPalette.m3surface
                }

                // Clicks on the picker stay in it; its frame drags it (kept on the screen)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.ArrowCursor
                    drag.target: picker
                    drag.minimumX: 0
                    drag.minimumY: 0
                    drag.maximumX: win.width - picker.width
                    drag.maximumY: win.height - picker.height
                    drag.onActiveChanged: {
                        if (!drag.active) {
                            root.lastX = picker.x;
                            root.lastY = picker.y;
                        }
                    }
                }

                // The handle: where to take it from
                StyledRect {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: (Tokens.padding.large - height) / 2
                    implicitWidth: 32
                    implicitHeight: 4
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3outlineVariant
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    SearchBar {
                        id: search

                        Layout.fillWidth: true
                        topPadding: Tokens.padding.medium
                        bottomPadding: Tokens.padding.medium
                        placeholderText: Tr.tr("Search")
                        onTextChanged: root.query = text

                        Keys.onPressed: event => {
                            switch (event.key) {
                            case Qt.Key_Escape:
                                root.close();
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                if (root.layout.flat.length > 0)
                                    root.pick(root.layout.flat[root.selected][0]);
                                break;
                            case Qt.Key_Up:
                                root.moveRow(-1);
                                break;
                            case Qt.Key_Down:
                                root.moveRow(1);
                                break;
                            case Qt.Key_Left:
                                root.move(-1);
                                break;
                            case Qt.Key_Right:
                                root.move(1);
                                break;
                            default:
                                return;
                            }
                            event.accepted = true;
                            if (root.layout.flat.length > 0)
                                list.positionViewAtIndex(root.layout.rowOf[root.selected], ListView.Contain);
                        }
                    }

                    StyledListView {
                        id: list

                        // The category the top of the list is in
                        readonly property int section: {
                            const top = indexAt(10, contentY + 10);
                            const headers = root.layout.headers;
                            let s = 0;
                            for (let i = 0; i < headers.length; i++)
                                if (headers[i] <= top)
                                    s = i;
                            return s;
                        }

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.layout.rows

                        StyledScrollBar.vertical: StyledScrollBar {
                            flickable: list
                        }

                        delegate: Loader {
                            id: row

                            required property var modelData

                            width: list.width
                            sourceComponent: modelData.title !== undefined ? titleComp : emojiComp

                            Component {
                                id: titleComp

                                StyledText {
                                    topPadding: Tokens.padding.small
                                    bottomPadding: Tokens.padding.extraSmall
                                    text: row.modelData.title
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.medium
                                }
                            }

                            Component {
                                id: emojiComp

                                Row {
                                    Repeater {
                                        model: row.modelData.emojis

                                        Item {
                                            id: emojiCell

                                            required property var modelData
                                            required property int index
                                            readonly property int flatIndex: row.modelData.start + index

                                            implicitWidth: picker.cell
                                            implicitHeight: picker.cell

                                            StyledRect {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                radius: Tokens.rounding.small
                                                color: Colours.palette.m3secondaryContainer
                                                opacity: emojiCell.flatIndex === root.selected ? 1 : 0
                                            }

                                            StateLayer {
                                                anchors.margins: 2
                                                radius: Tokens.rounding.small
                                                onClicked: root.pick(emojiCell.modelData[0])
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: emojiCell.modelData[0]
                                                font.family: "Noto Color Emoji"
                                                font.pixelSize: 20
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.groups.length > 0 && root.layout.flat.length === 0
                        text: Tr.tr("No results")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.medium
                    }

                    // The categories: a click goes to one
                    RowLayout {
                        Layout.fillWidth: true
                        visible: !root.query
                        spacing: 0

                        Repeater {
                            model: root.sections

                            Item {
                                id: category

                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                implicitHeight: categoryIcon.implicitHeight + Tokens.padding.small * 2

                                StateLayer {
                                    radius: Tokens.rounding.full
                                    onClicked: {
                                        list.positionViewAtIndex(root.layout.headers[category.index], ListView.Beginning);
                                        root.selected = root.layout.rowOf.indexOf(root.layout.headers[category.index] + 1);
                                    }
                                }

                                MaterialIcon {
                                    id: categoryIcon

                                    anchors.centerIn: parent
                                    text: category.modelData.icon
                                    color: list.section === category.index ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                    fill: list.section === category.index ? 1 : 0
                                    fontStyle: Tokens.font.icon.medium
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
