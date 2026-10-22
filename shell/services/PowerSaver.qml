// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.services

// Power saver (the power profile, Settings > Power or the bar's battery popout): nothing is blurred
// and every window is solid while it's on. Applied on the running Hyprland, and again after each of
// its config reloads; switching back reloads Hyprland's config, which puts the Window style's blur
// and opacity back (taris.lua). kitty's see-through background follows (WindowStyle.kittyConf).
Singleton {
    id: root

    readonly property bool active: PowerProfiles.profile === PowerProfile.PowerSaver
    property bool applied

    function apply(): void {
        if (active) {
            if (Hypr.usingLua)
                Hypr.extras.batchMessage(["eval hl.config({ decoration = { active_opacity = 1, inactive_opacity = 1, blur = { enabled = false } } })"]);
            else
                Hypr.extras.batchMessage(["keyword decoration:active_opacity 1", "keyword decoration:inactive_opacity 1", "keyword decoration:blur:enabled false"]);
            applied = true;
        } else if (applied) {
            applied = false;
            Hypr.reload();
        }
    }

    onActiveChanged: apply()
    Component.onCompleted: apply()

    // Again after a config reload, and once it's known whether the config is Lua (the syntax differs)
    Connections {
        function onConfigReloaded(): void {
            if (root.active)
                root.apply();
        }

        function onUsingLuaChanged(): void {
            if (root.active)
                root.apply();
        }

        target: Hypr
    }
}
