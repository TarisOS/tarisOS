// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Monitors, changed the way the Witcher's Tweaks settings change them: drag them into place,
// pick resolution, scale, rotation and mirroring, then Apply. Applied changes revert by themselves
// after 15 seconds unless kept (then they're saved to hypr-settings.lua), even with Settings closed
// (HyprSettings keeps the countdown). Also brightness and night light.
PageBase {
    id: root

    property var saved: [] // Monitors as Hyprland has them
    property var edits: [] // The same, with your changes
    property int picked: 0
    property bool changed
    readonly property int keepSeconds: HyprSettings.trialSeconds
    readonly property var current: edits[picked] ?? null

    function load(): void {
        monitorsProc.running = true;
    }

    function edit(key: string, value: var): void {
        const list = JSON.parse(JSON.stringify(edits));
        list[picked][key] = value;
        edits = list;
        changed = JSON.stringify(edits) !== JSON.stringify(saved);
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
                    list.sort((a, b) => (a.x - b.x) || (a.y - b.y));
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
                    model: root.edits

                    StyledRect {
                        id: screenBox

                        required property var modelData
                        required property int index
                        readonly property var size: root.logical(modelData)
                        readonly property bool isPicked: index === root.picked

                        visible: !modelData.disabled
                        width: size.w * arrangement.ratio
                        height: size.h * arrangement.ratio
                        radius: Tokens.rounding.small
                        color: isPicked ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                        border.width: 1
                        border.color: isPicked ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                        // Placed from the monitor's position, except while it's dragged
                        Binding on x {
                            when: !dragArea.drag.active
                            value: arrangement.ox + (screenBox.modelData.x - arrangement.bounds.x) * arrangement.ratio
                        }

                        Binding on y {
                            when: !dragArea.drag.active
                            value: arrangement.oy + (screenBox.modelData.y - arrangement.bounds.y) * arrangement.ratio
                        }

                        StyledText {
                            anchors.centerIn: parent
                            width: parent.width - Tokens.padding.small * 2
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: `${screenBox.index + 1}  ${screenBox.modelData.description}`
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
                                if (!drag.active && root.edits.length <= 1)
                                    return;
                                // Back to desktop coordinates, snapped to the other screens' edges
                                let nx = Math.round((screenBox.x - arrangement.ox) / arrangement.ratio + arrangement.bounds.x);
                                let ny = Math.round((screenBox.y - arrangement.oy) / arrangement.ratio + arrangement.bounds.y);
                                const snap = 60;
                                for (let i = 0; i < root.edits.length; i++) {
                                    const o = root.edits[i];
                                    if (i === screenBox.index || o.disabled)
                                        continue;
                                    const ol = root.logical(o);
                                    for (const e of [o.x - screenBox.size.w, o.x + ol.w, o.x, o.x + ol.w - screenBox.size.w])
                                        if (Math.abs(nx - e) < snap)
                                            nx = e;
                                    for (const e of [o.y - screenBox.size.h, o.y + ol.h, o.y, o.y + ol.h - screenBox.size.h])
                                        if (Math.abs(ny - e) < snap)
                                            ny = e;
                                }
                                const list = JSON.parse(JSON.stringify(root.edits));
                                list[screenBox.index].x = nx;
                                list[screenBox.index].y = ny;
                                root.edits = list;
                                root.changed = JSON.stringify(root.edits) !== JSON.stringify(root.saved);
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
            model: Brightness.monitors

            RangeRow {
                id: brightnessRow

                required property var modelData
                required property int index

                first: index === 0
                icon: "brightness_6"
                label: Brightness.monitors.length > 1 ? Tr.tr("Brightness · %1").arg(modelData.modelData.name) : Tr.tr("Brightness")
                from: 1
                to: 100
                step: 1
                current: Math.round(modelData.brightness * 100)
                format: v => `${Math.round(v)}%`
                onCommitted: v => brightnessRow.modelData.setBrightness(v / 100)
            }
        }

        ToggleRow {
            first: Brightness.monitors.length === 0
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
