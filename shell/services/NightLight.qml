// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Night light through hyprsunset: on is a warm temperature,
// off is hyprsunset's identity. hyprsunset is started when it isn't running.
Singleton {
    id: root

    readonly property int identity: 6000
    property int temperature: identity
    readonly property bool enabled: temperature < identity
    // The warmth used when it's turned on
    property int warmth: 4000

    function refresh(): void {
        query.running = true;
    }

    function setEnabled(on: bool): void {
        setTemperature(on ? warmth : identity);
    }

    function setTemperature(t: int): void {
        if (t < identity)
            warmth = t;
        temperature = t;
        apply.command = ["sh", "-c", `pgrep -x hyprsunset >/dev/null || { setsid hyprsunset >/dev/null 2>&1 & sleep 0.5; }; ${t < identity ? `hyprctl hyprsunset temperature ${t}` : "hyprctl hyprsunset identity"}`];
        apply.running = true;
    }

    Component.onCompleted: refresh()

    // hyprsunset keeps its temperature while it's off (identity), so whether it's off is asked too.
    // While it isn't running each answer is an error naming its socket (/run/user/1000/…), whose
    // numbers aren't a temperature: only exact answers count, and it's off otherwise
    Process {
        id: query

        command: ["sh", "-c", "hyprctl hyprsunset identity get; hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [identityAnswer, kelvin] = text.trim().split("\n").map(l => l.trim());
                const on = identityAnswer === "false" && /^\d+$/.test(kelvin ?? "");
                root.temperature = on ? parseInt(kelvin) : root.identity;
                if (root.enabled)
                    root.warmth = root.temperature;
            }
        }
    }

    Process {
        id: apply

        onExited: root.refresh()
    }
}
