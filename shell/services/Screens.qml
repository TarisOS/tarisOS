// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Taris.Config
import qs.utils

Singleton {
    id: root

    // The monitor keys whose shell settings folder is in place (configOf): a display's old folder,
    // named after its output, is copied to its monitor's first if that has none, so the config is
    // never read from the new folder before its files are there (it wouldn't see them arrive)
    property list<string> foldersReady: []

    // The display that always has the shell (Settings > Displays): the chosen one while it's
    // connected, else the built-in one (eDP), else the first (a Mac without one), so the shell is
    // never left on no display at all
    readonly property string mainName: nameOf(GlobalConfig.general.mainDisplay) || (Quickshell.screens.find(s => isBuiltIn(s.name))?.name ?? Quickshell.screens[0]?.name ?? "")
    // The displays with the shell (bar, dock and panels): the main one, and the others where it's
    // turned on (off by default)
    readonly property list<ShellScreen> screens: Quickshell.screens.filter(s => s.name === mainName || GlobalConfig.forScreen(configOf(s.name)).enabled)
    // Every display, by its number (numberOf)
    readonly property list<ShellScreen> ordered: Quickshell.screens.slice().sort((a, b) => ((numberOf(a.name) || 1000) - (numberOf(b.name) || 1000)) || a.name.localeCompare(b.name))
    // Every connected display's key (keyOf), changing as displays come and go and Hyprland names
    // their monitors
    readonly property list<string> keys: Quickshell.screens.map(s => keyOf(s.name))
    // The keys of the connected displays Hyprland has described, the ones that can be numbered
    readonly property list<string> describedKeys: Quickshell.screens.filter(s => known(s.name)).map(s => keyOf(s.name))
    // Each monitor's number, by key (keyOf, as its arrangement): given the first time the monitor is
    // seen and kept for good, so the same monitor always has the same number, wherever it's placed
    // and whichever others are plugged in
    readonly property var numbers: numbersAdapter.numbers
    property bool numbersLoaded

    function isExcluded(screen: ShellScreen): bool {
        return !screens.includes(screen);
    }

    // A display's number (1, 2…) in Settings and Identify, 0 until it has one
    function numberOf(name: string): int {
        return numbers[keyOf(name)] ?? 0;
    }

    // Numbers the monitors seen for the first time: each the lowest number not given yet, the
    // built-in display first
    function numberNew(): void {
        if (!numbersLoaded)
            return;
        const given = Object.assign({}, numbers);
        const fresh = Quickshell.screens.filter(s => known(s.name) && !given[keyOf(s.name)]).sort((a, b) => (isBuiltIn(b.name) - isBuiltIn(a.name)) || keyOf(a.name).localeCompare(keyOf(b.name)));
        if (fresh.length === 0)
            return;
        for (const s of fresh) {
            const taken = Object.values(given);
            let n = 1;
            while (taken.includes(n))
                n++;
            given[keyOf(s.name)] = n;
        }
        numbersAdapter.numbers = given;
    }

    // The Mac's own display (its panel is eDP)
    function isBuiltIn(name: string): bool {
        return name.startsWith("eDP");
    }

    // The monitor on an output, as Hyprland describes it: make, model and serial ("" for the
    // built-in panel, which has no EDID, or while Hyprland hasn't said yet)
    function descriptionOf(name: string): string {
        return Hyprland.monitors.values.find(m => m.name === name)?.description ?? "";
    }

    // Hyprland has described the monitor on an output (its id comes with the description)
    function known(name: string): bool {
        return (Hyprland.monitors.values.find(m => m.name === name)?.id ?? -1) >= 0;
    }

    // What a display's settings are kept under (its arrangement, the main display, its own shell
    // settings): "desc:<description>" when no other connected display has the same description, so
    // they follow the monitor to any port, adapter or adapter output; else the output's name (the
    // built-in panel, and identical monitors without serial numbers, which nothing else tells
    // apart)
    function keyOf(name: string): string {
        const desc = descriptionOf(name);
        if (!desc || Quickshell.screens.filter(s => descriptionOf(s.name) === desc).length !== 1)
            return name;
        return `desc:${desc}`;
    }

    // The connected display (its output's name) a key belongs to, "" for none
    function nameOf(key: string): string {
        if (!key)
            return "";
        return Quickshell.screens.find(s => s.name === key || keyOf(s.name) === key)?.name ?? "";
    }

    // The folder of a display's own shell settings (~/.config/taris/monitors/<this>/): its key,
    // without the "desc:", once in place (else its output's name, as before)
    function configOf(name: string): string {
        const key = keyOf(name);
        return key.startsWith("desc:") && foldersReady.includes(key) ? folderFor(key) : name;
    }

    function folderFor(key: string): string {
        return key.slice(5).replace(/\//g, "-");
    }

    // Puts the folders of newly seen monitors in place, then lets configOf use them
    function prepareFolders(): void {
        if (folderProc.running)
            return;
        const pending = Quickshell.screens.map(s => ({
                    name: s.name,
                    key: keyOf(s.name)
                })).filter(d => d.key.startsWith("desc:") && !foldersReady.includes(d.key));
        if (pending.length === 0)
            return;
        const dir = `${Paths.config}/monitors`;
        folderProc.keys = pending.map(d => d.key);
        folderProc.command = ["sh", "-c", 'while [ $# -gt 1 ]; do [ -e "$2" ] || { [ -d "$1" ] && cp -r "$1" "$2"; }; shift 2; done; exit 0', "sh"].concat(...pending.map(d => [`${dir}/${d.name}`, `${dir}/${folderFor(d.key)}`]));
        folderProc.running = true;
    }

    onKeysChanged: prepareFolders()
    onDescribedKeysChanged: numberNew()
    Component.onCompleted: prepareFolders()

    FileView {
        path: `${Paths.config}/display-numbers.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            root.numbersLoaded = true;
            root.numberNew();
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
            root.numbersLoaded = true;
            root.numberNew();
        }

        JsonAdapter {
            id: numbersAdapter

            property var numbers: ({})
        }
    }

    Process {
        id: folderProc

        property list<string> keys

        onExited: {
            root.foldersReady = [...new Set(root.foldersReady.concat(keys))];
            root.prepareFolders();
        }
    }
}
