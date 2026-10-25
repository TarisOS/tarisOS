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
import qs.utils
import qs.modules.nexus.common

// Keyboard, pointer and trackpad, changed the way the Witcher's Tweaks settings change them:
// sliders, switches and choices instead of raw option fields. Applied live and kept (through
// HyprSettings).
PageBase {
    id: root

    // Live values (hyprctl getoption), by option name without "input:"
    property var input: ({})
    property var xkb: ({
            layouts: [],
            variants: [],
            options: []
        })

    readonly property list<string> keys: ["kb_layout", "kb_variant", "kb_options", "repeat_rate", "repeat_delay", "numlock_by_default", "sensitivity", "accel_profile", "left_handed", "natural_scroll", "touchpad:natural_scroll", "touchpad:tap-to-click", "touchpad:clickfinger_behavior", "touchpad:scroll_factor", "touchpad:disable_while_typing", "touchpad:drag_3fg"]

    readonly property list<string> layouts: String(input.kb_layout || "us").split(",").map(s => s.trim()).filter(s => s)
    readonly property list<string> variants: {
        const v = String(input.kb_variant || "").split(",");
        return layouts.map((_, i) => (v[i] ?? "").trim());
    }
    readonly property list<string> kbOptions: String(input.kb_options || "").split(",").map(s => s.trim()).filter(s => s)

    // Chinese, Japanese and Korean typing (/usr/lib/taris/input-method: installed when turned on)
    readonly property var inputMethods: [
        { id: "zh", engine: "fcitx5-chinese-addons", label: Tr.tr("Chinese (Pinyin)") },
        { id: "ja", engine: "fcitx5-mozc", label: Tr.tr("Japanese") },
        { id: "ko", engine: "fcitx5-hangul", label: Tr.tr("Korean") }
    ]
    property list<string> installedInputMethods: []

    property Process _imGet: Process {
        id: imGet

        running: true
        command: ["sh", "-c", "pacman -Qq fcitx5-chinese-addons fcitx5-mozc fcitx5-hangul 2>/dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: root.installedInputMethods = text.split("\n").filter(l => l)
        }
    }

    // In a terminal (pacman asks for the password there); the switches catch up when it closes
    property Process _imSet: Process {
        onExited: root.refreshInputMethods()
    }

    function load(): void {
        inputProc.running = true;
    }

    function set(key: string, value: var): void {
        const values = {};
        values[`input:${key}`] = value;
        setMany(values);
    }

    function setMany(values: var): void {
        HyprSettings.setMany(values);
        const local = Object.assign({}, input);
        for (const [k, v] of Object.entries(values))
            local[k.replace(/^input:/, "")] = v;
        input = local;
    }

    function layoutName(code: string): string {
        return xkb.layouts.find(l => l.code === code)?.name ?? code;
    }

    function saveLayouts(ls: var, vs: var): void {
        setMany({
            "input:kb_layout": ls.join(","),
            "input:kb_variant": vs.join(",")
        });
    }

    function optionIn(prefixes: var): string {
        return kbOptions.find(o => prefixes.some(p => o.startsWith(p))) ?? "";
    }

    function setOption(prefixes: var, value: string): void {
        const rest = kbOptions.filter(o => !prefixes.some(p => o.startsWith(p)));
        if (value)
            rest.push(value);
        set("kb_options", rest.join(","));
    }

    function refreshInputMethods(): void {
        imGet.running = true;
    }

    title: Tr.tr("Keyboard & trackpad")

    Component.onCompleted: load()

    property Process _process1: Process {
        id: inputProc

        command: ["sh", "-c", 'for k in "$@"; do printf "%s\\t" "$k"; hyprctl getoption "input:$k" -j | tr -d "\\n"; echo; done', "sh", ...root.keys]
        stdout: StdioCollector {
            onStreamFinished: {
                const values = {};
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    try {
                        const o = JSON.parse(line.slice(tab + 1));
                        const v = "str" in o ? (o.str === "[[EMPTY]]" ? "" : o.str) : "int" in o ? o.int : "float" in o ? o.float : "bool" in o ? o.bool : null;
                        values[line.slice(0, tab)] = v;
                    } catch (e) {}
                }
                root.input = values;
            }
        }
    }

    property FileView _fileview2: FileView {
        path: "/usr/share/X11/xkb/rules/evdev.lst"
        printErrors: false
        onLoaded: {
            const out = {
                layouts: [],
                variants: [],
                options: []
            };
            let section = "";
            for (const line of text().split("\n")) {
                if (line.startsWith("! ")) {
                    section = line.slice(2).trim();
                    continue;
                }
                const m = line.match(/^\s+(\S+)\s+(.*)$/);
                if (!m)
                    continue;
                if (section === "layout")
                    out.layouts.push({
                        code: m[1],
                        name: m[2]
                    });
                else if (section === "variant") {
                    const v = m[2].match(/^(\S+):\s*(.*)$/);
                    if (v)
                        out.variants.push({
                            layout: v[1],
                            code: m[1],
                            name: v[2]
                        });
                }
            }
            out.layouts.sort((a, b) => a.name.localeCompare(b.name));
            root.xkb = out;
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---------- Keyboard ----------
        SectionHeader {
            first: true
            text: Tr.tr("Keyboard")
        }

        RangeRow {
            first: true
            icon: "keyboard"
            label: Tr.tr("Key repeat rate")
            from: 10
            to: 80
            step: 5
            current: Number(root.input.repeat_rate ?? 25)
            format: v => Tr.tr("%1 per second").arg(Math.round(v))
            onCommitted: v => root.set("repeat_rate", Math.round(v))
        }

        RangeRow {
            icon: "timer"
            label: Tr.tr("Delay until repeat")
            from: 150
            to: 1000
            step: 50
            current: Number(root.input.repeat_delay ?? 600)
            format: v => `${Math.round(v)} ms`
            onCommitted: v => root.set("repeat_delay", Math.round(v))
        }

        ToggleRow {
            last: true
            text: Tr.tr("Num Lock on at start")
            checked: root.input.numlock_by_default === true || root.input.numlock_by_default === 1
            onToggled: root.set("numlock_by_default", checked)
        }

        // ---------- Input sources ----------
        SectionHeader {
            text: Tr.tr("Input sources")
        }

        Repeater {
            model: root.layouts

            ChoiceRow {
                id: layoutRow

                required property string modelData
                required property int index

                first: index === 0
                icon: "language"
                label: root.layoutName(modelData)
                options: [
                    {
                        value: "",
                        label: Tr.tr("Standard")
                    }
                ].concat(root.xkb.variants.filter(v => v.layout === layoutRow.modelData).map(v => ({
                            value: v.code,
                            label: v.name
                        })))
                current: root.variants[index] ?? ""
                onChosen: v => {
                    const vs = [...root.variants];
                    vs[layoutRow.index] = v;
                    root.saveLayouts(root.layouts, vs);
                }
            }
        }

        ChoiceRow {
            icon: "add"
            label: Tr.tr("Add an input source")
            options: root.xkb.layouts.filter(l => !root.layouts.includes(l.code)).map(l => ({
                        value: l.code,
                        label: l.name
                    }))
            current: null
            onChosen: v => root.saveLayouts([...root.layouts, v], [...root.variants, ""])
        }

        ChoiceRow {
            visible: root.layouts.length > 1
            icon: "remove"
            label: Tr.tr("Remove an input source")
            options: root.layouts.map((l, i) => ({
                        value: i,
                        label: root.layoutName(l)
                    }))
            current: null
            onChosen: i => root.saveLayouts(root.layouts.filter((_, j) => j !== i), root.variants.filter((_, j) => j !== i))
        }

        ChoiceRow {
            visible: root.layouts.length > 1
            last: true
            icon: "swap_horiz"
            label: Tr.tr("Switch input sources with")
            options: [
                {
                    value: "",
                    label: Tr.tr("Nothing")
                },
                {
                    value: "fn",
                    label: Tr.tr("Double-tap Fn")
                },
                {
                    value: "grp:alts_toggle",
                    label: Tr.tr("Both Alt keys")
                },
                {
                    value: "grp:alt_shift_toggle",
                    label: "Alt + Shift"
                },
                {
                    value: "grp:ctrl_shift_toggle",
                    label: "Ctrl + Shift"
                },
                {
                    value: "grp:win_space_toggle",
                    label: "Super + Space"
                },
                {
                    value: "grp:caps_toggle",
                    label: "Caps Lock"
                }
            ]
            // Double-tapping Fn is Hyprland's config (taris_fn_switch, on unless turned off), the
            // others are keyboard options: one way at a time
            current: root.optionIn(["grp:"]) || ((HyprSettings.taris.fn_switch ?? true) ? "fn" : "")
            onChosen: v => {
                HyprSettings.setTaris("fn_switch", v === "fn");
                const option = v === "fn" ? "" : v;
                if (option !== root.optionIn(["grp:"]))
                    root.setOption(["grp:"], option);
            }
        }

        // ---------- Input methods (typing in other scripts) ----------
        SectionHeader {
            text: Tr.tr("Input methods")
        }

        // (Made again whenever what's installed is read: each switch shows that, also after a
        // terminal that didn't do it)
        Repeater {
            model: root.inputMethods.map(m => Object.assign({}, m, {
                        installed: root.installedInputMethods.includes(m.engine)
                    }))

            ToggleRow {
                id: imRow

                required property var modelData
                required property int index

                first: index === 0
                last: index === root.inputMethods.length - 1
                text: modelData.label
                checked: modelData.installed
                enabled: !root._imSet.running
                onToggled: {
                    root._imSet.command = [Paths.runApp, "sh", "-c", `exec ${GlobalConfig.general.apps.terminal.join(" ")} -e sh -c '/usr/lib/taris/input-method ${imRow.checked ? "add" : "remove"} ${imRow.modelData.id}; echo; read -p "Press Enter to close" _'`];
                    root._imSet.running = true;
                }
            }
        }

        // ---------- Special keys ----------
        SectionHeader {
            text: Tr.tr("Special keys")
        }

        ChoiceRow {
            first: true
            label: Tr.tr("Compose key")
            options: [
                {
                    value: "",
                    label: Tr.tr("None")
                },
                {
                    value: "compose:caps",
                    label: "Caps Lock"
                },
                {
                    value: "compose:ralt",
                    label: Tr.tr("Right Alt")
                },
                {
                    value: "compose:rctrl",
                    label: Tr.tr("Right Ctrl")
                },
                {
                    value: "compose:menu",
                    label: Tr.tr("Menu")
                },
                {
                    value: "compose:rwin",
                    label: Tr.tr("Right Super")
                }
            ]
            current: root.optionIn(["compose:"])
            onChosen: v => root.setOption(["compose:"], v)
        }

        ChoiceRow {
            label: Tr.tr("Caps Lock key")
            options: [
                {
                    value: "",
                    label: "Caps Lock"
                },
                {
                    value: "ctrl:nocaps",
                    label: "Control"
                },
                {
                    value: "caps:escape",
                    label: "Escape"
                },
                {
                    value: "caps:swapescape",
                    label: Tr.tr("Swap with Escape")
                },
                {
                    value: "caps:none",
                    label: Tr.tr("Nothing")
                }
            ]
            current: root.optionIn(["ctrl:nocaps", "caps:"])
            onChosen: v => root.setOption(["ctrl:nocaps", "caps:"], v)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Swap left Ctrl and left Super")
            checked: root.kbOptions.includes("ctrl:swap_lwin_lctl")
            onToggled: root.setOption(["ctrl:swap_lwin_lctl"], checked ? "ctrl:swap_lwin_lctl" : "")
        }

        // ---------- Pointer ----------
        SectionHeader {
            text: Tr.tr("Pointer")
        }

        RangeRow {
            first: true
            icon: "speed"
            label: Tr.tr("Tracking speed")
            from: -1
            to: 1
            step: 0.05
            current: Number(root.input.sensitivity ?? 0)
            format: v => v === 0 ? Tr.tr("Default") : `${v > 0 ? "+" : ""}${Math.round(v * 100)}%`
            onCommitted: v => root.set("sensitivity", Number(v.toFixed(2)))
        }

        ToggleRow {
            text: Tr.tr("Pointer acceleration")
            checked: root.input.accel_profile !== "flat"
            onToggled: root.set("accel_profile", checked ? "adaptive" : "flat")
        }

        ToggleRow {
            text: Tr.tr("Natural scrolling for mice")
            checked: root.input.natural_scroll === true || root.input.natural_scroll === 1
            onToggled: root.set("natural_scroll", checked)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Left-handed")
            checked: root.input.left_handed === true || root.input.left_handed === 1
            onToggled: root.set("left_handed", checked)
        }

        // ---------- Trackpad ----------
        SectionHeader {
            text: Tr.tr("Trackpad")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Natural scrolling")
            checked: root.input["touchpad:natural_scroll"] === true || root.input["touchpad:natural_scroll"] === 1
            onToggled: root.set("touchpad:natural_scroll", checked)
        }

        ToggleRow {
            text: Tr.tr("Tap to click")
            checked: root.input["touchpad:tap-to-click"] === true || root.input["touchpad:tap-to-click"] === 1
            onToggled: root.set("touchpad:tap-to-click", checked)
        }

        ToggleRow {
            text: Tr.tr("Click with two fingers to right-click")
            checked: root.input["touchpad:clickfinger_behavior"] === true || root.input["touchpad:clickfinger_behavior"] === 1
            onToggled: root.set("touchpad:clickfinger_behavior", checked)
        }

        RangeRow {
            icon: "swipe_vertical"
            label: Tr.tr("Scrolling speed")
            from: 0.1
            to: 2
            step: 0.05
            current: Number(root.input["touchpad:scroll_factor"] ?? 1)
            format: v => `${Math.round(v * 100)}%`
            onCommitted: v => root.set("touchpad:scroll_factor", Number(v.toFixed(2)))
        }

        ToggleRow {
            text: Tr.tr("Ignore the trackpad while typing")
            checked: root.input["touchpad:disable_while_typing"] === true || root.input["touchpad:disable_while_typing"] === 1
            onToggled: root.set("touchpad:disable_while_typing", checked)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Three-finger drag")
            checked: Number(root.input["touchpad:drag_3fg"] ?? 0) > 0
            onToggled: root.set("touchpad:drag_3fg", checked ? 1 : 0)
        }
    }
}
