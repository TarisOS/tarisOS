// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.misc
import qs.services

// Window overview, ported from the Witcher's Tweaks overview (witcher.overview). On the focused
// screen: along the top, a strip of every workspace as a live miniature of its screen (scrolls
// sideways when there are more than fit); below it, the windows of the workspace the pointer last
// hovered in the strip (the current one to start with) as big live thumbnails. What it shows is a
// snapshot taken on open, so nothing is rebuilt or recaptured while it's up.
//
// Click a workspace to go to it, a window to go to that window (raised above the others when it
// floats), middle click a window to close it. Keys: Left/Right pick a workspace, Tab/Shift+Tab a
// window, Enter goes to the picked window (or the workspace when it's empty), Esc closes; so does
// a click on the backdrop.
// Toggle with the taris:overview shortcut or `taris-qs -c taris ipc call overview toggle`.
Scope {
    id: root

    property bool closing
    // Where to go once the overview is gone: { address } for a window, { workspace } for a workspace
    property var pending: null
    property var landing: null
    // Each window's one live capture (in its strip miniature), by address; the grid shows the same
    // capture, so no window is captured twice
    property var captures: ({})

    property string screenName
    // Every workspace: { id, name, active, box, windows: [{ toplevel, address, title, appClass, x, y, width, height, aspect, floating, focusHistoryID }] }
    property var workspaces: []
    property int selectedWorkspace: 0
    property int selectedWindow: 0
    readonly property var current: workspaces[selectedWorkspace] ?? null
    readonly property var windows: current?.windows ?? []

    readonly property int titleHeight: 28
    readonly property int stripCardWidth: 190

    function open(): void {
        closeTimer.stop();
        goTimer.stop();
        pending = null;
        captures = {};
        screenName = Hypr.focusedMonitor?.name ?? "";
        rebuild();
        selectedWorkspace = Math.max(0, workspaces.findIndex(w => w.active));
        selectedWindow = activeWindowIndex();
        closing = false;
        loader.activeAsync = true;
    }

    function close(): void {
        closing = true;
        closeTimer.restart();
    }

    function toggle(): void {
        if (loader.active && !closing)
            close();
        else
            open();
    }

    // ---------------------------------------------------------------- model

    // A monitor's origin and size in layout coordinates (window positions are in those; the
    // monitor reports physical pixels and a scale)
    function monitorBox(monitor: var): var {
        const scale = monitor?.scale > 0 ? monitor.scale : 1;
        return {
            x: monitor?.x ?? 0,
            y: monitor?.y ?? 0,
            width: monitor?.width > 0 ? monitor.width / scale : 1920,
            height: monitor?.height > 0 ? monitor.height / scale : 1080
        };
    }

    function rebuild(): void {
        const byId = {};
        const list = [];
        for (const ws of Hypr.workspaces.values) {
            // Special workspaces (the scratchpad) stay out, like on screen
            if (!ws || ws.id < 0)
                continue;
            const entry = {
                id: ws.id,
                name: ws.name || String(ws.id),
                active: ws === Hypr.focusedWorkspace,
                box: monitorBox(ws.monitor),
                windows: []
            };
            byId[ws.id] = entry;
            list.push(entry);
        }

        for (const t of Hypr.toplevels.values) {
            const owner = byId[t.workspace?.id];
            if (!owner || Hypr.isToplevelIgnored(t))
                continue;
            const ipc = t.lastIpcObject ?? {};
            const size = ipc.size ?? [16, 10];
            const at = ipc.at ?? [0, 0];
            owner.windows.push({
                toplevel: t,
                address: `0x${t.address}`,
                title: t.title || ipc.title || "",
                appClass: ipc.class ?? "",
                x: at[0],
                y: at[1],
                width: Math.max(1, size[0]),
                height: Math.max(1, size[1]),
                aspect: Math.max(0.2, Math.min(5, size[0] / Math.max(1, size[1]))),
                floating: !!ipc.floating,
                focusHistoryID: ipc.focusHistoryID ?? 0
            });
        }

        list.sort((a, b) => a.id - b.id);
        for (const ws of list)
            ws.windows.sort((a, b) => (a.x - b.x) || (a.y - b.y));
        workspaces = list;
    }

    function activeWindowIndex(): int {
        return Math.max(0, windows.findIndex(w => w.toplevel === Hypr.activeToplevel));
    }

    function selectWorkspace(index: int): void {
        if (index < 0 || index >= workspaces.length || index === selectedWorkspace)
            return;
        selectedWorkspace = index;
        selectedWindow = activeWindowIndex();
    }

    // Lay the picked workspace's windows out in however many rows makes them biggest, keeping their
    // order and aspect ratios; each row is centred. Returns { height, rows: [[window index...]] }.
    function windowGrid(list: var, width: real, height: real, gap: real): var {
        const n = list.length;
        if (n === 0 || width <= 0 || height <= 0)
            return { height: 0, rows: [] };
        let best = { height: 0, rows: [] };
        for (let rowCount = 1; rowCount <= n; rowCount++) {
            const perRow = Math.ceil(n / rowCount);
            const rows = [];
            for (let i = 0; i < n; i += perRow)
                rows.push([...Array(Math.min(n, i + perRow) - i).keys()].map(k => k + i));
            let h = (height - rows.length * titleHeight - (rows.length - 1) * gap) / rows.length;
            for (const row of rows)
                h = Math.min(h, (width - (row.length - 1) * gap) / row.reduce((a, i) => a + list[i].aspect, 0));
            if (h > best.height)
                best = { height: h, rows };
        }
        best.height = Math.floor(Math.min(best.height, height * 0.8));
        return best;
    }

    function closeWindow(entry: var): void {
        const addr = `address:${entry.address}`;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.close({ window = "${addr}" })` : `closewindow ${addr}`);
        // The snapshot doesn't follow Hyprland, so drop it here
        for (const ws of workspaces)
            ws.windows = ws.windows.filter(w => w !== entry);
        workspaces = workspaces.slice();
        selectedWindow = Math.max(0, Math.min(selectedWindow, windows.length - 1));
    }

    // ---------------------------------------------------------------- going somewhere

    function registerCapture(address: string, item: var): void {
        const map = Object.assign({}, captures);
        map[address] = item;
        captures = map;
    }

    function unregisterCapture(address: string, item: var): void {
        if (captures[address] !== item)
            return;
        const map = Object.assign({}, captures);
        delete map[address];
        captures = map;
    }

    // Hyprland undoes focus changes made while the overview is up (releasing its keyboard refocuses
    // the previous window, removing it focuses the window under the cursor), so it goes at once,
    // and Hyprland is told where to go as soon as it reports it gone
    function goTo(target: var): void {
        pending = target;
        closing = true;
        closeTimer.stop();
        loader.active = false;
        goTimer.restart();
    }

    function goWindow(entry: var): void {
        if (entry)
            goTo({ address: entry.address });
    }

    function goWorkspace(ws: var): void {
        if (ws)
            goTo({ workspace: ws.id });
    }

    // Focus, raise and cursor in one batch, from the snapshot: no waiting on Hyprland
    function go(): void {
        goTimer.stop();
        const target = pending;
        pending = null;
        if (!target)
            return;

        const ws = workspaces.find(w => target.address ? w.windows.some(e => e.address === target.address) : w.id === target.workspace);
        // Going to a workspace focuses the window last focused on it
        const entry = target.address ? ws?.windows.find(e => e.address === target.address) : ws?.windows.reduce((a, e) => !a || e.focusHistoryID < a.focusHistoryID ? e : a, null);

        const messages = [];
        if (target.address) {
            const addr = `address:${target.address}`;
            messages.push(Hypr.usingLua ? `dispatch hl.dsp.focus({ window = "${addr}" })` : `dispatch focuswindow ${addr}`);
        } else {
            messages.push(Hypr.usingLua ? `dispatch hl.dsp.focus({ workspace = "${target.workspace}" })` : `dispatch workspace ${target.workspace}`);
        }
        if (entry)
            messages.push(...landMessages(entry, ws.windows, !!target.address));
        Hypr.extras.batchMessage(messages);

        // A layout that moves windows as they take focus (scrolling) leaves the cursor off them;
        // check once things have settled and put it back on
        if (entry) {
            landing = { target, entry };
            settleTimer.restart();
        }
    }

    // Raise a picked floating window above the others, and put the cursor on a part of the window
    // nothing covers, or focus follows the mouse to whichever window is over it. Windows are
    // { address, x, y, width, height, floating }.
    function landMessages(c: var, others: var, raise: bool): list<string> {
        const addr = `address:${c.address}`;
        const messages = [];
        if (raise && c.floating)
            messages.push(Hypr.usingLua ? `dispatch hl.dsp.window.alter_zorder({ window = "${addr}", mode = "top" })` : `dispatch alterzorder top,${addr}`);

        // Floating windows are drawn over tiled ones, whatever their order
        const covers = c.floating ? [] : others.filter(w => w.address !== c.address && w.floating);
        const p = visiblePoint(c, covers);
        messages.push(Hypr.usingLua ? `dispatch hl.dsp.cursor.move({ x = ${p.x}, y = ${p.y} })` : `dispatch movecursor ${p.x} ${p.y}`);
        return messages;
    }

    function settle(landing: var, clients: var): void {
        const rect = w => ({ address: w.address, x: w.at[0], y: w.at[1], width: w.size[0], height: w.size[1], floating: w.floating });
        const target = landing.target;
        const c = target.address ? clients.find(w => w.address === target.address) : clients.find(w => w.focusHistoryID === 0 && w.workspace?.id === target.workspace);
        if (!c?.at || !c.size)
            return;

        const e = landing.entry;
        if (c.address === e.address && c.at[0] === e.x && c.at[1] === e.y && c.size[0] === e.width && c.size[1] === e.height)
            return;
        const others = clients.filter(w => w.mapped && !w.hidden && w.workspace?.id === c.workspace?.id).map(rect);
        Hypr.extras.batchMessage(landMessages(rect(c), others, false));
    }

    // The point of the window nearest its centre that none of covers is over (its centre if all are).
    // Hyprland counts a window's border and its grab area around it as part of it, hence the margin.
    function visiblePoint(c: var, covers: var): var {
        const m = 32;
        const free = (x, y) => !covers.some(w => x >= w.x - m && x < w.x + w.width + m && y >= w.y - m && y < w.y + w.height + m);
        let best = { x: c.x + c.width / 2, y: c.y + c.height / 2, d: Infinity };
        for (let i = 1; i < 20; i++) {
            for (let j = 1; j < 20; j++) {
                const x = c.x + c.width * i / 20;
                const y = c.y + c.height * j / 20;
                const d = (i - 10) * (i - 10) + (j - 10) * (j - 10);
                if (d < best.d && free(x, y))
                    best = { x, y, d };
            }
        }
        return { x: Math.round(best.x), y: Math.round(best.y) };
    }

    Timer {
        id: closeTimer

        interval: Tokens.anim.durations.normal
        onTriggered: loader.active = false
    }

    // Goes should Hyprland never report the overview gone
    Timer {
        id: goTimer

        interval: 150
        onTriggered: root.go()
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "closelayer" && event.data === "taris-overview" && root.pending)
                root.go();
        }

        target: Hyprland
    }

    Timer {
        id: settleTimer

        interval: 150
        onTriggered: clients.running = true
    }

    Process {
        id: clients

        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const target = root.landing;
                root.landing = null;
                try {
                    if (target)
                        root.settle(target, JSON.parse(text));
                } catch (e) {
                    console.warn("Overview: couldn't read clients:", e);
                }
            }
        }
    }

    // ---------------------------------------------------------------- window

    LazyLoader {
        id: loader

        StyledWindow {
            id: win

            property real shown: root.closing ? 0 : 1

            screen: Screens.screens.find(s => s.name === root.screenName) ?? Screens.screens[0]
            name: "overview"
            color: "transparent"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Component.onCompleted: shown = Qt.binding(() => root.closing ? 0 : 1)

            Behavior on shown {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }

            // Dark enough that the windows behind don't compete with the thumbnails
            StyledRect {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3surface, 0.96)
                opacity: win.shown

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Item {
                id: content

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraLarge * 2
                opacity: win.shown
                scale: 0.96 + 0.04 * win.shown
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.close();
                    else if (event.key === Qt.Key_Left)
                        root.selectWorkspace(root.selectedWorkspace - 1);
                    else if (event.key === Qt.Key_Right)
                        root.selectWorkspace(root.selectedWorkspace + 1);
                    else if (event.key === Qt.Key_Tab && root.windows.length > 0)
                        root.selectedWindow = (root.selectedWindow + 1) % root.windows.length;
                    else if (event.key === Qt.Key_Backtab && root.windows.length > 0)
                        root.selectedWindow = (root.selectedWindow - 1 + root.windows.length) % root.windows.length;
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.windows.length > 0)
                            root.goWindow(root.windows[root.selectedWindow]);
                        else
                            root.goWorkspace(root.current);
                    } else
                        return;
                    event.accepted = true;
                }

                // ---------- Workspaces strip ----------
                ListView {
                    id: strip

                    Glide {
                        flickable: strip
                        horizontal: true
                    }

                    readonly property real cardHeight: {
                        const box = root.workspaces[0]?.box;
                        return box ? root.stripCardWidth * box.height / box.width : root.stripCardWidth * 0.625;
                    }
                    readonly property int picked: root.selectedWorkspace

                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Room for the picked card to grow without being clipped
                    leftMargin: Tokens.spacing.small
                    rightMargin: Tokens.spacing.small
                    width: Math.min(parent.width, contentWidth + leftMargin + rightMargin)
                    height: cardHeight + root.titleHeight + Tokens.spacing.small
                    orientation: ListView.Horizontal
                    spacing: Tokens.spacing.large
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Keeps every workspace's miniature (and so its windows' captures) around while scrolled out
                    cacheBuffer: 100000
                    model: root.workspaces

                    onPickedChanged: positionViewAtIndex(picked, ListView.Contain)
                    Component.onCompleted: positionViewAtIndex(picked, ListView.Contain)

                    // A mouse wheel scrolls the strip sideways; touchpads already do
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: event => {
                            const min = -strip.leftMargin;
                            const max = Math.max(min, strip.contentWidth + strip.rightMargin - strip.width);
                            strip.contentX = Math.max(min, Math.min(max, strip.contentX - event.angleDelta.y));
                        }
                    }

                    delegate: Item {
                        id: space

                        required property var modelData
                        required property int index
                        readonly property bool selected: root.selectedWorkspace === index

                        width: root.stripCardWidth
                        height: strip.height

                        StyledClippingRect {
                            id: miniature

                            readonly property real ratio: width / space.modelData.box.width

                            y: Tokens.spacing.small / 2
                            width: parent.width
                            height: strip.cardHeight
                            radius: Tokens.rounding.large
                            color: Colours.tPalette.m3surfaceContainer
                            scale: space.selected ? 1.04 : 1

                            Behavior on scale {
                                Anim {}
                            }

                            // The workspace's windows where they sit on its screen
                            Repeater {
                                model: space.modelData.windows

                                ScreencopyView {
                                    id: miniCapture

                                    required property var modelData

                                    Component.onCompleted: root.registerCapture(modelData.address, miniCapture)
                                    Component.onDestruction: root.unregisterCapture(modelData.address, miniCapture)

                                    // Tiled under floating, floating in focus order (most recent on top)
                                    z: modelData.floating ? 1000 - modelData.focusHistoryID : 0
                                    x: (modelData.x - space.modelData.box.x) * miniature.ratio
                                    y: (modelData.y - space.modelData.box.y) * miniature.ratio
                                    width: modelData.width * miniature.ratio
                                    height: modelData.height * miniature.ratio
                                    captureSource: !root.closing ? (modelData.toplevel?.wayland ?? null) : null
                                    // Live, not a single frame: a one-off capture of a window that isn't
                                    // redrawing (an idle terminal, a file manager) can come back empty
                                    live: !root.closing
                                }
                            }

                            StyledRect {
                                z: 2000
                                anchors.fill: parent
                                radius: miniature.radius
                                color: "transparent"
                                border.width: space.selected ? 2 : 1
                                border.color: space.selected ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, 0.25)
                            }
                        }

                        StyledText {
                            anchors.top: miniature.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: root.titleHeight
                            verticalAlignment: Text.AlignBottom
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            // The workspace you're on is marked with a dot
                            text: (space.modelData.active ? "● " : "") + Tr.tr("Workspace %1").arg(space.modelData.name)
                            color: Colours.palette.m3onSurface
                            opacity: space.selected ? 1 : 0.7
                            font: Tokens.font.label.medium
                        }

                        HoverHandler {
                            onHoveredChanged: {
                                if (hovered)
                                    root.selectWorkspace(space.index);
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goWorkspace(space.modelData)
                        }
                    }
                }

                // ---------- The picked workspace's windows ----------
                Item {
                    id: area

                    readonly property int gap: Tokens.spacing.extraLarge
                    readonly property var grid: root.windowGrid(root.windows, width, height, gap)

                    anchors.top: strip.bottom
                    anchors.topMargin: Tokens.padding.extraLarge * 2
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.windows.length === 0
                        text: root.current ? Tr.tr("No windows on Workspace %1").arg(root.current.name) : Tr.tr("No workspaces")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.title.medium
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: area.gap

                        Repeater {
                            model: area.grid.rows

                            Row {
                                id: gridRow

                                required property var modelData

                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: area.gap

                                Repeater {
                                    model: gridRow.modelData

                                    Item {
                                        id: card

                                        required property int modelData
                                        readonly property var entry: root.windows[modelData]
                                        readonly property bool selected: root.selectedWindow === modelData

                                        width: Math.round(area.grid.height * (entry?.aspect ?? 1))
                                        height: area.grid.height + root.titleHeight

                                        HoverHandler {
                                            onHoveredChanged: {
                                                if (hovered)
                                                    root.selectedWindow = card.modelData;
                                            }
                                        }

                                        StyledClippingRect {
                                            id: frame

                                            width: parent.width
                                            height: area.grid.height
                                            radius: Tokens.rounding.large
                                            color: Colours.tPalette.m3surfaceContainer
                                            scale: card.selected ? 1.03 : 1

                                            Behavior on scale {
                                                Anim {}
                                            }

                                            // The window's capture from its strip miniature, drawn at this size
                                            ShaderEffectSource {
                                                id: capture

                                                readonly property var screencopy: root.captures[card.entry?.address] ?? null

                                                anchors.fill: parent
                                                sourceItem: screencopy
                                                textureSize: Qt.size(Math.ceil(width * win.devicePixelRatio), Math.ceil(height * win.devicePixelRatio))
                                                live: !root.closing
                                                hideSource: false
                                            }

                                            // A window the compositor won't hand over (or hasn't yet) shows its app icon
                                            Image {
                                                visible: !(capture.screencopy?.hasContent ?? false)
                                                anchors.centerIn: parent
                                                width: Math.min(parent.width, parent.height) * 0.4
                                                height: width
                                                sourceSize: Qt.size(width * 2, height * 2)
                                                fillMode: Image.PreserveAspectFit
                                                source: Quickshell.iconPath(DesktopEntries.heuristicLookup(card.entry?.appClass ?? "")?.icon ?? "", "image-missing")
                                            }

                                            StyledRect {
                                                anchors.fill: parent
                                                radius: frame.radius
                                                color: "transparent"
                                                border.width: card.selected ? 3 : 1
                                                border.color: card.selected ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, 0.25)
                                            }
                                        }

                                        StyledText {
                                            anchors.top: frame.bottom
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: root.titleHeight
                                            verticalAlignment: Text.AlignBottom
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: card.entry?.title ?? ""
                                            color: card.selected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                                            opacity: card.selected ? 1 : 0.75
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            onClicked: event => {
                                                if (event.button === Qt.MiddleButton)
                                                    root.closeWindow(card.entry);
                                                else
                                                    root.goWindow(card.entry);
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

    IpcHandler {
        target: "overview"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "overview"
        description: "Toggle window overview"
        onPressed: root.toggle()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "overviewOpen"
        description: "Open window overview"
        onPressed: root.open()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "overviewClose"
        description: "Close window overview"
        onPressed: {
            if (loader.active)
                root.close();
        }
    }
}
