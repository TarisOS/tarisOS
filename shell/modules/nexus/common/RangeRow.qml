// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick

// A number picked with a slider over a range, the way the Witcher's Tweaks settings change it:
// value in from..to, rounded to step, shown through format; committed(value) once the slider
// settles, so dragging doesn't apply every step on the way.
SliderRow {
    id: root

    property real from: 0
    property real to: 1
    property real step: 0
    property real current
    property var format: v => String(v)
    property var pending: null

    signal committed(value: real)

    function snap(v: real): real {
        const x = from + v * (to - from);
        const s = step > 0 ? Math.round((x - from) / step) * step + from : x;
        return Math.max(from, Math.min(to, Number(s.toFixed(4))));
    }

    value: ((pending ?? current) - from) / Math.max(1e-9, to - from)
    valueLabel: format(pending ?? current)
    onMoved: v => {
        pending = snap(v);
        settle.restart();
    }

    Timer {
        id: settle

        interval: 250
        onTriggered: {
            const v = root.pending;
            root.pending = null;
            if (v !== null && v !== root.current)
                root.committed(v);
        }
    }
}
