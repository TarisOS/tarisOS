// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Taris.Config
import qs.services

Scope {
    id: root

    // NordVPN installed, however it was (on first use, the App Store, a terminal), on an account
    // with no VPN configured: it becomes the account's VPN
    readonly property bool nordVpnUnset: {
        DesktopEntries.applications.values; // Again when apps are installed or removed
        return DesktopEntries.byId("nordvpn") !== null && GlobalConfig.utilities.vpn.provider.values.length === 0;
    }

    onNordVpnUnsetChanged: {
        if (nordVpnUnset)
            VPN.addBuiltIn("nordvpn");
    }

    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        Notifs;
        Players;
        Brightness;
        Weather.reload();
        AgentTerminal; // Writes the shell's terminal colours (its terminal only starts when used)
        Stash.restore(); // The apps open again after a Stash
        Tor; // Follows Tor being switched on and off, whatever switches it
        PowerSaver; // Applies Power saver (no blur, solid windows) whenever the profile is on

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
        if (root.nordVpnUnset)
            VPN.addBuiltIn("nordvpn");
    }
}
