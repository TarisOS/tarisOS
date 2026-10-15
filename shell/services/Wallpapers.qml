// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris
import Taris.Config
import Taris.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")
    // TarisOS's own wallpapers (taris-wallpapers), in the wallpaper folder through a link
    readonly property string builtinDir: "/usr/share/backgrounds/taris"

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    // The current wallpaper's file, links followed: the same file can be listed through a link to
    // its folder (~/Pictures/Wallpapers/TarisOS is /usr/share/backgrounds/taris)
    readonly property string actualCurrentFile: CUtils.canonicalPath(actualCurrent)
    property bool previewColourLock
    property bool pendingPreviewClear
    // The display Settings > Wallpaper & Style sets the wallpaper of (its output name), "" for all
    property string pickFor

    // A display's wallpaper: its own, else the shared one
    function wallpaperOf(name: string): string {
        return (name ? GlobalConfig.forScreen(name).background.wallpaper : "") || current;
    }

    // A wallpaper from Settings, for pickFor's display or every display. The main display's is
    // the shared one, which the colours follow: a display that isn't the main one gets its own
    function pick(path: string): void {
        const name = Quickshell.screens.some(s => s.name === pickFor) ? pickFor : "";
        if (name && name !== Screens.mainName) {
            GlobalConfig.forScreen(name).background.wallpaper = path;
            return;
        }
        clearOwn(name);
        setWallpaper(path);
    }

    // A random one of those Settings shows, the same way as pick()
    function pickRandom(): void {
        const name = Quickshell.screens.some(s => s.name === pickFor) ? pickFor : "";
        if (name && name !== Screens.mainName) {
            if (list.length > 0)
                GlobalConfig.forScreen(name).background.wallpaper = list[Math.floor(Math.random() * list.length)].path;
            return;
        }
        clearOwn(name);
        setRandom();
    }

    // The display's own wallpaper goes (every display's when name is "")
    function clearOwn(name: string): void {
        for (const s of Quickshell.screens)
            if ((!name || s.name === name) && GlobalConfig.forScreen(s.name).background.wallpaper)
                GlobalConfig.forScreen(s.name).background.wallpaper = "";
    }

    function isCurrent(path: string): bool {
        return CUtils.canonicalPath(path) === actualCurrentFile;
    }

    function isBuiltin(w: FileSystemEntry): bool {
        return CUtils.canonicalPath(w.parentDir) === builtinDir;
    }

    // By name, numbered ones in their order (2 before 10)
    function compareNames(a: FileSystemEntry, b: FileSystemEntry): int {
        const na = Number(a.baseName);
        const nb = Number(b.baseName);
        if (a.baseName && b.baseName && !isNaN(na) && !isNaN(nb))
            return na - nb;
        return a.name.localeCompare(b.name);
    }

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    // Any wallpaper the settings page shows, whatever its size (-n)
    function setRandom(): void {
        Quickshell.execDetached(["taris", "wallpaper", "-r", "-n", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["taris", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["taris", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["taris", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    Process {
        id: getPreviewColoursProc

        command: ["taris", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
