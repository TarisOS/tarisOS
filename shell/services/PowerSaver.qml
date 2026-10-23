// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Taris.Config
import qs.services

// Power saver (the power profile, Settings > Power or the bar's battery popout) turns off what costs
// power without changing what can be done: nothing is blurred, every window is solid, Hyprland draws
// no animations or shadows, and the shell's animations are off (every duration 0, the decorative
// loops paused, no panel wobble). Hyprland's part is applied on the running Hyprland, and again
// after each of its config reloads; switching back reloads Hyprland's config, which puts the Window
// style's values back (taris.lua). kitty's see-through background follows (WindowStyle.kittyConf);
// the built-in display's brightness, Brightness.
Singleton {
    id: root

    readonly property bool active: PowerProfiles.profile === PowerProfile.PowerSaver
    property bool applied

    function apply(): void {
        Tokens.anim.durations.setSuspended(active);
        if (active) {
            if (Hypr.usingLua)
                Hypr.extras.batchMessage(["eval hl.config({ animations = { enabled = false }, decoration = { active_opacity = 1, inactive_opacity = 1, blur = { enabled = false }, shadow = { enabled = false } } })"]);
            else
                Hypr.extras.batchMessage(["keyword animations:enabled false", "keyword decoration:active_opacity 1", "keyword decoration:inactive_opacity 1", "keyword decoration:blur:enabled false", "keyword decoration:shadow:enabled false"]);
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
