// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.utils

// Window style (Settings > Window style): window-style.conf, key=value lines read by
// taris.lua; saving reloads Hyprland. With bordertheme on, the border takes its colours
// from the colour scheme (theme-border.conf, which Colours writes) instead of colors/inactive.
// The border is one colour: solid (empty: the first of colors). opacity is the
// windows' (percent), blur the blur behind windows, blursize and blurpasses the blur's strength
// for everything blurred, shellblur the blur behind the shell's panels (Colours applies it).
Singleton {
    id: root

    // A fresh install: one border colour, the scheme's accent, following scheme changes
    readonly property var defaults: ({
            bordertheme: "1",
            colors: "c4b5fd a855f7 da70d6",
            solid: "",
            inactive: "5b3a7a",
            fade: "1",
            swipe: "1",
            titlebars: "1",
            borderresize: "1",
            roundingon: "1",
            rounding: "70",
            bordersize: "1",
            gapsin: "1",
            gapsout: "1",
            columns: "0",
            floatnew: "0",
            opacity: "80",
            blur: "1",
            blursize: "12",
            blurpasses: "3",
            shellblur: "1"
        })
    property var style: Object.assign({}, defaults)
    // window-style.conf has been read (or isn't there): style is the account's from now on
    property bool styleRead
    // kitty's background opacity, the windows' (taris.lua keeps kitty solid as a window, so only its
    // background is see-through and its text stays sharp: /etc/xdg/kitty/kitty.conf includes this)
    readonly property string kittyConf: `background_opacity ${Math.max(0.3, Math.min(1, (Number(style.opacity) || 80) / 100))}\n`

    function save(changes: var): void {
        style = Object.assign({}, style, changes);
        file.setText(Object.entries(style).map(([k, v]) => `${k}=${v}`).join("\n") + "\n");
        Hypr.reload();
    }

    // Only once both files are read, and only when it changed: running kittys read their config
    // again when it's written
    function writeKittyConf(): void {
        if (!styleRead || !kittyFile.read || kittyConf === kittyFile.current)
            return;
        kittyFile.current = kittyConf;
        kittyFile.setText(kittyConf);
    }

    onKittyConfChanged: writeKittyConf()

    FileView {
        id: file

        path: `${Paths.config}/window-style.conf`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const s = Object.assign({}, root.defaults);
            for (const line of text().split("\n")) {
                const m = line.match(/^\s*(\w+)\s*=\s*(.*?)\s*$/);
                if (m)
                    s[m[1]] = m[2];
            }
            root.style = s;
            root.styleRead = true;
            root.writeKittyConf();
        }
        onLoadFailed: {
            root.styleRead = true;
            root.writeKittyConf();
        }
    }

    FileView {
        id: kittyFile

        property bool read
        property string current

        path: `${Paths.state}/terminal/kitty.conf`
        printErrors: false
        onLoaded: {
            current = text();
            read = true;
            root.writeKittyConf();
        }
        onLoadFailed: {
            read = true;
            root.writeKittyConf();
        }
        onSaved: Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"])
    }
}
