// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Taris.Config
import qs.components.misc
import qs.utils

Singleton {
    id: root

    property list<var> ddcMonitors: []
    readonly property var ddcMonitorMap: {
        const map = {};
        for (const m of ddcMonitors)
            map[m.connector] = m;
        return map;
    }
    readonly property list<Monitor> monitors: variants.instances // qmllint disable incompatible-type
    property bool appleDisplayPresent: false
    // Automatic brightness, for the laptop's own panel: the light sensor's reading on a curve, with
    // the user's own changes kept as an offset from it, so the panel follows the light from where
    // they put it
    readonly property Monitor panel: monitors.find(m => m.isPanel) ?? null
    property string sensorPath
    readonly property bool autoBrightness: GlobalConfig.services.autoBrightness && sensorPath !== "" && panel !== null
    // The level for a reading (lux), set by eye on a MacBook Pro's panel in a dark room, at half light
    // and with the room's light on; in between on the light's logarithm, past the last at its level
    readonly property list<var> curve: [[0, 0.2], [3, 0.8], [14, 1]]
    // The light now: the middle of the last three readings, so a flicker doesn't move the panel
    property real lux: NaN
    property list<real> readings: []

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.modelData === screen); // qmllint disable missing-property
    }

    function getMonitor(query: string): var {
        if (query === "active") {
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.focused); // qmllint disable missing-property
        }

        if (query.startsWith("model:")) {
            const model = query.slice(6);
            return monitors.find(m => m.modelData.model === model); // qmllint disable missing-property
        }

        if (query.startsWith("serial:")) {
            const serial = query.slice(7);
            return monitors.find(m => m.modelData.serialNumber === serial); // qmllint disable missing-property
        }

        if (query.startsWith("id:")) {
            const id = parseInt(query.slice(3), 10);
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.id === id); // qmllint disable missing-property
        }

        return monitors.find(m => m.modelData.name === query); // qmllint disable missing-property
    }

    function levelFor(reading: real): real {
        const x = Math.log10(1 + Math.max(0, reading));
        let prevX = Math.log10(1 + curve[0][0]);
        let prevLevel = curve[0][1];
        if (x <= prevX)
            return prevLevel;
        for (const [pointLux, level] of curve.slice(1)) {
            const pointX = Math.log10(1 + pointLux);
            if (x <= pointX)
                return prevLevel + (level - prevLevel) * (x - prevX) / (pointX - prevX);
            prevX = pointX;
            prevLevel = level;
        }
        return prevLevel;
    }

    // Never off: the dimmest the Settings slider goes
    function autoLevel(): real {
        return Math.max(0.01, Math.min(1, levelFor(lux) + adapter.offset));
    }

    // The user set the panel to this: kept as the offset from the curve
    function keepOffset(value: real): void {
        if (autoBrightness && !isNaN(lux))
            adapter.offset = value - levelFor(lux);
    }

    function addReading(value: real): void {
        if (isNaN(value))
            return;
        const last = readings.slice(-2);
        last.push(value);
        readings = last;
        lux = [...last].sort((a, b) => a - b)[Math.floor(last.length / 2)];
        if (!autoBrightness)
            return;
        const target = autoLevel();
        // Small moves are left alone: the sensor reports whole lux
        if (Math.abs(target - panel.brightness) >= 0.03)
            panel.rampTo(target);
    }

    function increaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
    }

    function decreaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
    }

    onAutoBrightnessChanged: {
        if (!autoBrightness)
            panel?.rampTimer.stop();
    }

    onMonitorsChanged: {
        ddcMonitors = [];
        ddcProc.running = true;
    }

    Variants {
        id: variants

        model: Quickshell.screens // Don't respect excluded screens cause ipc

        Monitor {}
    }

    Process {
        running: true
        command: ["sh", "-c", "asdbctl get"] // To avoid warnings if asdbctl is not installed
        stdout: StdioCollector {
            onStreamFinished: root.appleDisplayPresent = text.trim().length > 0
        }
    }

    // The first light sensor (the panel's, on a MacBook)
    Process {
        running: true
        command: ["sh", "-c", "ls /sys/bus/iio/devices/*/in_illuminance_input 2>/dev/null | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: root.sensorPath = text.trim()
        }
    }

    FileView {
        id: sensor

        path: root.sensorPath
        onLoaded: root.addReading(parseFloat(text()))
    }

    // Read every second while automatic brightness is on
    Timer {
        running: root.autoBrightness
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: sensor.reload()
    }

    FileView {
        path: `${Paths.state}/brightness.json`
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter

            // The user's own change from the curve's level
            property real offset: 0
        }
    }

    Process {
        id: ddcProc

        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: root.ddcMonitors = text.trim().split("\n\n").filter(d => d.startsWith("Display ")).map(d => ({
                        busNum: d.match(/I2C bus:[ ]*\/dev\/i2c-([0-9]+)/)[1],
                        connector: d.match(/DRM connector:\s+(.*)/)[1].replace(/^card\d+-/, "") // strip "card1-"
                    }))
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessUp"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessDown"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }

    IpcHandler {
        function get(): real {
            return getFor("active");
        }

        // Allows searching by active/model/serial/id/name
        function getFor(query: string): real {
            return root.getMonitor(query)?.brightness ?? -1;
        }

        function set(value: string): string {
            return setFor("active", value);
        }

        // Handles brightness value like brightnessctl: 0.1, +0.1, 0.1-, 10%, +10%, 10%-
        function setFor(query: string, value: string): string {
            const monitor = root.getMonitor(query);
            if (!monitor)
                return "Invalid monitor: " + query;

            let targetBrightness;
            if (value.endsWith("%-")) {
                const percent = parseFloat(value.slice(0, -2));
                targetBrightness = monitor.brightness - (percent / 100);
            } else if (value.startsWith("+") && value.endsWith("%")) {
                const percent = parseFloat(value.slice(1, -1));
                targetBrightness = monitor.brightness + (percent / 100);
            } else if (value.endsWith("%")) {
                const percent = parseFloat(value.slice(0, -1));
                targetBrightness = percent / 100;
            } else if (value.startsWith("+")) {
                const increment = parseFloat(value.slice(1));
                targetBrightness = monitor.brightness + increment;
            } else if (value.endsWith("-")) {
                const decrement = parseFloat(value.slice(0, -1));
                targetBrightness = monitor.brightness - decrement;
            } else if (value.includes("%") || value.includes("-") || value.includes("+")) {
                return `Invalid brightness format: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;
            } else {
                targetBrightness = parseFloat(value);
            }

            if (isNaN(targetBrightness))
                return `Failed to parse value: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;

            monitor.setBrightness(targetBrightness);

            return `Set monitor ${monitor.modelData.name} brightness to ${+monitor.brightness.toFixed(2)}`;
        }

        target: "brightness"
    }

    component Monitor: QtObject {
        id: monitor

        required property ShellScreen modelData
        readonly property var ddcInfo: root.ddcMonitorMap[modelData.name] ?? null
        readonly property bool isDdc: ddcInfo !== null
        readonly property string busNum: ddcInfo?.busNum ?? ""
        readonly property bool isAppleDisplay: root.appleDisplayPresent && modelData.model.startsWith("StudioDisplay")
        // The laptop's own panel (its backlight, brightnessctl)
        readonly property bool isPanel: modelData.name.startsWith("eDP")
        // The laptop's own panel (its backlight, brightnessctl), or a monitor that takes brightness
        // over DDC or Apple's link. Others (one on a USB display adapter) can't be dimmed: brightnessctl
        // would dim the laptop's panel instead
        readonly property bool controllable: isAppleDisplay || isDdc || isPanel
        property real brightness
        property real queuedBrightness: NaN
        property real rampTarget: NaN

        readonly property Process initProc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    if (monitor.isAppleDisplay) {
                        const val = parseInt(text.trim());
                        monitor.brightness = val / 101;
                    } else {
                        const [, , , cur, max] = text.split(" ");
                        monitor.brightness = parseInt(cur) / parseInt(max);
                    }
                }
            }
        }

        readonly property Timer timer: Timer {
            interval: 500
            onTriggered: {
                if (!isNaN(monitor.queuedBrightness)) {
                    monitor.setLevel(monitor.queuedBrightness);
                    monitor.queuedBrightness = NaN;
                }
            }
        }

        // Automatic brightness moves it in steps of up to 5% every 0.05 s
        readonly property Timer rampTimer: Timer {
            interval: 50
            repeat: true
            onTriggered: {
                const left = monitor.rampTarget - monitor.brightness;
                if (isNaN(left) || Math.abs(left) < 0.01) {
                    stop();
                    monitor.rampTarget = NaN;
                    return;
                }
                monitor.setLevel(monitor.brightness + Math.max(-0.05, Math.min(0.05, left)));
            }
        }

        // A change of the user's (keys, the OSD, Settings, the bar, IPC), not automatic brightness's
        signal adjusted

        function setBrightness(value: real): void {
            if (!controllable)
                return;
            value = Math.max(0, Math.min(1, value));
            if (Math.round(brightness * 100) === Math.round(value * 100))
                return;
            rampTimer.stop();
            rampTarget = NaN;
            if (isPanel)
                root.keepOffset(value);
            setLevel(value);
            adjusted();
        }

        function rampTo(value: real): void {
            rampTarget = value;
            if (!rampTimer.running)
                rampTimer.start();
        }

        function setLevel(value: real): void {
            if (!controllable)
                return;
            value = Math.max(0, Math.min(1, value));
            const rounded = Math.round(value * 100);
            if (Math.round(brightness * 100) === rounded)
                return;

            if (isDdc && timer.running) {
                queuedBrightness = value;
                return;
            }

            brightness = value;

            if (isAppleDisplay)
                Quickshell.execDetached(["asdbctl", "set", rounded]);
            else if (isDdc)
                Quickshell.execDetached(["ddcutil", "-b", busNum, "setvcp", "10", rounded]);
            else
                Quickshell.execDetached(["brightnessctl", "s", `${rounded}%`]);

            if (isDdc)
                timer.restart();
        }

        function initBrightness(): void {
            if (!controllable)
                return;
            if (isAppleDisplay)
                initProc.command = ["asdbctl", "get"];
            else if (isDdc)
                initProc.command = ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"];
            else
                initProc.command = ["sh", "-c", "echo a b c $(brightnessctl g) $(brightnessctl m)"];

            initProc.running = true;
        }

        onBusNumChanged: initBrightness()
        Component.onCompleted: initBrightness()
    }
}
