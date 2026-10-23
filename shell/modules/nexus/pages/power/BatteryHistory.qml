// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower
import Taris.Config
import Taris.I18n
import qs.components
import qs.services
import qs.modules.nexus.common

// The battery over the last 24 hours, from upower's own history (read over D-Bus; upower keeps it
// anyway): its level in half-hour bars, the time on the charger shaded with a line and a lightning
// bolt under it, and when it was last charged and to what level, marked with a dot. Read when shown
// and every 5 minutes while shown.
ConnectedRect {
    id: root

    readonly property int spanSeconds: 24 * 3600
    readonly property int barSeconds: 1800
    // Without a sample for this long (asleep, off), a half hour shows no bar
    readonly property int staleSeconds: 3600
    readonly property list<int> chargerStates: [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge]
    readonly property bool onCharger: chargerStates.includes(UPower.displayDevice.state)
    property string devicePath
    property real start
    // One per half hour, oldest first: {level (0-1), charging} or null
    property var bars: []
    // The spans on the charger, in half hours: [{from, to (after the last)}]
    property var chargeRuns: []
    // The last time it came off the charger: {time (s), level (0-1)}, or null
    property var lastCharge: null

    function load(): void {
        if (devicePath === "")
            enumerate.running = true;
        else
            history.running = true;
    }

    // upower's history: [time (s), level (%), state] per change, newest first; unknown samples
    // (state 0, level 0) left out
    function parse(text: string): void {
        let entries;
        try {
            entries = JSON.parse(text).data[0];
        } catch (e) {
            return;
        }
        entries = entries.filter(e => !(e[2] === 0 && e[1] === 0)).sort((a, b) => a[0] - b[0]);
        const now = Date.now() / 1000;
        start = Math.floor((now - spanSeconds) / barSeconds) * barSeconds + barSeconds;
        const chargingState = s => [1, 4, 5].includes(s);

        const result = [];
        let i = 0;
        let held = null;
        for (let b = 0; b < spanSeconds / barSeconds; b++) {
            const from = start + b * barSeconds;
            const to = from + barSeconds;
            let charging = false;
            while (i < entries.length && entries[i][0] < to) {
                held = entries[i];
                if (held[0] >= from && chargingState(held[2]))
                    charging = true;
                i++;
            }
            if (held && to - held[0] <= staleSeconds + barSeconds && from <= now)
                result.push({ level: Math.max(0, Math.min(1, held[1] / 100)), charging: charging || chargingState(held[2]) });
            else
                result.push(null);
        }
        bars = result;
        const runs = [];
        for (let b = 0; b < result.length; b++) {
            if (!result[b]?.charging)
                continue;
            if (runs.length && runs[runs.length - 1].to === b)
                runs[runs.length - 1].to = b + 1;
            else
                runs.push({ from: b, to: b + 1 });
        }
        chargeRuns = runs;

        let last = null;
        for (let k = 1; k < entries.length; k++) {
            if (chargingState(entries[k - 1][2]) && entries[k][2] === 2)
                last = { time: entries[k][0], level: Math.max(entries[k - 1][1], entries[k][1]) / 100 };
        }
        lastCharge = last;
        graph.requestPaint();
    }

    function when(seconds: real): string {
        const date = new Date(seconds * 1000);
        const time = Qt.formatTime(date, Units.twelveHourClock ? "h:mm AP" : "HH:mm");
        const today = new Date();
        const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
        if (date.toDateString() === today.toDateString())
            return Tr.tr("Today, %1").arg(time);
        if (date.toDateString() === yesterday.toDateString())
            return Tr.tr("Yesterday, %1").arg(time);
        return Tr.tr("%1, %2").arg(Qt.formatDate(date, "d MMM")).arg(time);
    }

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    first: true
    last: true

    onVisibleChanged: {
        if (visible)
            load();
    }
    Component.onCompleted: load()

    Timer {
        running: root.visible
        interval: 300000
        repeat: true
        onTriggered: root.load()
    }

    Process {
        id: enumerate

        command: ["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", "EnumerateDevices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.devicePath = JSON.parse(text).data[0].find(p => p.includes("/battery_")) ?? "";
                } catch (e) {
                    root.devicePath = "";
                }
                if (root.devicePath !== "")
                    history.running = true;
            }
        }
    }

    // A week back, so the last charge is found even after a day on battery
    Process {
        id: history

        command: ["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower", root.devicePath, "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", String(7 * 86400), "4000"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        StyledText {
            text: {
                if (UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
                    return Tr.tr("Fully charged");
                if (root.onCharger)
                    return Tr.tr("Charging, %1%").arg(Math.round(UPower.displayDevice.percentage * 100));
                if (root.lastCharge)
                    return Tr.tr("Last charged to %1%").arg(Math.round(root.lastCharge.level * 100));
                return Tr.tr("Battery level");
            }
            font: Tokens.font.title.small
            color: Colours.palette.m3onSurface
        }

        StyledText {
            visible: !root.onCharger && root.lastCharge !== null
            text: root.lastCharge ? root.when(root.lastCharge.time) : ""
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            Item {
                Layout.fillWidth: true
                implicitHeight: Tokens.padding.large * 9 + chargeStrip.implicitHeight + hourLabels.implicitHeight

                // Bars, grid, the charger's shading and the last charge's dot: drawn on the CPU, only
                // when the history or the size or colours change
                Canvas {
                    id: graph

                    readonly property color barColour: Colours.palette.m3primary
                    readonly property color gridColour: Colours.palette.m3outlineVariant
                    readonly property color dotColour: Colours.palette.m3onSurface

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height - chargeStrip.implicitHeight - hourLabels.implicitHeight

                    onBarColourChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const count = root.bars.length;
                        if (count === 0 || width <= 0 || height <= 0)
                            return;
                        const slot = width / count;
                        const gap = Math.max(1, Math.round(slot * 0.2));
                        // On the charger: shaded behind the bars
                        ctx.fillStyle = Qt.alpha(barColour, 0.18);
                        for (const run of root.chargeRuns)
                            ctx.fillRect(run.from * slot, 0, (run.to - run.from) * slot, height);
                        // 0, 50 and 100 %
                        ctx.strokeStyle = gridColour;
                        ctx.lineWidth = 1;
                        for (const f of [0, 0.5, 1]) {
                            const y = Math.round((height - 1) * (1 - f)) + 0.5;
                            ctx.beginPath();
                            ctx.moveTo(0, y);
                            ctx.lineTo(width, y);
                            ctx.stroke();
                        }
                        // Every three hours on the clock
                        for (const mark of hourMarks.model) {
                            const x = Math.round(mark.x * width) + 0.5;
                            ctx.beginPath();
                            ctx.setLineDash([2, 3]);
                            ctx.moveTo(x, 0);
                            ctx.lineTo(x, height);
                            ctx.stroke();
                        }
                        ctx.setLineDash([]);
                        for (let b = 0; b < count; b++) {
                            const bar = root.bars[b];
                            if (!bar)
                                continue;
                            const h = Math.max(1, bar.level * (height - 1));
                            ctx.fillStyle = barColour;
                            ctx.fillRect(b * slot + gap / 2, height - h, slot - gap, h);
                        }
                        const last = root.lastCharge;
                        if (last && last.time >= root.start) {
                            const x = (last.time - root.start) / root.spanSeconds * width;
                            const y = (height - 1) * (1 - last.level);
                            ctx.fillStyle = dotColour;
                            ctx.beginPath();
                            ctx.arc(x, Math.max(4, y), 4, 0, 2 * Math.PI);
                            ctx.fill();
                        }
                    }
                }

                // A line under each span on the charger, with a lightning bolt in its middle
                Item {
                    id: chargeStrip

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: graph.bottom
                    implicitHeight: bolt.implicitHeight

                    MaterialIcon {
                        id: bolt

                        visible: false
                        text: "bolt"
                        fontStyle: Tokens.font.icon.small
                    }

                    Repeater {
                        model: root.chargeRuns

                        Item {
                            id: run

                            required property var modelData
                            readonly property real slot: chargeStrip.width / Math.max(1, root.bars.length)

                            x: run.modelData.from * run.slot
                            width: (run.modelData.to - run.modelData.from) * run.slot
                            height: chargeStrip.height

                            StyledRect {
                                anchors.left: run.left
                                anchors.right: run.right
                                anchors.verticalCenter: run.verticalCenter
                                anchors.leftMargin: Tokens.spacing.extraSmall / 2
                                anchors.rightMargin: Tokens.spacing.extraSmall / 2
                                implicitHeight: Tokens.padding.extraSmall
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3primary
                            }

                            // On the card's colour, so the line stops either side of it
                            StyledRect {
                                anchors.centerIn: run
                                visible: run.width >= runBolt.implicitWidth
                                implicitWidth: runBolt.implicitWidth + Tokens.spacing.extraSmall
                                implicitHeight: runBolt.implicitHeight
                                radius: Tokens.rounding.full
                                color: root.color

                                MaterialIcon {
                                    id: runBolt

                                    anchors.centerIn: parent
                                    text: "bolt"
                                    fill: 1
                                    color: Colours.palette.m3primary
                                    fontStyle: Tokens.font.icon.small
                                }
                            }
                        }
                    }
                }

                // The hour labels under the marks
                Item {
                    id: hourLabels

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    implicitHeight: labelMetrics.height + Tokens.spacing.extraSmall

                    FontMetrics {
                        id: labelMetrics

                        font: Tokens.font.body.small
                    }

                    Repeater {
                        id: hourMarks

                        model: {
                            const marks = [];
                            if (root.start <= 0)
                                return marks;
                            const first = new Date(root.start * 1000);
                            first.setMinutes(0, 0, 0);
                            first.setHours(Math.ceil(first.getHours() / 3) * 3);
                            for (let t = first.getTime() / 1000; t < root.start + root.spanSeconds; t += 3 * 3600) {
                                if (t >= root.start)
                                    marks.push({ x: (t - root.start) / root.spanSeconds, time: t });
                            }
                            return marks;
                        }

                        StyledText {
                            id: hourLabel

                            required property var modelData

                            x: Math.min(hourLabels.width - hourLabel.implicitWidth, Math.max(0, hourLabel.modelData.x * hourLabels.width - hourLabel.implicitWidth / 2))
                            anchors.bottom: hourLabels.bottom
                            text: Qt.formatTime(new Date(hourLabel.modelData.time * 1000), Units.twelveHourClock ? "h AP" : "HH:mm")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }

            // 100, 50 and 0 %, beside the grid lines
            Item {
                id: percentLabels

                Layout.fillHeight: true
                implicitWidth: percentWidth.implicitWidth

                StyledText {
                    id: percentWidth

                    anchors.top: percentLabels.top
                    anchors.topMargin: -percentWidth.height / 2
                    text: "100%"
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    id: halfLabel

                    y: (graph.height - 1) / 2 - halfLabel.height / 2
                    text: "50%"
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    id: emptyLabel

                    y: graph.height - 1 - emptyLabel.height / 2
                    text: "0%"
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
