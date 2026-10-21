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
import qs.services
import qs.modules.nexus.common

// Monitors, changed the way the Witcher's Tweaks settings change them: drag them into place,
// pick resolution, scale, rotation and mirroring, then Apply. Applied changes revert by themselves
// after 15 seconds unless kept (then they're saved to hypr-settings.lua), even with Settings closed
// (HyprSettings keeps the countdown). A dropped display snaps to the side of the nearest one,
// lined up with its start, centre or end; the others make room for it and close the gaps, so
// displays never overlap (Hyprland warns when they do). Also which display is the main one, which
// have the shell, their numbers shown on them, brightness and night light.
PageBase {
    id: root

    property var saved: [] // Monitors as Hyprland has them
    property var edits: [] // The same, with your changes
    property int picked: 0
    property bool changed
    property bool identifying
    readonly property int keepSeconds: HyprSettings.trialSeconds
    readonly property var current: edits[picked] ?? null
    readonly property var dimmable: Brightness.monitors.filter(m => m.controllable)

    property Timer _timer3: Timer {
        id: identifyTimer

        interval: 3000
        onTriggered: root.identifying = false
    }

    // Each display's number on it while identifying: on top of everything, never taking the
    // keyboard, clicks going through
    property Variants _variants4: Variants {
        model: root.identifying ? Screens.ordered : []

        StyledWindow {
            id: numberWin

            required property ShellScreen modelData

            screen: modelData
            name: "identify"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            mask: Region {}

            anchors.top: true
            anchors.left: true
            margins.top: 24
            margins.left: 24
            implicitWidth: 120
            implicitHeight: 120

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.large
                color: Colours.palette.m3primaryContainer
                border.width: 4
                border.color: Colours.palette.m3primary

                StyledText {
                    anchors.centerIn: parent
                    text: String(Screens.numberOf(numberWin.modelData.name))
                    color: Colours.palette.m3onPrimaryContainer
                    font: Tokens.font.body.builders.large.size(64).weight(Font.Bold).build()
                }
            }
        }
    }

    // A display plugged in, unplugged or back under another output name: read them again, or the
    // boxes keep the old names, and their numbers and saved positions go to the wrong monitors
    property Connections _connections5: Connections {
        function onKeysChanged(): void {
            reloadTimer.restart();
        }

        target: Screens
    }

    function load(): void {
        monitorsProc.running = true;
    }

    function setEdits(list: var): void {
        edits = list;
        changed = JSON.stringify(edits) !== JSON.stringify(saved);
    }

    function edit(key: string, value: var): void {
        const list = JSON.parse(JSON.stringify(edits));
        list[picked][key] = value;
        settle(list, picked, rectOf(edits[picked]));
        setEdits(list);
    }

    // Shown and not mirroring another: these take room on the desktop and must never overlap
    function placed(m: var): bool {
        return !m.disabled && !m.mirror;
    }

    function rectOf(m: var): var {
        const l = logical(m);
        return {
            x: m.x,
            y: m.y,
            w: l.w,
            h: l.h
        };
    }

    function overlap(a: var, b: var): bool {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
    }

    function anyOverlap(list: var): bool {
        for (let i = 0; i < list.length; i++)
            for (let j = i + 1; j < list.length; j++)
                if (placed(list[i]) && placed(list[j]) && overlap(rectOf(list[i]), rectOf(list[j])))
                    return true;
        return false;
    }

    // Along the side two displays share: lined up with the other's start, centre or end when
    // within snap of it, else where it was dropped, the side still partly shared
    function alongSide(raw: real, start: int, length: int, size: int, snap: real): int {
        let pos = raw;
        let nearest = snap;
        for (const target of [start, Math.round(start + (length - size) / 2), start + length - size]) {
            if (Math.abs(raw - target) < nearest) {
                pos = target;
                nearest = Math.abs(raw - target);
            }
        }
        return Math.round(Math.max(start - size + 1, Math.min(start + length - 1, pos)));
    }

    // Moves every display overlapping list[from] out of its way along axis ("x" or "y") in
    // direction sign (1 or -1), and the ones those then overlap, leaving list[fixed] where it is
    function pushFrom(list: var, from: int, axis: string, sign: int, fixed: int): void {
        const size = axis === "x" ? "w" : "h";
        const queue = [from];
        for (let n = 0; queue.length > 0 && n < 100; n++) {
            const pusher = queue.shift();
            const p = rectOf(list[pusher]);
            for (let i = 0; i < list.length; i++) {
                if (i === pusher || i === fixed || !placed(list[i]))
                    continue;
                const r = rectOf(list[i]);
                if (!overlap(p, r))
                    continue;
                list[i][axis] = sign > 0 ? p[axis] + p[size] : p[axis] - r[size];
                queue.push(i);
            }
        }
    }

    // Closes every gap that runs across the whole desktop, so displays that touched still do
    function closeGaps(list: var): void {
        for (const [axis, size] of [["x", "w"], ["y", "h"]]) {
            const order = list.map((m, i) => i).filter(i => placed(list[i])).sort((a, b) => list[a][axis] - list[b][axis]);
            let end = null;
            let shift = 0;
            for (const i of order) {
                let start = list[i][axis] - shift;
                if (end !== null && start > end) {
                    shift += start - end;
                    start = end;
                }
                list[i][axis] = start;
                end = Math.max(end ?? start, start + rectOf(list[i])[size]);
            }
        }
    }

    // After list[index] changed size, went off or came back (before: its place until then): the
    // displays it now overlaps move out the way they were from it (beside, above, below), else
    // along the side they're least far into, then the gaps close
    function settle(list: var, index: int, before: var): void {
        if (placed(list[index])) {
            const p = rectOf(list[index]);
            for (let i = 0; i < list.length; i++) {
                if (i === index || !placed(list[i]))
                    continue;
                const r = rectOf(list[i]);
                if (!overlap(p, r))
                    continue;
                let axis;
                let sign;
                if (r.x >= before.x + before.w || r.x + r.w <= before.x) {
                    axis = "x";
                    sign = r.x >= before.x + before.w ? 1 : -1;
                } else if (r.y >= before.y + before.h || r.y + r.h <= before.y) {
                    axis = "y";
                    sign = r.y >= before.y + before.h ? 1 : -1;
                } else {
                    const dx = Math.min(p.x + p.w - r.x, r.x + r.w - p.x);
                    const dy = Math.min(p.y + p.h - r.y, r.y + r.h - p.y);
                    axis = dx < dy ? "x" : "y";
                    sign = axis === "x" ? (r.x + r.w / 2 >= p.x + p.w / 2 ? 1 : -1) : (r.y + r.h / 2 >= p.y + p.h / 2 ? 1 : -1);
                }
                const size = axis === "x" ? "w" : "h";
                list[i][axis] = sign > 0 ? p[axis] + p[size] : p[axis] - r[size];
                pushFrom(list, i, axis, sign, index);
            }
        }
        closeGaps(list);
    }

    // The picked display dropped at (rawX, rawY) on the desktop: against the side of the display
    // nearest to there, the ones in its way moved along. Kept only when nothing overlaps
    function dropAt(index: int, rawX: real, rawY: real, snap: real): void {
        const list = JSON.parse(JSON.stringify(edits));
        const d = rectOf(list[index]);
        let best = null;
        if (placed(list[index])) {
            for (let i = 0; i < list.length; i++) {
                if (i === index || !placed(list[i]))
                    continue;
                const o = rectOf(list[i]);
                const sides = [
                    {
                        axis: "x",
                        sign: -1,
                        x: o.x - d.w,
                        y: alongSide(rawY, o.y, o.h, d.h, snap)
                    },
                    {
                        axis: "x",
                        sign: 1,
                        x: o.x + o.w,
                        y: alongSide(rawY, o.y, o.h, d.h, snap)
                    },
                    {
                        axis: "y",
                        sign: -1,
                        x: alongSide(rawX, o.x, o.w, d.w, snap),
                        y: o.y - d.h
                    },
                    {
                        axis: "y",
                        sign: 1,
                        x: alongSide(rawX, o.x, o.w, d.w, snap),
                        y: o.y + o.h
                    }
                ];
                for (const side of sides) {
                    const dist = Math.hypot(side.x - rawX, side.y - rawY);
                    if (!best || dist < best.dist)
                        best = Object.assign({
                            dist
                        }, side);
                }
            }
        }
        if (best) {
            list[index].x = best.x;
            list[index].y = best.y;
            pushFrom(list, index, best.axis, best.sign, index);
            closeGaps(list);
        } else {
            list[index].x = Math.round(rawX);
            list[index].y = Math.round(rawY);
        }
        // Back where it was otherwise
        setEdits(anyOverlap(list) ? JSON.parse(JSON.stringify(edits)) : list);
    }

    // The Settings overlay is on a display about to lose the shell (and the overlay with it): it
    // opens on the main display first
    function keepSettingsOpen(losing: string, main: string): void {
        if (root.nState.isWindow || root.nState.screen?.name !== losing)
            return;
        const screen = Quickshell.screens.find(s => s.name === main);
        if (screen)
            ShellState.componentsFor(screen)?.panels?.popouts.detach("displays");
    }

    // A monitor's size on the desktop (rotation and scale applied)
    function logical(m: var): var {
        const res = String(m.mode).split("@")[0].split("x");
        let w = Number(res[0]) || m.width;
        let h = Number(res[1]) || m.height;
        if (m.transform % 2 === 1)
            [w, h] = [h, w];
        const s = Number(m.scale) || 1;
        return {
            w: Math.round(w / s),
            h: Math.round(h / s)
        };
    }

    function settingsFor(list: var): var {
        const out = {};
        for (const m of list)
            out[m.name] = {
                mode: m.mode,
                position: `${m.x}x${m.y}`,
                scale: m.scale,
                transform: m.transform,
                mirror: m.mirror,
                disabled: m.disabled
            };
        return out;
    }

    function apply(): void {
        HyprSettings.tryMonitors(settingsFor(edits), settingsFor(saved));
    }

    title: Tr.tr("Displays")

    // The tried-out monitors were kept or went back
    onKeepSecondsChanged: {
        if (keepSeconds === 0)
            reloadTimer.restart();
    }
    Component.onCompleted: load()

    property Process _process1: Process {
        id: monitorsProc

        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text).map(m => ({
                                name: m.name,
                                description: `${m.make ?? ""} ${m.model ?? ""}`.trim() || m.name,
                                modes: [...new Set((m.availableModes ?? []).map(x => {
                                            const [res, hz] = String(x).replace(/Hz$/, "").split("@");
                                            return `${res}@${Number(hz).toFixed(2)}`;
                                        }))],
                                mode: `${m.width}x${m.height}@${Number(m.refreshRate).toFixed(2)}`,
                                width: m.width,
                                height: m.height,
                                x: m.x,
                                y: m.y,
                                scale: Number(Number(m.scale).toFixed(6)),
                                transform: m.transform % 4,
                                mirror: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "",
                                disabled: m.disabled === true
                            }));
                    // In the order displays are numbered everywhere (Screens.ordered, by monitor),
                    // so a display keeps its number and stays picked, the displays that are off after
                    list.sort((a, b) => (a.disabled - b.disabled) || (Screens.numberOf(a.name) - Screens.numberOf(b.name)) || a.name.localeCompare(b.name));
                    root.saved = JSON.parse(JSON.stringify(list));
                    root.edits = list;
                    root.changed = false;
                    if (root.picked >= list.length)
                        root.picked = 0;
                } catch (e) {
                    console.warn("Displays: couldn't read monitors:", e);
                }
            }
        }
    }

    // Hyprland reports the new layout a moment after applying it
    property Timer _timer2: Timer {
        id: reloadTimer

        interval: 500
        onTriggered: root.load()
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---------- Arrangement ----------
        SectionHeader {
            first: true
            text: Tr.tr("Arrangement")
        }

        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: 220

            Item {
                id: arrangement

                readonly property var bounds: {
                    let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
                    for (const m of root.edits) {
                        if (m.disabled)
                            continue;
                        const l = root.logical(m);
                        minX = Math.min(minX, m.x);
                        minY = Math.min(minY, m.y);
                        maxX = Math.max(maxX, m.x + l.w);
                        maxY = Math.max(maxY, m.y + l.h);
                    }
                    return minX > maxX ? {
                        x: 0,
                        y: 0,
                        w: 1,
                        h: 1
                    } : {
                        x: minX,
                        y: minY,
                        w: maxX - minX,
                        h: maxY - minY
                    };
                }
                readonly property real ratio: Math.min((width - 40) / bounds.w, (height - 40) / bounds.h)
                readonly property real ox: (width - bounds.w * ratio) / 2
                readonly property real oy: (height - bounds.h * ratio) / 2

                anchors.fill: parent
                anchors.margins: Tokens.padding.large

                Repeater {
                    // By count, so the boxes stay and slide when the layout changes
                    model: root.edits.length

                    StyledRect {
                        id: screenBox

                        required property int index
                        readonly property var modelData: root.edits[index] ?? ({})
                        readonly property var size: root.logical(modelData)
                        readonly property bool isPicked: index === root.picked

                        visible: !modelData.disabled
                        width: size.w * arrangement.ratio
                        height: size.h * arrangement.ratio
                        radius: Tokens.rounding.small
                        color: isPicked ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                        border.width: 1
                        border.color: isPicked ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                        // Placed from the monitor's position, except while it's held. Nothing is put
                        // back when it's picked up (the default would put back where the box was before
                        // it was placed, and it would jump there)
                        Binding on x {
                            when: !dragArea.pressed
                            restoreMode: Binding.RestoreNone
                            value: arrangement.ox + (screenBox.modelData.x - arrangement.bounds.x) * arrangement.ratio
                        }

                        Binding on y {
                            when: !dragArea.pressed
                            restoreMode: Binding.RestoreNone
                            value: arrangement.oy + (screenBox.modelData.y - arrangement.bounds.y) * arrangement.ratio
                        }

                        // Sliding into place once let go, never while held
                        Behavior on x {
                            enabled: !dragArea.pressed

                            Anim {
                                type: Anim.DefaultSpatial
                            }
                        }

                        Behavior on y {
                            enabled: !dragArea.pressed

                            Anim {
                                type: Anim.DefaultSpatial
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            width: parent.width - Tokens.padding.small * 2
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: `${Screens.numberOf(screenBox.modelData.name) || screenBox.index + 1}  ${screenBox.modelData.description}`
                            color: screenBox.isPicked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                            font: Tokens.font.label.medium
                        }

                        MouseArea {
                            id: dragArea

                            anchors.fill: parent
                            cursorShape: root.edits.length > 1 ? Qt.OpenHandCursor : Qt.PointingHandCursor
                            drag.target: root.edits.length > 1 ? screenBox : null
                            onPressed: root.picked = screenBox.index
                            onReleased: {
                                if (!drag.active || root.edits.length <= 1)
                                    return;
                                // Back to desktop coordinates; lining up snaps within 6 px here
                                const rawX = (screenBox.x - arrangement.ox) / arrangement.ratio + arrangement.bounds.x;
                                const rawY = (screenBox.y - arrangement.oy) / arrangement.ratio + arrangement.bounds.y;
                                root.dropAt(screenBox.index, rawX, rawY, 6 / arrangement.ratio);
                            }
                        }
                    }
                }
            }
        }

        TextButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.small
            visible: root.edits.length > 1
            type: TextButton.Tonal
            text: Tr.tr("Identify")
            onClicked: {
                root.identifying = true;
                identifyTimer.restart();
            }
        }

        // ---------- Main display and the shell ----------
        SegmentedRow {
            Layout.topMargin: Tokens.spacing.small
            visible: Screens.ordered.length > 1
            first: true
            label: Tr.tr("Main display")
            options: Screens.ordered.map(s => ({
                        value: s.name,
                        label: String(Screens.numberOf(s.name))
                    }))
            current: Screens.mainName
            onChosen: v => {
                const old = Screens.mainName;
                if (!GlobalConfig.forScreen(Screens.configOf(old)).enabled)
                    root.keepSettingsOpen(old, v);
                Qt.callLater(() => HyprSettings.setMainDisplay(v));
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: Screens.ordered.length > 1
            last: true
            implicitHeight: taskbarRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: taskbarRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.large

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Show taskbar on")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                Repeater {
                    model: Screens.ordered

                    RowLayout {
                        id: taskbarToggle

                        required property ShellScreen modelData
                        readonly property bool isMain: modelData.name === Screens.mainName

                        spacing: Tokens.spacing.small

                        StyledText {
                            text: String(Screens.numberOf(taskbarToggle.modelData.name))
                            font: Tokens.font.body.small
                        }

                        StyledSwitch {
                            cLayer: 2
                            checked: taskbarToggle.isMain || GlobalConfig.forScreen(Screens.configOf(taskbarToggle.modelData.name)).enabled
                            disabled: taskbarToggle.isMain
                            onToggled: {
                                const name = taskbarToggle.modelData.name;
                                const on = checked;
                                if (!on)
                                    root.keepSettingsOpen(name, Screens.mainName);
                                Qt.callLater(() => GlobalConfig.forScreen(Screens.configOf(name)).enabled = on);
                            }
                        }
                    }
                }
            }
        }

        // ---------- Keep or revert ----------
        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: root.keepSeconds > 0
            implicitHeight: keepRow.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3primaryContainer

            RowLayout {
                id: keepRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Keep these display settings? Reverting in %1 s").arg(root.keepSeconds)
                    color: Colours.palette.m3onPrimaryContainer
                    wrapMode: Text.WordWrap
                }

                TextButton {
                    type: TextButton.Tonal
                    text: Tr.tr("Revert")
                    onClicked: HyprSettings.revertTrial()
                }

                TextButton {
                    text: Tr.tr("Keep")
                    onClicked: HyprSettings.keepTrial()
                }
            }
        }

        // ---------- The picked monitor ----------
        SectionHeader {
            visible: root.current !== null
            text: root.current ? `${root.picked + 1}. ${root.current.description}` : ""
        }

        ToggleRow {
            visible: root.current !== null && root.edits.length > 1
            first: true
            text: Tr.tr("Use this display")
            checked: !(root.current?.disabled ?? false)
            onToggled: root.edit("disabled", !checked)
        }

        ChoiceRow {
            visible: root.current !== null
            first: root.edits.length <= 1
            label: Tr.tr("Resolution")
            options: (root.current?.modes ?? []).map(m => {
                const [res, hz] = m.split("@");
                return {
                    value: m,
                    label: `${res.replace("x", " × ")}  ·  ${Number(hz).toFixed(0)} Hz`
                };
            })
            current: root.current?.mode
            searchable: false
            onChosen: v => root.edit("mode", v)
        }

        ChoiceRow {
            visible: root.current !== null
            label: Tr.tr("Scale")
            options: [1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.5, 3].map(s => ({
                        value: s,
                        label: `${Math.round(s * 100)}%`
                    }))
            current: [1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.5, 3].find(s => Math.abs(s - (root.current?.scale ?? 1)) < 0.01) ?? root.current?.scale
            onChosen: v => root.edit("scale", v)
        }

        SegmentedRow {
            visible: root.current !== null
            last: root.edits.length <= 1
            label: Tr.tr("Rotation")
            options: [
                {
                    value: 0,
                    label: Tr.tr("Standard")
                },
                {
                    value: 1,
                    label: "90°"
                },
                {
                    value: 2,
                    label: "180°"
                },
                {
                    value: 3,
                    label: "270°"
                }
            ]
            current: root.current?.transform ?? 0
            onChosen: v => root.edit("transform", v)
        }

        ChoiceRow {
            visible: root.current !== null && root.edits.length > 1
            last: true
            label: Tr.tr("Mirror")
            options: [
                {
                    value: "",
                    label: Tr.tr("Don't mirror")
                }
            ].concat(root.edits.filter((m, i) => i !== root.picked).map(m => ({
                        value: m.name,
                        label: Tr.tr("Mirror %1").arg(m.description)
                    })))
            current: root.current?.mirror ?? ""
            onChosen: v => root.edit("mirror", v)
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.small
            visible: root.current !== null
            spacing: Tokens.spacing.small

            StyledText {
                visible: root.changed
                text: Tr.tr("Not applied")
                color: Colours.palette.m3outline
                font: Tokens.font.label.medium
            }

            TextButton {
                type: TextButton.Tonal
                text: Tr.tr("Undo")
                enabled: root.changed
                onClicked: root.load()
            }

            TextButton {
                text: Tr.tr("Apply")
                enabled: root.changed && root.keepSeconds === 0
                onClicked: root.apply()
            }
        }

        // ---------- Brightness and color ----------
        SectionHeader {
            text: Tr.tr("Brightness and color")
        }

        Repeater {
            // Only the displays whose brightness can be set
            model: root.dimmable

            RangeRow {
                id: brightnessRow

                required property var modelData
                required property int index

                first: index === 0
                icon: "brightness_6"
                label: root.dimmable.length > 1 ? Tr.tr("Brightness · %1").arg(modelData.modelData.name) : Tr.tr("Brightness")
                from: 1
                to: 100
                step: 1
                current: Math.round(modelData.brightness * 100)
                format: v => `${Math.round(v)}%`
                onCommitted: v => brightnessRow.modelData.setBrightness(v / 100)
            }
        }

        ToggleRow {
            visible: Brightness.sensorPath !== "" && Brightness.panel !== null
            text: Tr.tr("Automatic brightness")
            subtext: Tr.tr("Follows the room's light, from where you set it")
            checked: GlobalConfig.services.autoBrightness
            onToggled: GlobalConfig.services.autoBrightness = checked
        }

        ToggleRow {
            first: root.dimmable.length === 0
            text: Tr.tr("Night light")
            checked: NightLight.enabled
            onToggled: NightLight.setEnabled(checked)
        }

        RangeRow {
            last: true
            icon: "nightlight"
            label: Tr.tr("Night light warmth")
            from: 2500
            to: 5500
            step: 100
            current: 8000 - NightLight.warmth
            format: v => `${8000 - Math.round(v)} K`
            onCommitted: v => {
                if (NightLight.enabled)
                    NightLight.setTemperature(8000 - v);
                else
                    NightLight.warmth = 8000 - v;
            }
        }
    }
}
