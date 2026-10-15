// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Taris.Config
import Taris.I18n
import qs.utils

Searcher {
    id: root

    property string currentScheme
    property string currentVariant

    function transformSearch(search: string): string {
        return search.slice(`${GlobalConfig.launcher.actionPrefix}scheme `.length);
    }

    function selector(item: var): string {
        return `${item.title} ${item.name} ${item.flavour}`;
    }

    function reload(): void {
        getCurrent.running = true;
    }

    list: schemes.instances
    useFuzzy: GlobalConfig.launcher.useFuzzy.schemes
    keys: ["title", "name", "flavour"]
    weights: [0.5, 0.4, 0.1]

    Variants {
        id: schemes

        Scheme {}
    }

    Process {
        id: getSchemes

        running: true
        command: ["taris", "scheme", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const schemeData = JSON.parse(text);
                const list = Object.entries(schemeData).map(([name, f]) => Object.entries(f).map(([flavour, colours]) => ({
                                name,
                                flavour,
                                colours
                            })));

                const flat = [];
                for (const s of list)
                    for (const f of s)
                        flat.push(f);

                // From wallpaper first, as Settings has it
                schemes.model = flat.sort((a, b) => (b.name === "dynamic") - (a.name === "dynamic") || String(a.name + a.flavour).localeCompare((b.name + b.flavour)));
            }
        }
    }

    Process {
        id: getCurrent

        running: true
        command: ["taris", "scheme", "get", "-nfv"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [name, flavour, variant] = text.trim().split("\n");
                root.currentScheme = `${name} ${flavour}`;
                root.currentVariant = variant;
            }
        }
    }

    component Scheme: QtObject {
        required property var modelData
        readonly property string name: modelData.name
        readonly property string flavour: modelData.flavour
        readonly property var colours: modelData.colours
        // The dynamic scheme is the one Settings calls From wallpaper (its flavour under it)
        readonly property string title: name === "dynamic" ? Tr.tr("From wallpaper") : flavour
        readonly property string subtitle: name === "dynamic" ? flavour : name

        function onClicked(list: AppList): void {
            list.screenState.launcher = false;
            Quickshell.execDetached(["taris", "scheme", "set", "-n", name, "-f", flavour]);
        }
    }
}
