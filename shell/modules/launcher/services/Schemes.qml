// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Taris.Config
import Taris.I18n
import qs.services
import qs.utils

Searcher {
    id: root

    property string currentScheme
    property string currentVariant
    // The CLI's schemes (taris scheme list)
    property var cliSchemes: []

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

    // The saved themes first (Taris among them), as Settings > Colours has them: their own colours
    // over their scheme's
    Variants {
        id: schemes

        model: Colours.customThemes.map(t => ({
                    name: t.scheme,
                    flavour: t.flavour,
                    colours: Object.assign({}, root.cliSchemes.find(s => s.name === t.scheme && s.flavour === t.flavour)?.colours ?? {}, t.colours ?? {}),
                    theme: t
                })).concat(root.cliSchemes)

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
                root.cliSchemes = flat.sort((a, b) => (b.name === "dynamic") - (a.name === "dynamic") || String(a.name + a.flavour).localeCompare((b.name + b.flavour)));
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
        // A saved theme (Settings > Colours), undefined for a scheme
        readonly property var theme: modelData.theme
        // The dynamic scheme is the one Settings calls From wallpaper (its flavour under it)
        readonly property string title: theme ? theme.name : name === "dynamic" ? Tr.tr("From wallpaper") : flavour
        readonly property string subtitle: name === "dynamic" ? flavour : name

        function onClicked(list: AppList): void {
            list.screenState.launcher = false;
            if (theme)
                Colours.applyCustomTheme(theme);
            else
                Quickshell.execDetached(["taris", "scheme", "set", "-n", name, "-f", flavour]);
        }
    }
}
